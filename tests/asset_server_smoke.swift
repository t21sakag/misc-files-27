import Foundation

@main struct AssetServerSmoke {
    static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ankipad-assets-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = folder.appendingPathComponent("public")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sveltekit/app/immutable/entry"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("css"), withIntermediateDirectories: true)
        try Data("frontend-route".utf8).write(to: root.appendingPathComponent("sveltekit/index.html"))
        try Data("export const bundled=true;".utf8).write(to: root.appendingPathComponent("sveltekit/app/immutable/entry/start.js"))
        try Data("body{color:blue}".utf8).write(to: root.appendingPathComponent("css/root-vars.css"))
        try Data("outside-private-file".utf8).write(to: folder.appendingPathComponent("secret.dat"))
        let server = StaticAssetServer(root: root)
        let base = try await server.start()
        precondition(base.host == "127.0.0.1" && base.port != nil)
        func get(_ path: String) async throws -> (String, HTTPURLResponse) {
            let url = URL(string: path, relativeTo: base)!.absoluteURL
            let (data, response) = try await URLSession.shared.data(from: url)
            return (String(decoding: data, as: UTF8.self), response as! HTTPURLResponse)
        }
        for route in ["/graphs", "/deck-options/1", "/image-occlusion/%2Ftmp%2Fdiagram.png", "/import-csv/%2Ftmp%2Fnotes.csv?test=1"] {
            let (body, response) = try await get(route)
            precondition(response.statusCode == 200 && response.mimeType == "text/html" && body == "frontend-route", "SPA route failed: " + route)
        }
        let (script, js) = try await get("/_app/immutable/entry/start.js")
        precondition(js.statusCode == 200 && js.mimeType == "text/javascript" && script == "export const bundled=true;")
        let (css, style) = try await get("/_anki/css/root-vars.css")
        precondition(style.statusCode == 200 && style.mimeType == "text/css" && css == "body{color:blue}")
        let (_, missing) = try await get("/_app/missing.js")
        precondition(missing.statusCode == 404)
        let (outside, _) = try await get("/app/../../../secret.dat")
        precondition(!outside.contains("outside-private-file"))
        var post = URLRequest(url: base.appendingPathComponent("_anki/mutate"))
        post.httpMethod = "POST"
        let (_, denied) = try await URLSession.shared.data(for: post)
        precondition((denied as! HTTPURLResponse).statusCode == 405)
        withExtendedLifetime(server) {
            print("PASS: actual loopback asset server + extension-bearing image/CSV SPA routes + public JS/CSS + missing asset + containment + POST denial")
        }
    }
}
