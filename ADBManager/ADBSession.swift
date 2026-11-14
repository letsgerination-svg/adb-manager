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

    func connect(host: String, port: UInt16) async {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            status = "Некорректный порт"
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

            let banner = Data("host::features=shell_v2,cmd,stat_v2,ls_v2\0".utf8)
            let hello = ADBPacket(command: ADBCommand.CNXN,
                                  arg0: 0x01000001,
                                  arg1: 256 * 1024,
                                  payload: banner)
            try await send(hello.encoded, over: candidate)

            let header = try await receiveExactly(ADBPacket.headerSize, from: candidate)
            let payloadLength = Int(header[12..<16].withUnsafeBytes {
                $0.loadUnaligned(as: UInt32.self).littleEndian
            })
            guard payloadLength <= ADBPacket.maximumPayload else {
                throw ADBPacketError.payloadTooLarge
            }
            let payload = payloadLength == 0 ? Data() : try await receiveExactly(payloadLength, from: candidate)
            let response = try ADBPacket.decode(header: header, payload: payload)

            switch response.command {
            case ADBCommand.AUTH:
                status = "Android запросил ADB AUTH. Следующий этап — RSA-ключ и подтверждение на Android."
                output = "Получен пакет AUTH (тип \(response.arg0)).\nТранспорт ADB отвечает. Авторизация ещё не завершена."
            case ADBCommand.CNXN:
                status = "ADB CNXN принят. Проверяем возможности соединения."
                output = String(data: response.payload, encoding: .utf8) ?? "Получен ответ CNXN."
                isConnected = true
            case ADBCommand.FAIL:
                status = "Android отклонил ADB-соединение."
                output = String(data: response.payload, encoding: .utf8) ?? "ADB FAIL"
            default:
                status = "Получен неожиданный пакет ADB: 0x" + String(response.command, radix: 16)
                output = "Ответ получен, но рукопожатие не завершено."
            }
        } catch {
            status = "Ошибка ADB: \(error.localizedDescription)"
            isConnected = false
            candidate.cancel()
            connection = nil
        }
    }

    func run(command: String) async {
        guard isConnected else {
            output = "Нет авторизованного ADB-соединения. Сначала завершите RSA/TLS-аутентификацию."
            return
        }
        output = "ADB-транспорт установлен, но интерактивный shell ещё не реализован."
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
        status = "Не подключено"
    }

    private func start(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { continuation in
            var completed = false
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready where !completed:
                    completed = true
                    continuation.resume()
                case .failed(let error) where !completed:
                    completed = true
                    continuation.resume(throwing: error)
                case .cancelled where !completed:
                    completed = true
                    continuation.resume(throwing: NWError.posix(.ECANCELED))
                default: break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    private func send(_ data: Data, over connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            })
        }
    }

    private func receiveExactly(_ count: Int, from connection: NWConnection) async throws -> Data {
        var collected = Data()
        while collected.count < count {
            let remaining = count - collected.count
            let chunk: Data = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: remaining, maximumLength: remaining) { data, _, isComplete, error in
                    if let error { continuation.resume(throwing: error); return }
                    if let data, !data.isEmpty {
                        continuation.resume(returning: data)
                    } else if isComplete {
                        continuation.resume(throwing: NWError.posix(.ECONNRESET))
                    } else {
                        continuation.resume(throwing: NWError.posix(.EWOULDBLOCK))
                    }
                }
            }
            collected.append(chunk)
        }
        return collected
    }
}
