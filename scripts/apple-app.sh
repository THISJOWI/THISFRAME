#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/thisjellyfix.xcodeproj"
ACTION="${1:-run}"
PLATFORM="${2:-ios}"
DEVICE_ID="${DEVICE_ID:-}"
DEVICE_KIND="${DEVICE_KIND:-}"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/.build/DerivedData}"

usage() {
  cat <<'EOF'
Uso: scripts/apple-app.sh [build|run|hub] [ios|macos|tvos|visionos]

Sin DEVICE_ID muestra un menú con los dispositivos detectados.
DEVICE_ID=<UDID> salta el menú y usa ese dispositivo.
DERIVED_DATA=<ruta> cambia el directorio de compilación.
EOF
}

[[ "$ACTION" == build || "$ACTION" == run || "$ACTION" == hub ]] || { usage >&2; exit 2; }
case "$PLATFORM" in
  ios) SCHEME="thisjellyfix-iOS"; XCODE_PLATFORM="iOS"; BUNDLE_ID="com.thisjellyfix.ios" ;;
  macos) SCHEME="thisjellyfix-macOS"; XCODE_PLATFORM="macOS"; BUNDLE_ID="com.thisjellyfix.macos" ;;
  tvos) SCHEME="thisjellyfix-tvOS"; XCODE_PLATFORM="tvOS"; BUNDLE_ID="com.thisjellyfix.tvos" ;;
  visionos) SCHEME="thisjellyfix-visionOS"; XCODE_PLATFORM="visionOS"; BUNDLE_ID="com.thisjellyfix.visionos" ;;
  *) usage >&2; exit 2 ;;
esac

command -v xcodebuild >/dev/null || { echo "No se encontró Xcode Command Line Tools. Instala/selecciona Xcode." >&2; exit 1; }
[[ -d "$PROJECT" ]] || { echo "No existe el proyecto: $PROJECT" >&2; exit 1; }

open_device_hub() {
  local hub="$(xcode-select -p)/Applications/Device Hub.app"
  if [[ -d "$hub" ]]; then
    open "$hub"
  else
    echo "Device Hub no está instalado en el Xcode seleccionado. Abre Xcode > Open Developer Tool > Device Hub." >&2
  fi
}

if [[ "$ACTION" == hub ]]; then open_device_hub; exit 0; fi

# ¿Hay algún certificado de firma de Apple en este equipo?
#
# Compilar para un dispositivo físico exige un certificado "Apple
# Development" (o "Apple Distribution") con clave privada. Sin él, el build
# muere en el paso de firma con "No signing certificate ... found". El
# simulador firma ad-hoc y no necesita certificado, así que cuando no hay
# identidad se compila para el simulador en su lugar.
has_signing_identity() {
  local count
  # sed -E: el sed de macOS (BSD) no entiende "\+" en modo básico.
  count="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -nE 's/^[[:space:]]*([0-9]+) valid identities found.*/\1/p')"
  [[ -n "$count" && "$count" -gt 0 ]]
}

# Primer destino que encaje con la plataforma pedida y el tipo de equipo.
# "$3" es "" para un dispositivo físico o "Simulator" para el simulador.
pick_destination() {
  printf '%s\n' "$1" | python3 -c '
import re, sys
platforms = {"ios": "iOS", "tvos": "tvOS", "visionos": "visionOS"}
wanted, kind, suffix = platforms[sys.argv[1]], sys.argv[2].lower(), sys.argv[3]
if suffix:
    wanted = wanted + " " + suffix
for line in sys.stdin:
    # xcodebuild imprime "id:XXXX" SIN espacio tras los dos puntos; con
    # "id: " la busqueda no encontraba nunca ningun destino y se caia al
    # destino generico (que exige certificado de firma).
    match = re.search(r"platform:([^,]+),.*?id:\s*([^,}]+)", line)
    if not match or match.group(1) != wanted:
        continue
    identifier = match.group(2).strip()
    # "Any iOS Device" / "Any iOS Simulator Device" son marcadores de
    # posicion, no equipos reales: no se pueden instalar ni arrancar.
    if identifier.endswith(":placeholder") or "Placeholder" in identifier:
        continue
    if not kind or kind in line.lower():
        print(f"platform={wanted},id={identifier}")
        break
' "$2" "$DEVICE_KIND" "$3"
}

