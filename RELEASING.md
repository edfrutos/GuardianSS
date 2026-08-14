# Publicar una release — GuardianSS

Guía operativa para cortar y publicar una nueva versión. Complementa la sección
"Actualizaciones y releases" de `README.md` (qué hace la app) con el paso a
paso de lo que tiene que ejecutar quien publica.

## Requisitos

- **macOS con Xcode** (el script usa `xcodebuild` y `hdiutil`, ambos exclusivos
  de macOS — no funciona desde Linux ni desde un sandbox sin GUI de macOS).
- **`gh` CLI instalado y logueado** (`gh auth login`) con permiso de escritura
  sobre `edfrutos/GuardianSS`.
- Working tree limpio (`git status` sin cambios pendientes) — el script se
  niega a correr si hay algo sin commitear.

## Pasos

1. Sube `MARKETING_VERSION` en Xcode (target `GuardianSS` → *General* →
   *Version*), o edita directamente las dos apariciones de
   `MARKETING_VERSION` en `GuardianSS.xcodeproj/project.pbxproj` (una por
   configuración Debug/Release del target de la app).
2. Commitea el bump de versión (y cualquier otro cambio de la release).
3. `git push origin main` — para que el remoto no quede por detrás del tag
   que el script va a crear.
4. `scripts/release.sh ["notas de la release"]`

## Qué hace `scripts/release.sh`

1. Lee `MARKETING_VERSION` con `xcodebuild -showBuildSettings`.
2. Comprueba que el tag `vX.Y` no exista ya y que no haya cambios sin
   commitear (aborta si alguna de las dos falla).
3. Compila en `Release` con `derivedDataPath`/`CONFIGURATION_BUILD_DIR`
   aislados en un directorio temporal (`mktemp -d`).
4. Empaqueta un DMG con `hdiutil` (la app + symlink a `/Applications`).
5. Crea el tag anotado `vX.Y` y lo empuja (`git push origin vX.Y`).
6. Publica la GitHub Release con `gh release create`, adjuntando el DMG.
7. Borra el DMG temporal local tras publicarlo — el artefacto queda en la
   release de GitHub, no versionado en el repo (`.gitignore` excluye
   `*.dmg`).

## Trabajando desde un sandbox de Claude Code

Si preparas la release con la ayuda de un agente en un sandbox (como este
proyecto), ten en cuenta:

- **El sandbox de este proyecto corre en Linux**: no tiene `xcodebuild` ni
  `hdiutil`. `scripts/release.sh` **debe ejecutarse en el Mac**, nunca desde
  el sandbox — el agente puede preparar el bump de versión y el commit, pero
  el build/DMG/tag/publicación los tienes que correr tú.
- **Modo de workspace**: comprueba con
  `[ -d /run/sandbox/source ] && echo clone || echo direct`.
  - *Direct mode* (el habitual aquí): los commits que haga el agente en el
    sandbox aparecen de inmediato en tu working tree del Mac — no hace falta
    ningún `pull` para verlos localmente, pero sí siguen sin estar en
    `origin` hasta que alguien haga `git push`.
  - *Clone mode*: el sandbox trabaja sobre un clon aislado; para traer sus
    commits al Mac hace falta `git fetch sandbox-<nombre>` desde el host.
- **`git push` desde el sandbox** requiere credenciales de GitHub inyectadas
  por el proxy. Si falla con `could not read Username for
  'https://github.com'`, configúralas desde el host:
  ```bash
  sbx secret set github --sandbox <nombre-sandbox> -t "$(gh auth token)"
  ```
  El nombre del sandbox está disponible dentro de él como `$SANDBOX_VM_ID`.
  Alternativa más simple: haz tú el `git push origin main` desde tu propia
  Terminal en vez de configurar el secreto.
