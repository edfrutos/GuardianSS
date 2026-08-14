# Publicar una release — GuardianSS

Guía operativa para cortar y publicar una nueva versión. Complementa la sección
"Actualizaciones y releases" de `README.md` (qué hace la app) con el paso a
paso de lo que tiene que ejecutar quien publica.

## Requisitos

- **macOS con Xcode** (el script usa `xcodebuild`, `hdiutil` y `xcrun`, todos
  exclusivos de macOS — no funciona desde Linux ni desde un sandbox sin GUI
  de macOS).
- **Cuenta de Apple Developer Program de pago** (necesaria para firma
  Developer ID y notarización; con Apple ID gratuito Gatekeeper siempre
  avisará al descargar la app, ver *Troubleshooting* más abajo).
- **Certificado "Developer ID Application"** para el team (`V29BTBRY6G`)
  instalado en el keychain de acceso a inicio de sesión. Si nunca lo has
  generado: en Xcode, *Product → Archive* sobre el esquema `GuardianSS`, y
  luego *Distribute App → Developer ID* una vez desde la GUI — Xcode crea el
  certificado automáticamente si hace falta. También se puede generar manual
  desde *Xcode → Settings → Accounts → (tu cuenta) → Manage Certificates → +
  → Developer ID Application*.
- **Credenciales de notarización guardadas una vez** en el keychain:
  ```bash
  xcrun notarytool store-credentials "GuardianSS-notary" \
    --apple-id "tu-apple-id@ejemplo.com" \
    --team-id V29BTBRY6G \
    --password "contraseña-específica-de-app"
  ```
  La contraseña específica de app se genera en
  [appleid.apple.com](https://appleid.apple.com) → *Seguridad* →
  *Contraseñas específicas de app* (no es tu contraseña normal de Apple ID).
  El nombre `"GuardianSS-notary"` debe coincidir con `NOTARY_PROFILE` en
  `scripts/release.sh`. Solo hace falta hacerlo una vez por Mac.
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

1. Lee `MARKETING_VERSION` y `DEVELOPMENT_TEAM` con `xcodebuild
   -showBuildSettings`.
2. Comprueba que el tag `vX.Y` no exista ya y que no haya cambios sin
   commitear (aborta si alguna de las dos falla).
3. `xcodebuild archive` en `Release`, con `derivedDataPath` aislado en un
   directorio temporal (`mktemp -d`).
4. `xcodebuild -exportArchive` con `method: developer-id`, re-firmando el
   `.app` con el certificado Developer ID del team.
5. Notariza el `.app` con `xcrun notarytool submit --wait` (perfil de
   keychain `GuardianSS-notary`) y grapa el ticket con `xcrun stapler
   staple` — esto es lo que hace que Gatekeeper deje de avisar al abrirla en
   cualquier Mac, incluso sin conexión.
6. Empaqueta un DMG con `hdiutil` (la app ya notarizada + symlink a
   `/Applications`), y grapa también el ticket al propio DMG.
7. Crea el tag anotado `vX.Y` y lo empuja (`git push origin vX.Y`).
8. Publica la GitHub Release con `gh release create`, adjuntando el DMG.
9. Borra el DMG temporal local tras publicarlo — el artefacto queda en la
   release de GitHub, no versionado en el repo (`.gitignore` excluye
   `*.dmg`).

## Troubleshooting

**"Apple no ha podido verificar que GuardianSS.app no contenga software
malicioso..."** al abrir una release descargada: la app se firmó con
certificado *Apple Development* (el de depuración local) en vez de
*Developer ID*, y/o no se notarizó. Esto pasaba con releases publicadas antes
de que `scripts/release.sh` incorporara los pasos de firma Developer ID +
notarización (ver más arriba) — relanza la release siguiendo esta guía y el
aviso desaparece. Si no tienes cuenta de pago de Apple Developer Program, no
hay forma de evitar el aviso; quien instale la app tendrá que saltárselo con
clic derecho → *Abrir* (o `xattr -cr /Applications/GuardianSS.app` en
Terminal).

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
