# GuardianSS

Aplicación nativa de macOS (SwiftUI) para auditar carpetas en busca de secretos expuestos (claves de API, contraseñas, claves privadas, tokens) y ponerlos en cuarentena con trazabilidad (moviendo o copiando el archivo, a elección). Es la interfaz gráfica del motor Python [`scan_sensitive.py`](../../scan_sensitive.py) del proyecto [Guardian Secret Scanner](../../README.md).

## Requisitos

- macOS con Xcode (proyecto `GuardianSS.xcodeproj`).
- Python 3 instalado (Homebrew en `/opt/homebrew/bin/python3` o `/usr/local/bin/python3`, o el `/usr/bin/python3` del sistema como último recurso).
- El motor `scan_sensitive.py` del repositorio padre. Por defecto se busca en `/Volumes/BACKUPS_PROYECTOS/secret-scanner-tool/scan_sensitive.py`; para usar otra ruta, define la variable de entorno `GUARDIANSS_SCAN_SCRIPT` (por ejemplo, en el *scheme* de Xcode, pestaña *Arguments* → *Environment Variables*). Si el script no aparece en la ruta resuelta, la app muestra un error en vez de fallar en silencio.

## Arquitectura

| Archivo | Responsabilidad |
|---|---|
| `GuardianSSApp.swift` | Punto de entrada `App`, define la ventana principal. |
| `ContentView.swift` | Toda la interfaz: lista de resultados, detalle de alertas, vistas de bienvenida/limpio/amenazas, selección múltiple y cuarentena. |
| `ScannerLogic.swift` | `ScannerManager` (`ObservableObject`): lanza `scan_sensitive.py` como subproceso, parsea el JSON de resultados y expone el estado (`isScanning`, `results`, `errorMessage`, etc.) a la UI. |
| `GuardianSS.entitlements` | Hardened Runtime activado (`hardened-process`, `hardened-heap`, `dyld-ro`). |
| `GuardianTheme.swift` | Lenguaje visual: paleta ámbar/azul (colores en `Assets.xcassets`), tarjetas de cristal (`guardianCard`), insignias con halo (`GlowBadge`), chips de severidad. |
| `UpdateChecker.swift` | Comprueba si hay una release más reciente en GitHub (API pública `GET /releases/latest`), la descarga, verifica su firma/notarización, y la instala tras confirmación del usuario. |
| `InstallLocation.swift` | `InstallLocation` (dónde debe vivir la app, persistido en `UserDefaults`), `RelaunchHelper` (sustituye el bundle en ejecución y relanza) y `InstallSetupManager` (pregunta el destino en el primer lanzamiento). Usado tanto por el flujo de primer lanzamiento como por `UpdateChecker`. |
| `GuardianSSTests/GuardianSSTests.swift` | Tests XCTest de los modelos (`ScanResult`, `Alerta`, `FileMetadata`), el estado inicial de `ScannerManager` y la comparación de versiones de `UpdateChecker`. |

El escaneo corre en background (`DispatchQueue.global`) leyendo el pipe del subproceso para evitar bloqueos por buffer lleno.

## Compilar y ejecutar

1. Abrir `GuardianSS.xcodeproj` en Xcode.
2. En *Signing & Capabilities*, comprobar el **App Sandbox**: debe permitir *User Selected File (Read/Write)* o estar desactivado, ya que la app necesita ejecutar un proceso externo (`Process`) y leer/escribir en carpetas elegidas por el usuario.
3. Run (⌘R). Pulsar "Escanear Carpeta" para elegir un directorio, o **arrastrar una carpeta desde Finder** a cualquier parte de la ventana (aparece un borde discontinuo ámbar mientras se arrastra encima). Ambos caminos llaman al mismo `ScannerManager.runScan`.
4. Activar "Poner en cuarentena al escanear" para que el escaneo también aísle los archivos detectados.
   - Por defecto **mueve** el archivo (`scan_sensitive.py --move`). Con "Copiar en vez de mover" activo, en cambio **copia** el archivo a cuarentena y el original permanece en su sitio (`--copy`).
   - El directorio raíz de cuarentena es por defecto `quarantine/` junto al script (con una subcarpeta por fecha dentro); se puede elegir otro con el selector de carpeta bajo los interruptores (`--move-to <ruta>`).

