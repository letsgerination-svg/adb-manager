import Foundation
import Security

enum ADBRSAError: LocalizedError {
    case keyGeneration(CFError?)
    case publicKeyUnavailable
    case invalidPublicKey
    case signingFailed(CFError?)
    case invalidModulus

    var errorDescription: String? {
        switch self {
        case .keyGeneration: return "Не удалось создать ADB RSA-ключ."
        case .publicKeyUnavailable: return "Не удалось получить открытый ADB RSA-ключ."
        case .invalidPublicKey: return "Неверный формат RSA-открытого ключа."
        case .signingFailed: return "Не удалось подписать ADB AUTH token."
        case .invalidModulus: return "Неверный RSA-модуль."
        }
    }
}

/// Persistent RSA-2048 identity used by Android ADB authentication.
final class ADBRSAIdentity {
    private let tag = Data("com.letsgerination.adbmanager.rsa".utf8)
    private let privateKey: SecKey

    init() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecReturnRef as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let key = item as! SecKey? {
            privateKey = key
            return
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag
            ]
        ]

        var error: Unmanaged<CFError>?
        guard let generated = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw ADBRSAError.keyGeneration(error?.takeRetainedValue())
        }
        privateKey = generated
    }

    func sign(token: Data) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA1,
            token as CFData,
            &error
        ) else {
            throw ADBRSAError.signingFailed(error?.takeRetainedValue())
        }
        return signature as Data
    }

    func adbPublicKeyString() throws -> String {
        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let external = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            throw ADBRSAError.publicKeyUnavailable
        }

        let (modulus, exponent) = try Self.parsePKCS1PublicKey(external)
        guard modulus.count == 256, exponent <= UInt32.max else {
            throw ADBRSAError.invalidPublicKey
        }

        let modulusLE = Array(modulus.reversed())
        let words = stride(from: 0, to: 256, by: 4).map { offset -> UInt32 in
            UInt32(modulusLE[offset]) |
            (UInt32(modulusLE[offset + 1]) << 8) |
            (UInt32(modulusLE[offset + 2]) << 16) |
            (UInt32(modulusLE[offset + 3]) << 24)
        }
        guard words.count == 64, words[63] & 0x8000_0000 != 0 else {
            throw ADBRSAError.invalidModulus
        }

        // n0inv = -n[0]^-1 modulo 2^32, using Newton iteration.
        var inverse = words[0]
        for _ in 0..<5 {
            inverse = inverse &* (2 &- (words[0] &* inverse))
        }
        let n0inv = 0 &- inverse

        // rr = 2^4096 mod n, represented as 64 little-endian UInt32 words.
        var rr = [UInt32](repeating: 0, count: 64)
        rr[0] = 1
        for _ in 0..<4096 {
            var carry: UInt64 = 0
            for index in 0..<64 {
                let value = (UInt64(rr[index]) << 1) | carry
                rr[index] = UInt32(truncatingIfNeeded: value)
                carry = value >> 32
            }
            if carry != 0 || Self.compare(rr, words) >= 0 {
                var borrow: UInt64 = 0
                for index in 0..<64 {
                    let lhs = UInt64(rr[index])
                    let rhs = UInt64(words[index]) + borrow
                    rr[index] = UInt32(truncatingIfNeeded: lhs &- rhs)
                    borrow = lhs < rhs ? 1 : 0
                }
            }
        }

        var key = Data()
        Self.appendLE(UInt32(64), to: &key)
        Self.appendLE(n0inv, to: &key)
        for word in words { Self.appendLE(word, to: &key) }
        for word in rr { Self.appendLE(word, to: &key) }
        Self.appendLE(UInt32(exponent), to: &key)

        return Data(key).base64EncodedString() + " vasiliy@iphone\0"
    }

    private static func compare(_ lhs: [UInt32], _ rhs: [UInt32]) -> Int {
        for index in stride(from: lhs.count - 1, through: 0, by: -1) {
            if lhs[index] < rhs[index] { return -1 }
            if lhs[index] > rhs[index] { return 1 }
        }
        return 0
    }

    private static func appendLE(_ value: UInt32, to data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }

    private static func parsePKCS1PublicKey(_ der: Data) throws -> (Data, UInt64) {
        var cursor = 0
        guard readByte(der, &cursor) == 0x30 else { throw ADBRSAError.invalidPublicKey }
        _ = try readLength(der, &cursor)
        guard readByte(der, &cursor) == 0x02 else { throw ADBRSAError.invalidPublicKey }
        let modulusLength = try readLength(der, &cursor)
        guard cursor + modulusLength <= der.count else { throw ADBRSAError.invalidPublicKey }
        var modulus = Data(der[cursor..<(cursor + modulusLength)])
        cursor += modulusLength
        while modulus.first == 0 { modulus.removeFirst() }

        guard readByte(der, &cursor) == 0x02 else { throw ADBRSAError.invalidPublicKey }
        let exponentLength = try readLength(der, &cursor)
        guard exponentLength > 0, exponentLength <= 4, cursor + exponentLength <= der.count else {
            throw ADBRSAError.invalidPublicKey
        }
        var exponent: UInt64 = 0
        for byte in der[cursor..<(cursor + exponentLength)] {
            exponent = (exponent << 8) | UInt64(byte)
        }
        guard modulus.count == 256 else { throw ADBRSAError.invalidPublicKey }
        return (modulus, exponent)
    }

    private static func readByte(_ data: Data, _ cursor: inout Int) -> UInt8? {
        guard cursor < data.count else { return nil }
        defer { cursor += 1 }
        return data[cursor]
    }

    private static func readLength(_ data: Data, _ cursor: inout Int) throws -> Int {
        guard let first = readByte(data, &cursor) else { throw ADBRSAError.invalidPublicKey }
        if first & 0x80 == 0 { return Int(first) }
        let count = Int(first & 0x7f)
        guard count > 0, count <= 4, cursor + count <= data.count else {
            throw ADBRSAError.invalidPublicKey
        }
        var length = 0
        for _ in 0..<count {
            guard let byte = readByte(data, &cursor) else { throw ADBRSAError.invalidPublicKey }
            length = (length << 8) | Int(byte)
        }
        return length
    }
}
