import XCTest
@testable import GuardianSS

final class GuardianSSTests: XCTestCase {

    func testScanResultDecoding() throws {
        let jsonString = """
        [
            {
                "archivo": "/path/to/secret.txt",
                "alertas": [
                    {
                        "tipo": "API Key",
                        "detalle": "Encontrado potencial secreto",
                        "linea": 12,
                        "muestra": "api_key = \\"12345\\""
                    }
                ],
                "movido_a": "/quarantine/secret.txt"
            }
        ]
        """

        let data = try XCTUnwrap(jsonString.data(using: .utf8))
        let decoded = try JSONDecoder().decode([ScanResult].self, from: data)

        XCTAssertEqual(decoded.count, 1)

        let result = try XCTUnwrap(decoded.first)
        XCTAssertEqual(result.archivo, "/path/to/secret.txt")
        XCTAssertEqual(result.movido_a, "/quarantine/secret.txt")
        XCTAssertEqual(result.alertas.count, 1)

        let alert = try XCTUnwrap(result.alertas.first)
        XCTAssertEqual(alert.tipo, "API Key")
        XCTAssertEqual(alert.linea, 12)
        XCTAssertEqual(alert.muestra, "api_key = \"12345\"")
    }

    func testScanResultEqualityAndHashing() {
        // Misma ruta, mismo contenido -> iguales (Identifiable.id ya cubre la
        // identidad por ruta; == debe reflejar el contenido completo para que
        // SwiftUI detecte cambios de estado, ej. al pasar de "comprometido" a
        // "aislado", y refresque la fila correspondiente en el sidebar).
        let alerta = Alerta(tipo: "Token", detalle: nil, linea: nil, muestra: nil)
        let result1 = ScanResult(archivo: "/path/to/file.txt", alertas: [alerta], movido_a: nil, copiado: nil)
        let result1Copy = ScanResult(archivo: "/path/to/file.txt", alertas: [alerta], movido_a: nil, copiado: nil)

        XCTAssertEqual(result1, result1Copy, "ScanResults con el mismo contenido deben ser iguales")

        var hasher1 = Hasher()
        var hasher1Copy = Hasher()
        result1.hash(into: &hasher1)
        result1Copy.hash(into: &hasher1Copy)
        XCTAssertEqual(hasher1.finalize(), hasher1Copy.finalize(), "ScanResults iguales deben tener el mismo hash")

        // Misma ruta, pero ya aislado -> deben ser DISTINTOS pese a compartir
        // id, o el sidebar no se refresca tras poner un archivo en cuarentena.
        let quarantined = ScanResult(archivo: "/path/to/file.txt", alertas: [alerta], movido_a: "/quarantine/file.txt", copiado: true)
        XCTAssertNotEqual(result1, quarantined, "El estado de cuarentena debe afectar a la igualdad, no solo la ruta")
        XCTAssertEqual(result1.id, quarantined.id, "El id (Identifiable) sigue siendo la ruta, pese a diferir en contenido")
    }

    func testFileMetadataDecoding() throws {
        let jsonString = """
        {
            "timestamp": "2026-08-01T20:00:00Z",
            "original_path": "/path/to/secret.txt",
            "reasons": [
                {
                    "tipo": "Private Key",
                    "detalle": "RSA Private Key detected",
                    "linea": 1,
                    "muestra": "-----BEGIN RSA PRIVATE KEY-----"
                }
            ]
        }
        """

        let data = try XCTUnwrap(jsonString.data(using: .utf8))
        let metadata = try JSONDecoder().decode(FileMetadata.self, from: data)

        XCTAssertEqual(metadata.timestamp, "2026-08-01T20:00:00Z")
        XCTAssertEqual(metadata.original_path, "/path/to/secret.txt")
        XCTAssertEqual(metadata.reasons.count, 1)
        XCTAssertEqual(metadata.reasons.first?.tipo, "Private Key")
    }

    @MainActor
    func testScannerManagerInitialState() {
        let manager = ScannerManager()

        XCTAssertTrue(manager.results.isEmpty, "Se esperan resultados vacíos al inicio")
        XCTAssertFalse(manager.isScanning, "isScanning debe ser false al inicio")
        XCTAssertFalse(manager.quarantineActive, "quarantineActive debe ser false al inicio")
    }

    func testUpdateCheckerVersionComparison() {
        XCTAssertTrue(UpdateChecker.isVersion("1.1", newerThan: "1.0"))
        XCTAssertTrue(UpdateChecker.isVersion("2.0", newerThan: "1.9"))
        XCTAssertTrue(UpdateChecker.isVersion("1.0.1", newerThan: "1.0"))
        XCTAssertFalse(UpdateChecker.isVersion("1.0", newerThan: "1.0"))
        XCTAssertFalse(UpdateChecker.isVersion("1.0", newerThan: "1.1"))
        XCTAssertFalse(UpdateChecker.isVersion("0.9", newerThan: "1.0"))
    }

    // MARK: - quarantineArgs()

    @MainActor
    func testQuarantineArgsDefaultsToMove() {
        let manager = ScannerManager()
        XCTAssertEqual(manager.quarantineArgs(), ["--move"])
    }

    @MainActor
    func testQuarantineArgsCopyMode() {
        let manager = ScannerManager()
        manager.copyInsteadOfMove = true
        XCTAssertEqual(manager.quarantineArgs(), ["--copy"])
    }

    @MainActor
    func testQuarantineArgsWithCustomDirectory() {
        let manager = ScannerManager()
        manager.customQuarantineDir = "/Users/test/MiCuarentena"
        XCTAssertEqual(manager.quarantineArgs(), ["--move", "--move-to", "/Users/test/MiCuarentena"])
    }

    @MainActor
    func testQuarantineArgsCopyModeWithCustomDirectory() {
        let manager = ScannerManager()
        manager.copyInsteadOfMove = true
        manager.customQuarantineDir = "/Users/test/MiCuarentena"
        XCTAssertEqual(manager.quarantineArgs(), ["--copy", "--move-to", "/Users/test/MiCuarentena"])
    }

    @MainActor
    func testQuarantineArgsIgnoresEmptyCustomDirectory() {
        // Una cadena vacía (ej. tras limpiar el selector de carpeta) no debe generar "--move-to ''".
        let manager = ScannerManager()
        manager.customQuarantineDir = ""
        XCTAssertEqual(manager.quarantineArgs(), ["--move"])
    }

    // MARK: - extractJSONPayload(from:)

    func testExtractJSONPayloadStripsLogLines() {
        let raw = """
        [*] Escaneando carpeta...
        [*] 3 archivos revisados
        [{"archivo": "/a.txt", "alertas": [], "movido_a": null, "copiado": null}]
        """
        let payload = ScannerManager.extractJSONPayload(from: raw)
        XCTAssertEqual(payload, #"[{"archivo": "/a.txt", "alertas": [], "movido_a": null, "copiado": null}]"#)
    }

    func testExtractJSONPayloadWithoutLogLinesIsUnchanged() {
        let raw = #"[{"archivo": "/a.txt", "alertas": [], "movido_a": null, "copiado": null}]"#
        XCTAssertEqual(ScannerManager.extractJSONPayload(from: raw), raw)
    }

    func testExtractJSONPayloadEmptyOutputIsEmpty() {
        XCTAssertEqual(ScannerManager.extractJSONPayload(from: ""), "")
        XCTAssertEqual(ScannerManager.extractJSONPayload(from: "[*] Solo logs, sin JSON"), "")
    }
}
