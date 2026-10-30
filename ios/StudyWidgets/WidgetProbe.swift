import Foundation

#if DEBUG
/// Bounded, local-only diagnostics for the simulator's remote widget process.
/// No deck names, card text, paths, credentials, or profile IDs are recorded.
enum WidgetProbe {
    private static let lock = NSLock()
    static func record(_ phase: String, values: [String: String] = [:]) {
        lock.lock(); defer { lock.unlock() }
        // Extension tmp files may be purged when the test runner shuts down
        // its simulator, before CI can inspect the owning container.
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent((Bundle.main.bundleIdentifier ?? "StudyWidgets") + "-widget-probe.json")
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let previous = size <= 16384 ? try? Data(contentsOf: file) : nil
        var events = (previous.flatMap { try? JSONDecoder().decode([[String: String]].self, from: $0) } ?? [])
        events = Array(events.suffix(15))
        events.append(values.merging(["phase": phase, "at": String(Date().timeIntervalSince1970)]) { _, new in new })
        if let data = try? JSONEncoder().encode(events), data.count <= 16384 { try? data.write(to: file, options: .atomic) }
        NSLog("WidgetProbe %@ %@", phase, String(describing: values))
    }
}
#endif
