import Foundation
import Network
import UniformTypeIdentifiers

/// Serves only pinned, public application assets on an ephemeral loopback port.
/// Collection data and mutations are handled by a separate WK message bridge.
final class StaticAssetServer: @unchecked Sendable {
    private let root: URL
    private let queue = DispatchQueue(label: "AnkiPad.assets", qos: .userInitiated, attributes: .concurrent)
    private var listener: NWListener?
    init(root: URL) { self.root = root.standardizedFileURL.resolvingSymlinksInPath() }
    deinit { listener?.cancel() }
    func start() async throws -> URL {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            connection.start(queue: self.queue)
            self.receive(connection, accumulated: Data())
        }
        return try await withCheckedThrowingContinuation { continuation in
            let completion = AssetServerStart()
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard let port = self?.listener?.port else { return }
                    guard completion.claim() else { return }
                    continuation.resume(returning: URL(string: "http://127.0.0.1:\(port.rawValue)")!)
                case .failed(let error): if completion.claim() { continuation.resume(throwing: error) }
                case .cancelled: if completion.claim() { continuation.resume(throwing: CancellationError()) }
                default: break
                }
            }
            listener.start(queue: DispatchQueue(label: "AnkiPad.assets.state"))
        }
    }
    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            var bytes = accumulated
            if let data { bytes.append(data) }
            guard bytes.count < 65536, error == nil else { connection.cancel(); return }
            if let end = bytes.range(of: Data("\r\n\r\n".utf8)),
               let header = String(data: bytes[..<end.lowerBound], encoding: .utf8) {
                self.respond(connection, header: header)
            } else if complete { connection.cancel() }
            else { self.receive(connection, accumulated: bytes) }
        }
    }
    private func respond(_ connection: NWConnection, header: String) {
        let parts = header.components(separatedBy: "\r\n").first?.split(separator: " ") ?? []
        guard parts.count >= 2, parts[0] == "GET" else { send(connection, status: 405, mime: "text/plain", data: Data()); return }
        let target = String(parts[1]).components(separatedBy: "?")[0]
        guard let decoded = target.removingPercentEncoding else { connection.cancel(); return }
        let relative: String
        if decoded.hasPrefix("/_app/") { relative = "sveltekit/app/" + String(decoded.dropFirst(6)) }
        else if decoded.hasPrefix("/_anki/") { relative = String(decoded.dropFirst(7)) }
        else if decoded.hasPrefix("/app/") { relative = "sveltekit/" + String(decoded.dropFirst()) }
        else {
            // Dynamic routes may contain a selected file path ending in .png/.csv.
            // Serve a real public file when present; otherwise let the SPA router
            // interpret the entire path, including its extension.
            let candidate = root.appendingPathComponent("sveltekit/" + String(decoded.dropFirst())).standardizedFileURL.resolvingSymlinksInPath()
            var directory: ObjCBool = false
            if candidate.path.hasPrefix(root.path + "/"), FileManager.default.fileExists(atPath: candidate.path, isDirectory: &directory), !directory.boolValue {
                relative = "sveltekit/" + String(decoded.dropFirst())
            } else { relative = "sveltekit/index.html" }
        }
        let file = root.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
        guard file.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: file) else {
            send(connection, status: 404, mime: "text/plain", data: Data("Not found".utf8)); return
        }
        let mime: String
        switch file.pathExtension {
        case "mjs", "js": mime = "text/javascript"
        case "css": mime = "text/css"
        case "html": mime = "text/html"
        case "json": mime = "application/json"
        default: mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        }
        send(connection, status: 200, mime: mime, data: data)
    }
    private func send(_ connection: NWConnection, status: Int, mime: String, data: Data) {
        var response = Data("HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r\nContent-Type: \(mime)\r\nContent-Length: \(data.count)\r\nConnection: close\r\nCache-Control: no-cache\r\nX-Content-Type-Options: nosniff\r\n\r\n".utf8)
        response.append(data)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}

private final class AssetServerStart: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return false }
        completed = true
        return true
    }
}