SHOW_DESTINATIONS_OUTPUT=""

load_destinations() {
  if [[ -z "$SHOW_DESTINATIONS_OUTPUT" ]]; then
    echo "Buscando dispositivos disponibles para ${XCODE_PLATFORM}…"
    SHOW_DESTINATIONS_OUTPUT="$(xcodebuild -showdestinations -project "$PROJECT" -scheme "$SCHEME" 2>/dev/null || true)"
  fi
}

# Destinos compatibles con el esquema, uno por línea y separados por tabulador:
#   <id>	<nombre>	<physical|simulator>	<versión de OS>
# Los físicos salen de la sección "Destinations compatible" de xcodebuild (los
# incompatibles no se pueden instalar); los simuladores, de simctl, porque
# xcodebuild no siempre los enumera. El tipo pedido (iPhone en iphone.sh, iPad
# en ipad.sh) va primero para que la opción 1 sea la esperada; después los
# físicos y, por último, los simuladores.
parse_menu_destinations() {
  printf '%s\n' "$1" | python3 -c '
import json, re, subprocess, sys

want = sys.argv[1]
preferred = sys.argv[2].lower()
runtime_prefix = {"iOS": "iOS", "tvOS": "tvOS", "visionOS": "xrOS"}.get(want, want)
rows = []
seen = set()

def add(kind, device_id, label, version):
    if not device_id or device_id in seen:
        return
    seen.add(device_id)
    rows.append((kind, device_id, label, version))

in_compatible = False
for line in sys.stdin:
    if "Destinations compatible" in line:
        in_compatible = True
        continue
    if "Destinations incompatible" in line:
        break
    if not in_compatible or "{" not in line:
        continue
    text = line.strip()
    platform = re.search(r"platform:\s*([^,}]+)", text)
    identifier = re.search(r"\bid:\s*([^,}\s]+)", text)
    name = re.search(r"\bname:([^,}]+)", text)
    os_version = re.search(r"\bOS:\s*([^,}]+)", text)
    if not (platform and identifier and name):
        continue
    value = platform.group(1).strip()
    if value == want:
        kind = "physical"
    elif value == want + " Simulator":
        kind = "simulator"
    else:
        continue
    device_id = identifier.group(1).strip()
    if device_id.endswith(":placeholder") or "Placeholder" in device_id:
        continue
    label = name.group(1).strip()
    version = os_version.group(1).strip() if os_version else ""
    add(kind, device_id, label, version)

# Fuente estable de simuladores instalados, independiente del esquema.
try:
    payload = subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "-j"],
        stderr=subprocess.DEVNULL,
    )
    devices_by_runtime = json.loads(payload).get("devices", {})
except Exception:
    devices_by_runtime = {}

for runtime, devices in devices_by_runtime.items():
    if f"SimRuntime.{runtime_prefix}-" not in runtime:
        continue
    version_match = re.search(r"SimRuntime\.[A-Za-z]+-([0-9-]+)$", runtime)
    version = version_match.group(1).replace("-", ".") if version_match else ""
    for device in devices:
        if device.get("isAvailable") is False:
            continue
        add("simulator", device.get("udid", ""), device.get("name", ""), version)

rows.sort(key=lambda row: (
    0 if preferred and preferred in row[2].lower() else 1,
    0 if row[0] == "physical" else 1,
))
for kind, device_id, label, version in rows:
    print(f"{device_id}\t{label}\t{kind}\t{version}")
' "$XCODE_PLATFORM" "$DEVICE_KIND"
}

SELECTED_DESTINATION=""
SELECTED_KIND=""

# El calificador de plataforma de xcodebuild distingue el dispositivo del
# simulador: "iOS" no resuelve un UDID de simulador, hace falta "iOS Simulator".
destination_for_id() {
  if [[ "$1" == "simulator" ]]; then
    echo "platform=$XCODE_PLATFORM Simulator,id=$2"
  else
    echo "platform=$XCODE_PLATFORM,id=$2"
  fi
}

# Un UDID solo dice si es simulador consultando simctl; los físicos no salen ahí.
device_kind_for_id() {
  if xcrun simctl list devices 2>/dev/null | grep -q -- "$1"; then
    echo "simulator"
  fi
}

