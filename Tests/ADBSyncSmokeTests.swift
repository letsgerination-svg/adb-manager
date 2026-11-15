import Foundation

@main
struct ADBSyncSmokeTests {
    static func main() throws {
        let send = try ADBSync.sendRequest(path: "/data/local/tmp/test.apk")
        precondition(String(data: send.prefix(4), encoding: .ascii) == "SEND")
        let sendLength = send[4..<8].withUnsafeBytes { Int($0.loadUnaligned(as: UInt32.self).littleEndian) }
        precondition(send.count == 8 + sendLength)
        precondition(String(data: send.suffix(6), encoding: .utf8) == "33188\0")

        let bytes = Data([0, 1, 2, 3, 4])
        let dataPacket = try ADBSync.dataRequest(bytes)
        let decoded = try ADBSync.decodeResponse(dataPacket)
        precondition(decoded.id == "DATA")
        precondition(decoded.payload == bytes)

        let done = ADBSync.doneRequest(modifiedAt: 1234)
        precondition(String(data: done.prefix(4), encoding: .ascii) == "DONE")
        precondition(done.count == 8)

        do {
            _ = try ADBSync.sendRequest(path: "/tmp/bad\0name.apk")
            fatalError("Invalid path was accepted")
        } catch ADBSyncError.invalidPath {
        }

        do {
            _ = try ADBSync.dataRequest(Data(repeating: 0, count: ADBSync.maximumDataChunk + 1))
            fatalError("Oversized DATA packet was accepted")
        } catch ADBSyncError.payloadTooLarge {
        }

        print("ADBSync smoke tests: PASS (SEND, DATA, DONE, path and chunk limits)")
    }
}
