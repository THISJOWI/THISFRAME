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

DESTINATION=""
if [[ -n "$DEVICE_ID" ]]; then
  DESTINATION="platform=$XCODE_PLATFORM,id=$DEVICE_ID"
elif [[ "$PLATFORM" == macos ]]; then
  DESTINATION="platform=macOS"
else
  echo "Buscando dispositivos disponibles para ${PLATFORM}…"
  DESTINATIONS="$(xcodebuild -showdestinations -project "$PROJECT" -scheme "$SCHEME" 2>/dev/null || true)"
  # Preferir dispositivos físicos. Después, elegir simuladores por nombre estable.
  DESTINATION="$(printf '%s\n' "$DESTINATIONS" | python3 -c '
import re, sys
platforms = {"ios": "iOS", "tvos": "tvOS", "visionos": "visionOS"}
wanted, kind = platforms[sys.argv[1]], sys.argv[2].lower()
matches = []
for line in sys.stdin:
    match = re.search(r"platform:([^,]+),.*?id: ([^,}]+)", line)
    if match and match.group(1) == wanted:
        matches.append((line, match.group(2).strip()))
for line, identifier in matches:
    if not kind or kind in line.lower():
        print(f"platform={wanted},id={identifier}")
        break
' "$PLATFORM" "$DEVICE_KIND")"
  if [[ -z "$DESTINATION" ]]; then
    DESTINATION="$(printf '%s\n' "$DESTINATIONS" | python3 -c '
import re, sys
platforms = {"ios": "iOS", "tvos": "tvOS", "visionos": "visionOS"}
wanted, kind = platforms[sys.argv[1]] + " Simulator", sys.argv[2].lower()
matches = []
for line in sys.stdin:
    match = re.search(r"platform:([^,]+),.*?id: ([^,}]+)", line)
    if match and match.group(1) == wanted:
        matches.append((line, match.group(2).strip()))
for line, identifier in matches:
    if not kind or kind in line.lower():
        print(f"platform={wanted},id={identifier}")
        break
' "$PLATFORM" "$DEVICE_KIND")"
  fi
fi

if [[ -z "$DESTINATION" ]]; then
  echo "No hay un dispositivo emparejado ni un simulador disponible. Compilaré para destino genérico y abriré Device Hub."
  DESTINATION="generic/platform=$XCODE_PLATFORM"
  open_device_hub
fi

echo "Destino: $DESTINATION"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" -configuration Debug build

[[ "$ACTION" == run ]] || exit 0
APP="$DERIVED_DATA/Build/Products/Debug/thisjellyfix.app"
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
  xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID"
else
  echo "Compilación lista. Selecciona un dispositivo en Device Hub para instalar y ejecutar la app."
fi
