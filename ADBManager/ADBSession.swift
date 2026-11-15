import Foundation
import Network
import Combine

@MainActor
final class ADBSession: ObservableObject {
    @Published private(set) var status = "Не подключено"
    @Published private(set) var isConnected = false
    @Published private(set) var isBusy = false
    @Published private(set) var output = ""

    private var connection: NWConnection?
    private var nextLocalID: UInt32 = 1
    private var rsaIdentity: ADBRSAIdentity?

    func connect(host: String, port: UInt16) async {
        guard !isBusy else { return }
        guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let nwPort = NWEndpoint.Port(rawValue: port) else {
            status = "Проверьте IP-адрес и порт"
            return
        }

        disconnect()
        isBusy = true
        defer { isBusy = false }

        let candidate = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        connection = candidate

        do {
            try await start(candidate)
            status = "TCP-соединение установлено. Отправка ADB CNXN…"

            let banner = Data("host::features=;\0".utf8)
            let hello = ADBPacket(command: ADBCommand.CNXN,
                                  arg0: 0x01000001,
                                  arg1: 256 * 1024,
                                  payload: banner)
            try await send(hello, over: candidate)

            var didSendSignature = false
            var didSendPublicKey = false
            while true {
                let response = try await receivePacket(from: candidate)
                switch response.command {
                case ADBCommand.AUTH:
                    guard let identity = try? ADBRSAIdentity() else {
                        throw ADBSessionError.authenticationUnavailable
                    }
                    rsaIdentity = identity
                    if response.arg0 == 1 && !didSendSignature {
                        let signature = try identity.sign(token: response.payload)
                        try await send(ADBPacket(command: ADBCommand.AUTH, arg0: 2, arg1: 0, payload: signature), over: candidate)
                        didSendSignature = true
                        status = "Отправлена RSA-подпись. Ожидаю ответ Android…"
                        continue
                    }
                    if response.arg0 == 1 && didSendSignature && !didSendPublicKey {
                        let publicKey = Data(try identity.adbPublicKeyString().utf8)
                        try await send(ADBPacket(command: ADBCommand.AUTH, arg0: 3, arg1: 0, payload: publicKey), over: candidate)
                        didSendPublicKey = true
                        status = "Открытый RSA-ключ отправлен. Подтвердите запрос на Android."
                        output = "На Android должно появиться окно разрешения отладки. Разрешите подключение."
                        continue
                    }
                    throw ADBSessionError.authenticationRejected
                case ADBCommand.CNXN:
                    isConnected = true
                    status = "ADB-транспорт подключён"
                    output = String(data: response.payload, encoding: .utf8) ?? "Получен ответ CNXN."
                    return
                case ADBCommand.FAIL:
                    isConnected = false
                    status = "Android отклонил ADB-соединение"
                    output = String(data: response.payload, encoding: .utf8) ?? "ADB FAIL"
                    candidate.cancel()
                    connection = nil
                    return
                default:
                    throw ADBSessionError.unexpectedPacket(response.command)
                }
            }
        } catch {
            status = "Ошибка ADB: \(error.localizedDescription)"
            isConnected = false
            candidate.cancel()
            connection = nil
        }
    }

    func run(command: String) async {
        guard !isBusy else { return }
        guard isConnected, let connection else {
            output = "Нет подключённого ADB-транспорта."
            return
        }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            output = "Введите команду."
            return
        }

        isBusy = true
        status = "Выполняется команда…"
        defer {
            isBusy = false
            if isConnected { status = "ADB-транспорт подключён" }
        }

        let localID = nextLocalID
        nextLocalID &+= 1
        let open = ADBPacket(command: ADBCommand.OPEN,
                             arg0: localID,
                             arg1: 0,
                             payload: Data(("shell:" + trimmed + "\0").utf8))

