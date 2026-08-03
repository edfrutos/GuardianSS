#!/bin/bash
# Empaqueta GuardianSS en un DMG, crea el tag git y publica un GitHub Release.
#
# Uso: scripts/release.sh [notas de la release]
# La versión se lee de MARKETING_VERSION en el proyecto Xcode (Info > General > Version).
#
# Requiere: xcodebuild, hdiutil (macOS), gh CLI autenticado con acceso al repo.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

PROJECT="GuardianSS.xcodeproj"
SCHEME="GuardianSS"
APP_NAME="GuardianSS"
GH_REPO="edfrutos/GuardianSS"

VERSION=$(xcodebuild -project "$PROJECT" -showBuildSettings -scheme "$SCHEME" -configuration Release 2>/dev/null \
  | awk -F'= ' '/MARKETING_VERSION/{print $2; exit}')

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

echo "==> Compilando en Release..."
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CONFIGURATION_BUILD_DIR="$BUILD_DIR/Build"

APP_PATH="$BUILD_DIR/Build/${APP_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
  echo "No se encontró ${APP_PATH} tras el build." >&2
  exit 1
fi

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