# Menú numerado. $1 = 1 restringe a simuladores (fallback sin certificado).
# Devuelve 1 si no hay ningún destino que mostrar; q sale sin compilar.
choose_device_interactively() {
  local only_simulators="${1:-0}"
  local ids=() names=() kinds=() versions=()

  load_destinations
  [[ -n "$SHOW_DESTINATIONS_OUTPUT" ]] || return 1

  while IFS=$'\t' read -r device_id device_name device_kind device_version; do
    [[ -n "$device_id" ]] || continue
    if [[ "$only_simulators" == 1 && "$device_kind" != "simulator" ]]; then
      continue
    fi
    ids+=("$device_id")
    names+=("$device_name")
    kinds+=("$device_kind")
    versions+=("$device_version")
  done < <(parse_menu_destinations "$SHOW_DESTINATIONS_OUTPUT")

  local count="${#ids[@]}"
  (( count > 0 )) || return 1

  if [[ "$only_simulators" == 1 ]]; then
    echo "Sin certificado de firma: elige un simulador para ${XCODE_PLATFORM}."
  else
    echo "Dispositivos detectados para ${XCODE_PLATFORM}:"
  fi

  local i label choice number index
  for ((i = 0; i < count; i++)); do
    if [[ "${kinds[$i]}" == "simulator" ]]; then
      label="simulador"
      if [[ -n "${versions[$i]}" ]]; then
        label="simulador, ${XCODE_PLATFORM} ${versions[$i]}"
      fi
    else
      label="físico"
    fi
    printf '  %2d) %s (%s)\n' "$((i + 1))" "${names[$i]}" "$label"
  done
  echo "   m) escribir un ID manualmente"
  echo "   q) cancelar"

  while true; do
    if ! read -r -p "Elige [1]: " choice; then
      echo
      echo "Cancelado."
      exit 0
    fi
    choice="${choice//[[:space:]]/}"
    case "$choice" in
      "")
        choice="1"
        ;;
      q|Q)
        echo "Cancelado."
        exit 0
        ;;
      m|M)
        if ! read -r -p "ID del dispositivo (UDID): " choice; then
          echo
          echo "Cancelado."
          exit 0
        fi
        choice="${choice//[[:space:]]/}"
        if [[ -z "$choice" ]]; then
          echo "ID vacío." >&2
          continue
        fi
        SELECTED_KIND="$(device_kind_for_id "$choice")"
        SELECTED_DESTINATION="$(destination_for_id "$SELECTED_KIND" "$choice")"
        echo "Seleccionado: $choice"
        return 0
        ;;
    esac

    if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
      echo "Opción no válida." >&2
      continue
    fi
    number="$((10#$choice))"
    if (( number < 1 || number > count )); then
      echo "Opción fuera de rango (1-$count)." >&2
      continue
    fi

    index="$((number - 1))"
    SELECTED_KIND="${kinds[$index]}"
    SELECTED_DESTINATION="$(destination_for_id "$SELECTED_KIND" "${ids[$index]}")"
    echo "Seleccionado: ${names[$index]} (${kinds[$index]})"
    return 0
  done
}

DESTINATION=""
if [[ -n "$DEVICE_ID" ]]; then
  DESTINATION="$(destination_for_id "$(device_kind_for_id "$DEVICE_ID")" "$DEVICE_ID")"
elif [[ "$PLATFORM" == macos ]]; then
  DESTINATION="platform=macOS"
elif [[ -t 0 ]]; then
  if choose_device_interactively; then
    DESTINATION="$SELECTED_DESTINATION"
    # Una elección explícita de dispositivo físico sin certificado no se
    # ignora en silencio: se avisa y se ofrece la lista de simuladores.
    if [[ "$SELECTED_KIND" != "simulator" ]] && ! has_signing_identity; then
      echo "Este equipo no tiene ningún certificado de firma de Apple: no puedo firmar para un dispositivo físico." >&2
      if choose_device_interactively 1; then
        DESTINATION="$SELECTED_DESTINATION"
      else
        echo "No hay simuladores disponibles para ${XCODE_PLATFORM}." >&2
        exit 1
      fi
    fi
  else
    echo "No hay dispositivos compatibles. Compilaré para destino genérico y abriré Device Hub."
    DESTINATION="generic/platform=$XCODE_PLATFORM"
    open_device_hub
  fi
