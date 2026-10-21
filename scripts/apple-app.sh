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

DEVICE_ID=<UDID> permite seleccionar un dispositivo concreto.
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

DESTINATION=""
if [[ -n "$DEVICE_ID" ]]; then
  DESTINATION="platform=$XCODE_PLATFORM,id=$DEVICE_ID"
elif [[ "$PLATFORM" == macos ]]; then
  DESTINATION="platform=macOS"
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
