import Foundation

enum ADBSyncError: Error {
    case invalidPacket
    case payloadTooLarge
    case invalidPath
}

/// ADB SYNC v1 framing helpers. Transport is carried inside an ADB "sync:" stream.
enum ADBSync {
    static let maximumDataChunk = 64 * 1024
    static let regularFileMode: UInt32 = 0o100644

    static func sendRequest(path: String, mode: UInt32 = regularFileMode) throws -> Data {
        guard !path.isEmpty, !path.contains("\0"), path.utf8.count <= 4096 else {
            throw ADBSyncError.invalidPath
        }
        let remotePath = Data((path + "," + String(mode) + "\0").utf8)
        return packet(id: "SEND", payload: remotePath)
    }

    static func dataRequest(_ data: Data) throws -> Data {
        guard !data.isEmpty, data.count <= maximumDataChunk else {
            throw ADBSyncError.payloadTooLarge
        }
        return packet(id: "DATA", payload: data)
    }

    static func doneRequest(modifiedAt: UInt32) -> Data {
        var result = Data("DONE".utf8)
        appendLE(modifiedAt, to: &result)
        return result
    }

    static func quitRequest() -> Data {
        packet(id: "QUIT", payload: Data())
    }

    static func decodeResponse(_ data: Data) throws -> (id: String, payload: Data) {
        guard data.count >= 8,
              let id = String(data: data.prefix(4), encoding: .ascii) else {
            throw ADBSyncError.invalidPacket
        }
        let length = data[4..<8].withUnsafeBytes {
            Int($0.loadUnaligned(as: UInt32.self).littleEndian)
        }
        guard length <= maximumDataChunk, data.count == 8 + length else {
            throw ADBSyncError.invalidPacket
        }
        return (id, Data(data.dropFirst(8)))
    }

    private static func packet(id: String, payload: Data) -> Data {
        var result = Data(id.utf8)
        appendLE(UInt32(payload.count), to: &result)
        result.append(payload)
        return result
    }

    private static func appendLE(_ value: UInt32, to data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
}
