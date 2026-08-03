# Estado de desarrollo — GuardianSS

Notas de la revisión del repo `macos-app/GuardianSS`, a fecha 2026-08-02. Complementa a `README.md` (arquitectura y uso) con el diagnóstico de dónde está el proyecto y qué falta.

## Qué es

GuardianSS es la interfaz nativa macOS (SwiftUI) del proyecto Guardian Secret Scanner. No contiene lógica de detección propia: delega el escaneo real en el script Python `scan_sensitive.py` (fuera de este repo, en `secret-scanner-tool/`), lo lanza como subproceso y pinta sus resultados JSON.

## Funcionalidad en desarrollo

- Selección de carpeta vía `NSOpenPanel` y lanzamiento de escaneo (`ScannerManager.runScan`).
- Listado de archivos con alertas, detalle por archivo (tipo de alerta, línea, fragmento detectado) y vista de selección múltiple.
- Cuarentena: individual (`quarantineFile`) y por lote (`quarantineFiles` / `quarantineFileSync`), con lectura de metadatos de traslado (`.metadata.json`) para mostrar fecha y ruta original. Modo copia (conserva el original) o mover (lo elimina), y directorio raíz de cuarentena configurable (por defecto `quarantine/` junto al script, con subcarpeta por fecha).
- Hardened Runtime activado vía entitlements; App Sandbox desactivado a nivel de proyecto (`ENABLE_APP_SANDBOX = NO`), necesario porque la app lanza procesos externos y accede a rutas arbitrarias elegidas por el usuario.

## Lo que se lleva hecho (esta sesión)

1. **Sincronización del repo**: se ordenó un working tree con archivos duplicados y a medio-stage; se limpiaron dos copias obsoletas de `ScannerLogic.swift`, se creó `.gitignore` (excluye `.gemini/`, `GEMINI.md`, el binario `GuardianSSTests` y `.DS_Store`) y se hizo el primer commit real de la lógica de escaneo, entitlements endurecidos y tests.
2. **Revisión de datos sensibles**: sin credenciales ni secretos reales en el código. Hallazgos de bajo riesgo documentados (ruta hardcodeada del script, Apple Team ID en `project.pbxproj`).
3. **README.md**: creado desde cero para este subproyecto (no existía); cubre arquitectura, requisitos, build/run y notas de seguridad.
4. **Refactor de robustez**: la ruta al script Python y la búsqueda del ejecutable `python3` estaban duplicadas idénticas en 4 sitios (`runScan`, `quarantineFile`, `quarantineFiles`→`quarantineFileSync`). Se centralizaron en `ScannerManager.scriptPath` (con override por `GUARDIANSS_SCAN_SCRIPT`) y `resolvePythonExecutable()`. Ahora, si el script no existe en la ruta resuelta, se muestra un error explícito en vez de fallar en silencio o lanzar un proceso condenado a fallar. Verificado con `xcodebuild build` → `BUILD SUCCEEDED`.
5. **Migración de tests a XCTest real**: se sustituyó el arnés casero (`@main struct TestRunner`) por un target `GuardianSSTests` de verdad (`com.apple.product-type.bundle.unit-test`), añadido al `.pbxproj` con la gem `xcodeproj` y registrado en el scheme compartido. Los 4 tests se movieron a `GuardianSSTests/GuardianSSTests.swift` con `XCTAssert*`. Hubo que igualar `ARCHS = arm64e` en el nuevo target (la app compila en `arm64e` por el hardened runtime; el target de test por defecto se creaba en `arm64`, y un `.xctest` no puede cargarse por `dlopen` en un host de arquitectura distinta). Verificado con `xcodebuild test` → **TEST SUCCEEDED**, 4/4 pasan.
6. **Copiar en vez de mover**: nueva funcionalidad completa, motor + app.
   - `scan_sensitive.py` (fuera de este repo, en `secret-scanner-tool/`): `move_file` renombrado a `quarantine_file`, ahora acepta `mode` ('move'/'copy'/None) en vez de un booleano. CLI: `--move` y `--copy` son mutuamente excluyentes (`argparse.add_mutually_exclusive_group`); `--move-to <ruta>` (ya existía) define el directorio raíz, con subcarpeta por fecha dentro — ese ya era el comportamiento "por defecto `quarantine/` salvo que se elija otro" que pediste. El JSON de resultados gana el campo `copiado: bool`, y `.metadata.json` gana `modo`. Probado manualmente: copia dentro de directorio custom con original intacto, y modo mover sigue igual que antes (regresión).
   - `ScannerLogic.swift`: `ScanResult` gana `copiado: Bool?`, `FileMetadata` gana `modo: String?`. `ScannerManager` gana `@Published var copyInsteadOfMove` y `@Published var customQuarantineDir: String?`, más un helper `quarantineArgs()` que construye `--copy`/`--move` (+ `--move-to` si hay dir custom) — usado en los 3 puntos que antes tenían `--move` hardcodeado (`runScan`, `quarantineFile`, `quarantineFileSync`).
   - `ContentView.swift`: toggle "Copiar en vez de mover" (solo visible si la cuarentena al escanear está activa), componente nuevo `QuarantineDirectoryPicker` (selector de carpeta + botón para volver al valor por defecto), y las etiquetas/botones ("Aislado" → "Copiado", "Aislar archivo" → "Copiar a cuarentena", aviso de que el original permanece) se adaptan al modo activo.
   - `GuardianSSTests.swift`: actualizado para el nuevo parámetro `copiado` en el init memberwise de `ScanResult`. Verificado con `xcodebuild test` → 4/4 pasan.

