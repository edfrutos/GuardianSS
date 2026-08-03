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
| `GuardianSSTests/GuardianSSTests.swift` | Tests XCTest de los modelos (`ScanResult`, `Alerta`, `FileMetadata`) y del estado inicial de `ScannerManager`. |

El escaneo corre en background (`DispatchQueue.global`) leyendo el pipe del subproceso para evitar bloqueos por buffer lleno.

## Compilar y ejecutar

1. Abrir `GuardianSS.xcodeproj` en Xcode.
2. En *Signing & Capabilities*, comprobar el **App Sandbox**: debe permitir *User Selected File (Read/Write)* o estar desactivado, ya que la app necesita ejecutar un proceso externo (`Process`) y leer/escribir en carpetas elegidas por el usuario.
3. Run (⌘R). Pulsar "Escanear Carpeta" para elegir un directorio.
4. Activar "Poner en cuarentena al escanear" para que el escaneo también aísle los archivos detectados.
   - Por defecto **mueve** el archivo (`scan_sensitive.py --move`). Con "Copiar en vez de mover" activo, en cambio **copia** el archivo a cuarentena y el original permanece en su sitio (`--copy`).
   - El directorio raíz de cuarentena es por defecto `quarantine/` junto al script (con una subcarpeta por fecha dentro); se puede elegir otro con el selector de carpeta bajo los interruptores (`--move-to <ruta>`).

## Tests

Target XCTest `GuardianSSTests` (bundle de unit tests, dependiente del target `GuardianSS`). Ejecutar con ⌘U desde Xcode o `xcodebuild test -project GuardianSS.xcodeproj -scheme GuardianSS -destination 'platform=macOS'`. Cubre la decodificación de los modelos de datos y el estado inicial de `ScannerManager`; no cubre el lanzamiento del subproceso ni la UI.

## Notas de seguridad

- No hay credenciales ni secretos reales en el código fuente; las cadenas que mencionan "api_key"/"secret" en `ContentView.swift` y `GuardianSSTests.swift` son texto de interfaz o datos de prueba ficticios.
- `project.pbxproj` contiene el `DEVELOPMENT_TEAM` (Apple Team ID) del firmante. No es una credencial explotable, pero si el repositorio se publica en abierto queda vinculado a la cuenta de desarrollador.
- La ruta del script Python tiene un valor por defecto fijo, ahora sobreescribible con `GUARDIANSS_SCAN_SCRIPT` (ver *Requisitos*).
