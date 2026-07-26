import Foundation
import Testing

/// Turns the AGENTS.md "never trigger Keychain prompts in tests" rule into a CI gate:
/// it asserts the rule still exists, and that no test file calls UI-prompting Keychain
/// APIs. The credential store uses file storage in DEBUG so tests never hit the Keychain;
/// this keeps that guarantee from silently regressing.
struct KeychainPromptSafetyAuditTests {
    @Test func `agents documents the keychain rule`() throws {
        let agents = try String(contentsOf: Self.packageRoot.appendingPathComponent("AGENTS.md"), encoding: .utf8)
        #expect(
            agents.localizedCaseInsensitiveContains("Keychain prompt"),
            "AGENTS.md must keep the 'never trigger Keychain prompts in tests' rule.")
    }

    @Test func `no test calls UI prompting keychain AP is`() throws {
        let testsDir = Self.packageRoot.appendingPathComponent("Tests")
        let risky = ["SecItemAdd", "SecItemCopyMatching", "SecItemUpdate", "SecItemDelete"]
        let thisFile = URL(fileURLWithPath: #filePath).lastPathComponent

        let enumerator = FileManager.default.enumerator(at: testsDir, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift", url.lastPathComponent != thisFile else { continue }
            let source = try String(contentsOf: url, encoding: .utf8)
            for symbol in risky where source.contains(symbol) {
                Issue.record("""
                \(url.lastPathComponent) calls \(symbol) — tests must not prompt the Keychain.
                Use a file-backed test store.
                """)
            }
        }
    }

    /// Walk up from this source file to the package root (the dir holding Package.swift).
    static let packageRoot: URL = {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
                return dir
            }
            dir.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }()
}
