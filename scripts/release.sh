#!/bin/bash
# Firma con Developer ID, notariza, empaqueta GuardianSS en un DMG, crea el
# tag git y publica un GitHub Release.
#
# Uso: scripts/release.sh [notas de la release]
# La versión se lee de MARKETING_VERSION en el proyecto Xcode (Info > General > Version).
#
# Requiere:
#   - xcodebuild, hdiutil, xcrun (macOS).
#   - Certificado "Developer ID Application" para DEVELOPMENT_TEAM instalado
#     en el keychain de acceso a inicio de sesión (Xcode lo genera la primera
#     vez que archivas y distribuyes como Developer ID desde la GUI, o desde
#     Xcode > Settings > Accounts > Manage Certificates).
#   - Credenciales de notarización guardadas una vez en el keychain:
#       xcrun notarytool store-credentials "$NOTARY_PROFILE" \
#         --apple-id "<tu-apple-id>" --team-id "<TEAM_ID>" \
#         --password "<contraseña específica de app>"
#     Ver RELEASING.md para el detalle.
#   - gh CLI autenticado con acceso al repo.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

PROJECT="GuardianSS.xcodeproj"
SCHEME="GuardianSS"
APP_NAME="GuardianSS"
GH_REPO="edfrutos/GuardianSS"
NOTARY_PROFILE="GuardianSS-notary"

VERSION=$(xcodebuild -project "$PROJECT" -showBuildSettings -scheme "$SCHEME" -configuration Release 2>/dev/null \
  | awk -F'= ' '/MARKETING_VERSION/{print $2; exit}')
DEVELOPMENT_TEAM=$(xcodebuild -project "$PROJECT" -showBuildSettings -scheme "$SCHEME" -configuration Release 2>/dev/null \
  | awk -F'= ' '/ DEVELOPMENT_TEAM/{print $2; exit}')

if [ -z "$VERSION" ]; then
  echo "No se pudo leer MARKETING_VERSION del proyecto." >&2
  exit 1
fi

TAG="v${VERSION}"
NOTES="${1:-Release ${TAG}}"

echo "==> Versión: ${VERSION} (tag ${TAG})"

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "El tag ${TAG} ya existe. Sube MARKETING_VERSION antes de lanzar otra release." >&2
  exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "Hay cambios sin commitear. Commitea o descarta antes de lanzar una release." >&2
  exit 1
fi

BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

echo "==> Archivando en Release..."
ARCHIVE_PATH="$BUILD_DIR/${APP_NAME}.xcarchive"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$BUILD_DIR/DerivedData"

echo "==> Exportando firmado con Developer ID..."
EXPORT_OPTIONS="$BUILD_DIR/exportOptions.plist"
cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>teamID</key>
	<string>${DEVELOPMENT_TEAM}</string>
	<key>signingStyle</key>
	<string>automatic</string>
</dict>
</plist>
PLIST

EXPORT_DIR="$BUILD_DIR/Export"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

APP_PATH="$EXPORT_DIR/${APP_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
  echo "No se encontró ${APP_PATH} tras la exportación." >&2
  exit 1
fi

echo "==> Notarizando (esto puede tardar varios minutos)..."
NOTARY_ZIP="$BUILD_DIR/${APP_NAME}-notarize.zip"
ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP"
xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Grapando el ticket de notarización a la app..."
xcrun stapler staple "$APP_PATH"

echo "==> Creando DMG..."
DMG_STAGING="$BUILD_DIR/dmg"
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

DMG_PATH="$BUILD_DIR/${APP_NAME}-${VERSION}.dmg"
hdiutil create -volname "${APP_NAME} ${VERSION}" \
  -srcfolder "$DMG_STAGING" \
  -ov -format UDZO \
  "$DMG_PATH" >/dev/null

echo "==> Grapando el ticket de notarización al DMG..."
xcrun stapler staple "$DMG_PATH"

FINAL_DMG="$REPO_DIR/${APP_NAME}-${VERSION}.dmg"
cp "$DMG_PATH" "$FINAL_DMG"
echo "==> DMG listo: ${FINAL_DMG}"

echo "==> Creando tag ${TAG}..."
git tag -a "$TAG" -m "$NOTES"
git push origin "$TAG"

echo "==> Publicando GitHub Release..."
gh release create "$TAG" "$FINAL_DMG" \
  --repo "$GH_REPO" \
  --title "${APP_NAME} ${VERSION}" \
  --notes "$NOTES"

rm -f "$FINAL_DMG"
echo "==> Release ${TAG} publicada en https://github.com/${GH_REPO}/releases/tag/${TAG}"
