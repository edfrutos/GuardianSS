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
        let result1 = ScanResult(
            archivo: "/path/to/file.txt",
            alertas: [Alerta(tipo: "Token", detalle: nil, linea: nil, muestra: nil)],
            movido_a: nil,
            copiado: nil
        )

        let result2 = ScanResult(
            archivo: "/path/to/file.txt",
            alertas: [Alerta(tipo: "Password", detalle: "Diff detail", linea: 5, muestra: "pass")],
            movido_a: "/quarantine/file.txt",
            copiado: true
        )

        XCTAssertEqual(result1, result2, "ScanResults con el mismo archivo deben ser iguales")

        var hasher1 = Hasher()
        var hasher2 = Hasher()
        result1.hash(into: &hasher1)
        result2.hash(into: &hasher2)

        XCTAssertEqual(hasher1.finalize(), hasher2.finalize(), "ScanResults iguales deben tener el mismo hash")
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
}