else
  echo "Buscando dispositivos disponibles para ${PLATFORM}…"
  DESTINATIONS="$(xcodebuild -showdestinations -project "$PROJECT" -scheme "$SCHEME" 2>/dev/null || true)"
  # Preferir dispositivos físicos. Después, elegir simuladores por nombre estable.
  DESTINATION="$(pick_destination "$DESTINATIONS" "$PLATFORM" "")"
  if [[ -n "$DESTINATION" && "$DESTINATION" != *Simulator* ]] && ! has_signing_identity; then
    echo "Este equipo no tiene ningún certificado de firma de Apple: la compilación para el dispositivo fallaría. Compilo para el simulador."
    DESTINATION="$(pick_destination "$DESTINATIONS" "$PLATFORM" "Simulator")"
  fi
  if [[ -z "$DESTINATION" ]]; then
    DESTINATION="$(pick_destination "$DESTINATIONS" "$PLATFORM" "Simulator")"
  fi
fi

if [[ -z "$DESTINATION" ]]; then
  echo "No hay un dispositivo emparejado ni un simulador disponible. Compilaré para destino genérico y abriré Device Hub."
  DESTINATION="generic/platform=$XCODE_PLATFORM"
  open_device_hub
fi

echo "Destino: $DESTINATION"
# -allowProvisioningUpdates: con firma automática, deja que Xcode cree (o
# refresque) el certificado y el perfil de aprovisionamiento. Sin este flag el
# build muere con "No signing certificate ... found" la primera vez.
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" -configuration Debug build -allowProvisioningUpdates

[[ "$ACTION" == run ]] || exit 0

# El bundle vive en una carpeta según la plataforma: Debug-iphoneos para el
# dispositivo, Debug-iphonesimulator para el simulador y Debug para macOS.
app_path() {
  local destination="$1" platform="$2" variant
  case "$platform" in
    macos) variant="Debug" ;;
    ios) variant="Debug-iphoneos" ;;
    tvos) variant="Debug-appletvos" ;;
    visionos) variant="Debug-xros" ;;
    *) variant="Debug" ;;
  esac
  if [[ "$destination" == *Simulator* ]]; then
    case "$platform" in
      ios) variant="Debug-iphonesimulator" ;;
      tvos) variant="Debug-appletvsimulator" ;;
      visionos) variant="Debug-xrsimulator" ;;
    esac
  fi
  echo "$DERIVED_DATA/Build/Products/$variant/THISFRAME.app"
}

APP="$(app_path "$DESTINATION" "$PLATFORM")"
if [[ ! -d "$APP" ]]; then
  echo "No se encontró la app compilada en $APP" >&2
  exit 1
fi
if [[ "$PLATFORM" == macos ]]; then
  open "$APP"
elif [[ "$DESTINATION" == *Simulator* ]]; then
  DEVICE_ID="$(printf '%s' "$DESTINATION" | sed -nE 's/.*id=([^,]+).*/\1/p')"
  xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
  xcrun simctl bootstatus "$DEVICE_ID" -b
  xcrun simctl install "$DEVICE_ID" "$APP"
  xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID"
elif [[ "$DESTINATION" != generic/* ]]; then
  DEVICE_ID="$(printf '%s' "$DESTINATION" | sed -nE 's/.*id=([^,]+).*/\1/p')"
  xcrun devicectl device install app --device "$DEVICE_ID" "$APP"
  # El primer arranque en un equipo nuevo falla hasta que el usuario confía
  # en el perfil: se instala pero no arranca. Se explica en vez de volcar
  # el error crudo de devicectl.
  if ! LAUNCH_OUT="$(xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID" 2>&1)"; then
    echo "$LAUNCH_OUT"
    if grep -q "has not been explicitly trusted" <<<"$LAUNCH_OUT"; then
      {
        echo
        echo "La app está instalada, pero el iPhone todavía no confía en el perfil de firma."
        echo "En el iPhone: Ajustes › General › VPN y gestión de dispositivos ›"
        echo "  «Apple Development: …» › Confiar."
        echo "Si sigue sin arrancar: Ajustes › Privacidad y seguridad › Modo desarrollador (activar y reiniciar)."
      } >&2
    fi
    exit 1
  fi
  echo "$LAUNCH_OUT"
else
  echo "Compilación lista. Selecciona un dispositivo en Device Hub para instalar y ejecutar la app."
fi