## Actualizaciones y releases

- La app comprueba automáticamente al abrir (silenciosa) si hay una release más nueva en `github.com/edfrutos/GuardianSS`, comparando `MARKETING_VERSION` contra el último tag. También se puede comprobar a mano desde el botón ↻ de la toolbar o el menú **GuardianSS → Buscar actualizaciones...**; a diferencia de la comprobación automática, la manual siempre muestra una alerta con el resultado (haya o no actualización, o si falla), para que no parezca que el botón "no hace nada".
- El repositorio es **público**, así que la comprobación consulta la API HTTP de GitHub directamente y de forma anónima (`GET https://api.github.com/repos/edfrutos/GuardianSS/releases/latest`), sin necesidad de token ni de tener `gh` CLI instalado en la máquina que ejecuta la app.
- **Descarga e instalación automáticas** (`UpdateChecker.swift`): en cuanto se detecta una versión más nueva, la app descarga sola el DMG adjunto a la release en segundo plano (banner con progreso en el sidebar), lo monta, y verifica que el `.app` de dentro esté correctamente firmado (`codesign --verify`), pase la comprobación de Gatekeeper (`spctl --assess`) y esté firmado por el team ID esperado (`V29BTBRY6G`) antes de darla por buena — si algo de eso falla, no se instala. Con la actualización ya verificada, el banner muestra **Reiniciar y actualizar**: al pulsarlo, la app lanza un script auxiliar que espera a que cierre, sustituye el bundle, y la relanza. No se instala nunca sin que el usuario pulse ese botón. Si la release no trae un DMG adjunto, cae de vuelta al comportamiento antiguo (enlace a la página de la release).
- **Ubicación de instalación** (`InstallLocation.swift`): en el primer lanzamiento de una build de Release, la app pregunta dónde debe vivir de forma estable (por defecto `/Applications`) — necesario porque, si se ejecuta directamente desde un DMG montado o desde Descargas, las actualizaciones automáticas no tendrían un destino fiable. Se puede elegir otra carpeta en ese momento, o cambiarla más tarde desde el ajuste "Ubicación de instalación" al pie del sidebar. `UpdateChecker` instala siempre en esa ubicación configurada, nunca en la ruta desde la que la instancia actual resulte estar corriendo. Este flujo está desactivado en builds de Debug (ejecutadas desde Xcode).
- Para publicar una release nueva: sube `MARKETING_VERSION` en Xcode (General → Version), commitea, y ejecuta `scripts/release.sh ["notas"]`. El script compila en Release, empaqueta un DMG, crea el tag `vX.Y` y publica la GitHub Release con el DMG adjunto. Se niega a correr si hay cambios sin commitear o si el tag ya existe. Ver [`RELEASING.md`](RELEASING.md) para el paso a paso detallado, incluidas las particularidades de publicar desde un sandbox de Claude Code.

## Tests

Target XCTest `GuardianSSTests` (bundle de unit tests, dependiente del target `GuardianSS`). Ejecutar con ⌘U desde Xcode o `xcodebuild test -project GuardianSS.xcodeproj -scheme GuardianSS -destination 'platform=macOS'`. Cubre la decodificación de los modelos de datos y el estado inicial de `ScannerManager`; no cubre el lanzamiento del subproceso ni la UI.

## Notas de seguridad

- No hay credenciales ni secretos reales en el código fuente; las cadenas que mencionan "api_key"/"secret" en `ContentView.swift` y `GuardianSSTests.swift` son texto de interfaz o datos de prueba ficticios.
- `project.pbxproj` contiene el `DEVELOPMENT_TEAM` (Apple Team ID) del firmante. No es una credencial explotable, pero si el repositorio se publica en abierto queda vinculado a la cuenta de desarrollador.
- La ruta del script Python tiene un valor por defecto fijo, ahora sobreescribible con `GUARDIANSS_SCAN_SCRIPT` (ver *Requisitos*).
