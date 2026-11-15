import Foundation

@main
struct ADBPacketSmokeTests {
    static func main() throws {
        let payload = Data("device::features=shell_v2\0".utf8)
        let packet = ADBPacket(command: ADBCommand.CNXN,
                               arg0: 0x01000001,
                               arg1: 256 * 1024,
                               payload: payload)
        let encoded = packet.encoded
        let header = Data(encoded.prefix(ADBPacket.headerSize))
        let body = Data(encoded.dropFirst(ADBPacket.headerSize))
        let decoded = try ADBPacket.decode(header: header, payload: body)
        precondition(decoded.command == packet.command)
        precondition(decoded.arg0 == packet.arg0)
        precondition(decoded.arg1 == packet.arg1)
        precondition(decoded.payload == payload)

        var badMagic = header
        badMagic[20] ^= 0x01
        do {
            _ = try ADBPacket.decode(header: badMagic, payload: body)
            fatalError("Invalid magic was accepted")
        } catch ADBPacketError.invalidMagic {
        }

        var badChecksum = header
        badChecksum[16] ^= 0x01
        do {
            _ = try ADBPacket.decode(header: badChecksum, payload: body)
            fatalError("Invalid checksum was accepted")
        } catch ADBPacketError.invalidChecksum {
        }

        var oversized = header
        let tooLarge = UInt32(ADBPacket.maximumPayload + 1).littleEndian
        withUnsafeBytes(of: tooLarge) { bytes in
            oversized.replaceSubrange(12..<16, with: bytes)
        }
        do {
            _ = try ADBPacket.decode(header: oversized, payload: body)
            fatalError("Oversized payload was accepted")
        } catch ADBPacketError.payloadTooLarge {
        }

        print("ADBPacket smoke tests: PASS (round-trip, magic, checksum, payload limit)")
    }
}
