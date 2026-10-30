import Foundation

/// Read only this bundle's signed group declarations. SideStore may suffix the
/// configured group when signing for another team; never guess a container path.
enum SharedGroup {
    static func candidates(configured: String, signed: [String], legacy: [String] = []) -> [String] {
        guard configured.hasPrefix("group."), configured.count > 6 else { return [] }
        var result: [String] = []
        for name in signed + legacy + [configured] {
            guard name == configured || (name.hasPrefix(configured + ".") && name.count > configured.count + 1 && name.dropFirst(configured.count + 1).allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) })),
                  !result.contains(name) else { continue }
            result.append(name)
        }
        return result
    }
    static func container(bundle: Bundle = .main, manager: FileManager = .default) -> URL? {
        guard let configured = bundle.object(forInfoDictionaryKey: "StudySharedGroup") as? String else { return nil }
        let signed = bundle.executableURL.flatMap { try? SignedGroupReader.groups(in: $0) } ?? []
        let legacy = bundle.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
        for group in candidates(configured: configured, signed: signed, legacy: legacy) {
            if let url = manager.containerURL(forSecurityApplicationGroupIdentifier: group) { return url }
        }
        return nil
    }
}

/// LC_CODE_SIGNATURE and its XML entitlement slot are public Mach-O/code-signing
/// structures. This reads identifiers, not authentication/validation of a signer;
/// FileManager remains responsible for granting access to the container.
enum SignedGroupReader {
    enum ReadError: Error { case invalidExecutable }
    private static func integer(_ data: Data, _ offset: Int, big: Bool = false) throws -> UInt32 {
        guard offset >= 0, offset <= data.count - 4 else { throw ReadError.invalidExecutable }
        return (0..<4).reduce(0) { value, index in
            value | UInt32(data[data.startIndex + offset + index]) << UInt32((big ? 3 - index : index) * 8)
        }
    }
    static func groups(in executable: URL) throws -> [String] {
        let handle = try FileHandle(forReadingFrom: executable)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 32) ?? Data()
        guard try integer(header, 0) == 0xfeedfacf else { throw ReadError.invalidExecutable }
        let count = Int(try integer(header, 16)), bytes = Int(try integer(header, 20))
        guard count <= 32768, bytes <= 1024 * 1024, bytes >= count * 8 else { throw ReadError.invalidExecutable }
        let commands = try handle.read(upToCount: bytes) ?? Data()
        guard commands.count == bytes else { throw ReadError.invalidExecutable }
        var offset = 0
        for _ in 0..<count {
            let command = try integer(commands, offset), length = Int(try integer(commands, offset + 4))
            guard length >= 8, length <= commands.count - offset else { throw ReadError.invalidExecutable }
            if command == 0x1d {
                guard length >= 16 else { throw ReadError.invalidExecutable }
                let start = UInt64(try integer(commands, offset + 8)), size = Int(try integer(commands, offset + 12))
                guard size >= 12, size <= 16 * 1024 * 1024 else { throw ReadError.invalidExecutable }
                try handle.seek(toOffset: start)
                let signature = try handle.read(upToCount: size) ?? Data()
                guard signature.count == size else { throw ReadError.invalidExecutable }
                return try groups(inSignature: signature)
            }
            offset += length
        }
        return []
    }
    static func groups(inSignature signature: Data) throws -> [String] {
        guard try integer(signature, 0, big: true) == 0xfade0cc0 else { throw ReadError.invalidExecutable }
        let length = Int(try integer(signature, 4, big: true)), count = Int(try integer(signature, 8, big: true))
        guard length <= signature.count, length >= 12, count <= (length - 12) / 8 else { throw ReadError.invalidExecutable }
        for index in 0..<count {
            let type = try integer(signature, 12 + index * 8, big: true)
            if type != 5 { continue }
            let offset = Int(try integer(signature, 16 + index * 8, big: true))
            guard offset >= 12 + count * 8, offset <= length - 8,
                  try integer(signature, offset, big: true) == 0xfade7171 else { throw ReadError.invalidExecutable }
            let size = Int(try integer(signature, offset + 4, big: true))
            guard size >= 8, size <= length - offset else { throw ReadError.invalidExecutable }
            let payload = signature.subdata(in: (offset + 8)..<(offset + size))
            guard let plist = try PropertyListSerialization.propertyList(from: payload, format: nil) as? [String: Any] else { throw ReadError.invalidExecutable }
            return plist["com.apple.security.application-groups"] as? [String] ?? []
        }
        return []
    }
}