        do {
            try await send(open, over: connection)
            var remoteID: UInt32?
            var result = Data()
            let maxOutput = 1024 * 1024

            while true {
                let packet = try await receivePacket(from: connection)
                switch packet.command {
                case ADBCommand.OKAY:
                    guard packet.arg1 == localID else { continue }
                    remoteID = packet.arg0
                case ADBCommand.WRTE:
                    guard let remoteID, packet.arg0 == remoteID, packet.arg1 == localID else {
                        throw ADBSessionError.invalidStream
                    }
                    if result.count + packet.payload.count > maxOutput {
                        throw ADBSessionError.outputTooLarge
                    }
                    result.append(packet.payload)
                    try await send(ADBPacket(command: ADBCommand.OKAY,
                                              arg0: localID,
                                              arg1: remoteID,
                                              payload: Data()), over: connection)
                case ADBCommand.CLSE:
                    let peerID = packet.arg0
                    try await send(ADBPacket(command: ADBCommand.CLSE,
                                              arg0: localID,
                                              arg1: peerID,
                                              payload: Data()), over: connection)
                    output = String(data: result, encoding: .utf8) ?? result.map { String(format: "%02x", $0) }.joined()
                    return
                case ADBCommand.FAIL:
                    throw ADBSessionError.deviceFailure(String(data: packet.payload, encoding: .utf8) ?? "ADB FAIL")
                default:
                    throw ADBSessionError.unexpectedPacket(packet.command)
                }
            }
        } catch {
            output = "Ошибка выполнения команды: \(error.localizedDescription)"
        }
    }


    func installAPK(from fileURL: URL) async {
        guard !isBusy else { return }
        guard isConnected, let connection else {
            output = "Сначала подключите Android по ADB."
            return
        }

        isBusy = true
        status = "Подготовка APK…"
        var didStartAccess = false
        do {
            didStartAccess = fileURL.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess { fileURL.stopAccessingSecurityScopedResource() }
            }

            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
            guard fileSize > 0 else { throw ADBInstallError.emptyFile }

            let remotePath = "/data/local/tmp/adbmanager-install.apk"
            let localID = nextLocalID
            nextLocalID &+= 1
            try await send(ADBPacket(command: ADBCommand.OPEN, arg0: localID, arg1: 0,
                                     payload: Data("sync:\0".utf8)), over: connection)

            var remoteID: UInt32?
            while remoteID == nil {
                let packet = try await receivePacket(from: connection)
                guard packet.command == ADBCommand.OKAY, packet.arg1 == localID else {
                    throw ADBInstallError.invalidStream
                }
                remoteID = packet.arg0
            }

            let peerID = remoteID!
            let sendRequest = try ADBSync.sendRequest(path: remotePath)
            try await sendSyncPayload(sendRequest, localID: localID, remoteID: peerID, over: connection)

            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            var transferred = 0
            while let chunk = try handle.read(upToCount: ADBSync.maximumDataChunk), !chunk.isEmpty {
                let request = try ADBSync.dataRequest(chunk)
                try await sendSyncPayload(request, localID: localID, remoteID: peerID, over: connection)
                transferred += chunk.count
                status = "Передача APK: \(transferred / 1024) / \(max(fileSize / 1024, 1)) КБ"
            }

            let done = ADBSync.doneRequest(modifiedAt: UInt32(Date().timeIntervalSince1970))
            try await sendSyncPayload(done, localID: localID, remoteID: peerID, over: connection)

            var installResult: String?
            while installResult == nil {
                let packet = try await receivePacket(from: connection)
                if packet.command == ADBCommand.OKAY, packet.arg1 == localID {
                    continue
                }
                guard packet.command == ADBCommand.WRTE,
                      packet.arg0 == peerID, packet.arg1 == localID else {
                    if packet.command == ADBCommand.CLSE {
                        throw ADBInstallError.streamClosed
                    }
                    throw ADBInstallError.invalidStream
                }
                try await send(ADBPacket(command: ADBCommand.OKAY, arg0: localID, arg1: peerID, payload: Data()), over: connection)
                let response = try ADBSync.decodeResponse(packet.payload)
                if response.id == "OKAY" {
                    installResult = "APK передан на Android."
                } else if response.id == "FAIL" {
                    installResult = "Ошибка передачи: " + (String(data: response.payload, encoding: .utf8) ?? "неизвестная ошибка")
                } else {
                    throw ADBInstallError.invalidSyncResponse
                }
            }

            try await send(ADBPacket(command: ADBCommand.CLSE, arg0: localID, arg1: peerID, payload: Data()), over: connection)
            isBusy = false
            status = "APK передан. Установка…"
            output = installResult ?? "APK передан."
            await run(command: "pm install -r \"\(remotePath)\"")
        } catch {
            isBusy = false
            status = "Ошибка передачи APK"
            output = error.localizedDescription
        }
    }

    private func sendSyncPayload(_ payload: Data, localID: UInt32, remoteID: UInt32, over connection: NWConnection) async throws {
        try await send(ADBPacket(command: ADBCommand.WRTE, arg0: localID, arg1: remoteID, payload: payload), over: connection)
        while true {
            let response = try await receivePacket(from: connection)
            if response.command == ADBCommand.OKAY,
               response.arg0 == remoteID, response.arg1 == localID {
                return
            }
            if response.command == ADBCommand.FAIL {
                throw ADBInstallError.deviceFailure(String(data: response.payload, encoding: .utf8) ?? "ADB FAIL")
            }
            throw ADBInstallError.invalidStream
        }
    }


    func managePackage(_ rawName: String, action: PackageAction) async {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.range(of: #"^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$"#, options: .regularExpression) != nil else {
            output = "Неверное имя пакета. Пример: com.example.app"
            return
        }
        let command: String
        switch action {
        case .uninstall:
            command = "pm uninstall --user 0 \"\(name)\""
        case .disable:
            command = "pm disable-user --user 0 \"\(name)\""
        case .enable:
            command = "pm enable \"\(name)\""
        }
        await run(command: command)
    }

    func reportError(_ message: String) {
        output = message
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
        isBusy = false
        status = "Не подключено"
        output = ""
    }

    private func start(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ContinuationGate()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if gate.claim() { continuation.resume() }
                case .failed(let error):
                    if gate.claim() { continuation.resume(throwing: error) }
                case .cancelled:
                    if gate.claim() { continuation.resume(throwing: NWError.posix(.ECANCELED)) }
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    private func send(_ packet: ADBPacket, over connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: packet.encoded, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            })
        }
    }

    private func receivePacket(from connection: NWConnection) async throws -> ADBPacket {
        let header = try await receiveExactly(ADBPacket.headerSize, from: connection)
        let payloadLength = header[12..<16].withUnsafeBytes {
            Int($0.loadUnaligned(as: UInt32.self).littleEndian)
        }
        guard payloadLength <= ADBPacket.maximumPayload else {
            throw ADBPacketError.payloadTooLarge
        }
        let payload = payloadLength == 0 ? Data() : try await receiveExactly(payloadLength, from: connection)
        return try ADBPacket.decode(header: header, payload: payload)
    }

    private func receiveExactly(_ count: Int, from connection: NWConnection) async throws -> Data {
        var collected = Data()
        while collected.count < count {
            let remaining = count - collected.count
            let chunk: Data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { data, _, isComplete, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let data, !data.isEmpty {
                        continuation.resume(returning: data)
                    } else if isComplete {
                        continuation.resume(throwing: NWError.posix(.ECONNRESET))
                    } else {
                        // Network.framework may deliver an empty, non-final callback.
                        // Keep waiting instead of treating it as a fatal EWOULDBLOCK.
                        continuation.resume(returning: Data())
                    }
                }
            }
            if !chunk.isEmpty {
                collected.append(chunk)
            }
        }
        return collected
    }
}

