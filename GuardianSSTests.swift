import Foundation
import Combine

// --- Light-weight Test Harness ---
func runTest(name: String, testBlock: () throws -> Void) {
    print("⏳ Running \(name)...", terminator: "")
    fflush(stdout)
    do {
        try testBlock()
        print("\r✅ \(name) PASSED")
    } catch {
        print("\r❌ \(name) FAILED: \(error)")
        exit(1)
    }
}

// --- Test Implementation ---

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
    
    guard let data = jsonString.data(using: .utf8) else {
        throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert string to data"])
    }
    
    let decoded = try JSONDecoder().decode([ScanResult].self, from: data)
    
    if decoded.count != 1 {
        throw NSError(domain: "TestError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected 1 result, got \(decoded.count)"])
    }
    
    let result = decoded[0]
    if result.archivo != "/path/to/secret.txt" {
        throw NSError(domain: "TestError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Incorrect archivo: \(result.archivo)"])
    }
    if result.movido_a != "/quarantine/secret.txt" {
        throw NSError(domain: "TestError", code: 4, userInfo: [NSLocalizedDescriptionKey: "Incorrect movido_a: \(String(describing: result.movido_a))"])
    }
    if result.alertas.count != 1 {
        throw NSError(domain: "TestError", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected 1 alert, got \(result.alertas.count)"])
    }
    
    let alert = result.alertas[0]
    if alert.tipo != "API Key" {
        throw NSError(domain: "TestError", code: 6, userInfo: [NSLocalizedDescriptionKey: "Incorrect alert type: \(alert.tipo)"])
    }
    if alert.linea != 12 {
        throw NSError(domain: "TestError", code: 7, userInfo: [NSLocalizedDescriptionKey: "Incorrect line number: \(String(describing: alert.linea))"])
    }
    if alert.muestra != "api_key = \"12345\"" {
        throw NSError(domain: "TestError", code: 8, userInfo: [NSLocalizedDescriptionKey: "Incorrect sample: \(String(describing: alert.muestra))"])
    }
}

func testScanResultEqualityAndHashing() throws {
    let result1 = ScanResult(
        archivo: "/path/to/file.txt",
        alertas: [Alerta(tipo: "Token", detalle: nil, linea: nil, muestra: nil)],
        movido_a: nil
    )
    
    let result2 = ScanResult(
        archivo: "/path/to/file.txt",
        alertas: [Alerta(tipo: "Password", detalle: "Diff detail", linea: 5, muestra: "pass")],
        movido_a: "/quarantine/file.txt"
    )
    
    if result1 != result2 {
        throw NSError(domain: "TestError", code: 9, userInfo: [NSLocalizedDescriptionKey: "ScanResults with same archivo must be equal"])
    }
    
    var hasher1 = Hasher()
    var hasher2 = Hasher()
    result1.hash(into: &hasher1)
    result2.hash(into: &hasher2)
    
    if hasher1.finalize() != hasher2.finalize() {
        throw NSError(domain: "TestError", code: 10, userInfo: [NSLocalizedDescriptionKey: "Equal ScanResults must have matching hashes"])
    }
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
    
    guard let data = jsonString.data(using: .utf8) else {
        throw NSError(domain: "TestError", code: 11, userInfo: [NSLocalizedDescriptionKey: "Failed to convert string to data"])
    }
    
    let metadata = try JSONDecoder().decode(FileMetadata.self, from: data)
    
    if metadata.timestamp != "2026-08-01T20:00:00Z" {
        throw NSError(domain: "TestError", code: 12, userInfo: [NSLocalizedDescriptionKey: "Incorrect timestamp: \(metadata.timestamp)"])
    }
    if metadata.original_path != "/path/to/secret.txt" {
        throw NSError(domain: "TestError", code: 13, userInfo: [NSLocalizedDescriptionKey: "Incorrect original_path: \(metadata.original_path)"])
    }
    if metadata.reasons.count != 1 {
        throw NSError(domain: "TestError", code: 14, userInfo: [NSLocalizedDescriptionKey: "Expected 1 reason, got \(metadata.reasons.count)"])
    }
    
    let reason = metadata.reasons[0]
    if reason.tipo != "Private Key" {
        throw NSError(domain: "TestError", code: 15, userInfo: [NSLocalizedDescriptionKey: "Incorrect reason type: \(reason.tipo)"])
    }
}

func testScannerManagerInitialState() throws {
    let manager = ScannerManager()
    
    if !manager.results.isEmpty {
        throw NSError(domain: "TestError", code: 16, userInfo: [NSLocalizedDescriptionKey: "Expected empty results initially"])
    }
    if manager.isScanning {
        throw NSError(domain: "TestError", code: 17, userInfo: [NSLocalizedDescriptionKey: "Expected isScanning to be false initially"])
    }
    if manager.quarantineActive {
        throw NSError(domain: "TestError", code: 18, userInfo: [NSLocalizedDescriptionKey: "Expected quarantineActive to be false initially"])
    }
}

// --- Main Entry Point ---
@main
struct TestRunner {
    static func main() {
        print("\n🚀 Starting GuardianSS Automated Test Suite 🚀")
        print("==============================================")
        
        runTest(name: "testScanResultDecoding", testBlock: testScanResultDecoding)
        runTest(name: "testScanResultEqualityAndHashing", testBlock: testScanResultEqualityAndHashing)
        runTest(name: "testFileMetadataDecoding", testBlock: testFileMetadataDecoding)
        runTest(name: "testScannerManagerInitialState", testBlock: testScannerManagerInitialState)
        
        print("==============================================")
        print("🎉 ALL TESTS PASSED SUCCESSFULLY! 🎉\n")
    }
}
