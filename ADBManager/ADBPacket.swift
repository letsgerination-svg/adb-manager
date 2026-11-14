import Foundation

enum ADBPacketError: Error {
    case invalidHeader
    case invalidMagic
    case invalidChecksum
    case payloadTooLarge
}

/// ADB wire packet: six little-endian UInt32 fields followed by payload.
struct ADBPacket {
    static let headerSize = 24
    static let maximumPayload = 1024 * 1024

    let command: UInt32
    let arg0: UInt32
    let arg1: UInt32
    let payload: Data

    var encoded: Data {
        var bytes = Data()
        let length = UInt32(payload.count)
        let checksum = payload.reduce(UInt32(0)) { $0 &+ UInt32($1) }
        for value in [command, arg0, arg1, length, checksum, command ^ 0xFFFF_FFFF] {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { bytes.append(contentsOf: $0) }
        }
        bytes.append(payload)
        return bytes
    }

    static func decode(header: Data, payload: Data) throws -> ADBPacket {
        guard header.count == headerSize else { throw ADBPacketError.invalidHeader }
        let fields = stride(from: 0, to: headerSize, by: 4).map { offset -> UInt32 in
            header[offset..<(offset + 4)].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
        }
        guard fields[5] == (fields[0] ^ 0xFFFF_FFFF) else { throw ADBPacketError.invalidMagic }
        guard fields[3] <= maximumPayload, payload.count == Int(fields[3]) else {
            throw ADBPacketError.payloadTooLarge
        }
        let checksum = payload.reduce(UInt32(0)) { $0 &+ UInt32($1) }
        guard checksum == fields[4] else { throw ADBPacketError.invalidChecksum }
        return ADBPacket(command: fields[0], arg0: fields[1], arg1: fields[2], payload: payload)
    }
}

enum ADBCommand {
    static let CNXN: UInt32 = 0x4E584E43
    static let OPEN: UInt32 = 0x4E45504F
    static let AUTH: UInt32 = 0x48545541
    static let STLS: UInt32 = 0x534C5453
    static let OKAY: UInt32 = 0x59414B4F
    static let FAIL: UInt32 = 0x4C494146
    static let WRTE: UInt32 = 0x45545257
    static let CLSE: UInt32 = 0x45534C43
}