## Errores / problemas detectados

| Severidad | Problema | Detalle |
|---|---|---|
| Baja | Estado de usuario versionado | `GuardianSS.xcodeproj/xcuserdata/edefrutos.xcuserdatad/xcschemes/xcschememanagement.plist` está trackeado en git. Es configuración local de Xcode (qué esquemas se autocrean/muestran), específica de tu usuario/máquina; normalmente se ignora. |
| Baja | Icono inconsistente | `Assets.xcassets/AppIcon.appiconset` declara 10 slots de tamaño (16..512, @1x/@2x) pero **no contiene ninguna imagen** — catálogo vacío. El icono real se sirve por el mecanismo legacy `INFOPLIST_KEY_CFBundleIconFile = "icon"` + `GuardianSS/icon.icns`. Funciona, pero Xcode marcará advertencias de icono faltante y hay dos mecanismos conviviendo sin necesidad. |
| Baja | Cuarentena por lote sin feedback de error | `quarantineFileSync` (usada por `quarantineFiles` para selección múltiple) solo hace `print` si falla un archivo concreto; el usuario no se entera de qué archivo no se pudo aislar, solo ve que `isScanning` vuelve a `false`. |
| Baja | Duplicación menor | En `ContentView.swift` (`MultiDetailView`), el filtro que calcula archivos no aislados (`unisolatedCount` / `unisolatedPaths`) se recalcula dos veces con el mismo predicado. |

No se han encontrado bugs de severidad alta ni problemas de seguridad explotables (credenciales, inyección de comandos — `Process.arguments` se usa como array, no hay shell interpolation).

## Pendiente (propuesta, a validar contigo)

- Decidir icono: completar `AppIcon.appiconset` con imágenes reales o eliminarlo y documentar que el icono vive solo en `icon.icns`.
- Sacar `xcuserdata/` del control de versiones (`git rm --cached` + añadir a `.gitignore`).
- Ampliar cobertura de tests: hoy solo cubren modelos y estado inicial; falta el parseo de la salida real del subproceso, el manejo de errores y la cuarentena.
- Propagar errores por-archivo en cuarentena múltiple a la UI en vez de solo consola.
- Repo aún sin remoto (decisión previa: solo local). Cuando quieras subirlo, aviso para crear/enlazar GitHub.
- El README de la carpeta padre (`secret-scanner-tool/README.md`, fuera de este repo) sigue describiendo un flujo de instalación desactualizado ("crea un proyecto Xcode nuevo y arrastra archivos"); no lo he tocado por estar fuera del repo gestionado, pero conviene actualizarlo si te interesa mantener esa doc coherente.