private final class ContinuationGate: @unchecked Sendable {
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

private enum ADBInstallError: LocalizedError {
    case emptyFile
    case invalidStream
    case streamClosed
    case invalidSyncResponse
    case deviceFailure(String)

    var errorDescription: String? {
        switch self {
        case .emptyFile: return "Выбран пустой файл."
        case .invalidStream: return "Нарушен протокол ADB SYNC."
        case .streamClosed: return "Android закрыл поток передачи."
        case .invalidSyncResponse: return "Android вернул неизвестный ответ SYNC."
        case .deviceFailure(let message): return message
        }
    }
}

private enum ADBSessionError: LocalizedError {
    case unexpectedPacket(UInt32)
    case invalidStream
    case outputTooLarge
    case deviceFailure(String)
    case authenticationUnavailable
    case authenticationRejected

    var errorDescription: String? {
        switch self {
        case .unexpectedPacket(let command):
            return "Неожиданный пакет ADB: 0x" + String(command, radix: 16)
        case .invalidStream:
            return "Неверные идентификаторы ADB-потока."
        case .outputTooLarge:
            return "Вывод команды превысил 1 МБ."
        case .deviceFailure(let message):
            return message
        case .authenticationUnavailable:
            return "Не удалось подготовить RSA-ключ ADB."
        case .authenticationRejected:
            return "Android отклонил RSA-авторизацию или прислал неожиданный AUTH. Проверьте запрос на устройстве."
        }
    }
}


enum PackageAction {
    case uninstall
    case disable
    case enable
}
