import Foundation
import UIKit

private struct NativeEvent: Codable {
    let time: String
    let event: String
    let detail: String?
}

/// Native-only evidence. Never records URL query strings, chats, tokens, cookies, or prompts.
final class NativeDiagnostics {
    static let shared = NativeDiagnostics()
    private let key = "FloatTestShell.NativeDiagnostics.v1"
    private let maxEvents = 64
    private let formatter = ISO8601DateFormatter()

    private init() {}

    func record(_ event: String, detail: String? = nil) {
        let entry = NativeEvent(time: formatter.string(from: Date()), event: event, detail: detail)
        var events = load()
        events.append(entry)
        if events.count > maxEvents { events.removeFirst(events.count - maxEvents) }
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() -> [NativeEvent] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let events = try? JSONDecoder().decode([NativeEvent].self, from: data) else {
            return []
        }
        return events
    }

    func makeExport() throws -> URL {
        let info = Bundle.main.infoDictionary ?? [:]
        let envelope = ExportEnvelope(
            type: "float-ios-test-shell-native-diagnostics",
            exportedAt: formatter.string(from: Date()),
            appVersion: info["CFBundleShortVersionString"] as? String ?? "unknown",
            appBuild: info["CFBundleVersion"] as? String ?? "unknown",
            iosVersion: UIDevice.current.systemVersion,
            events: load()
        )
        let data = try JSONEncoder.prettyPrinted.encode(envelope)
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("float-shell-native-diagnostics-\(Int(Date().timeIntervalSince1970)).json")
        try data.write(to: output, options: .atomic)
        return output
    }
}

private struct ExportEnvelope: Codable {
    let type: String
    let exportedAt: String
    let appVersion: String
    let appBuild: String
    let iosVersion: String
    let events: [NativeEvent]
}

private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
