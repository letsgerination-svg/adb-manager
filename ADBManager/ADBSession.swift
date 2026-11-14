import Foundation
import Network

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
        isBusy = true
        defer { isBusy = false }

        // This initial transport probe verifies reachability only.
        // Full ADB CNXN/AUTH negotiation and Android 11+ TLS pairing are the next protocol milestone.
        let candidate = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        connection = candidate

        await withCheckedContinuation { continuation in
            var resumed = false
            func finish() {
                guard !resumed else { return }
                resumed = true
                continuation.resume()
            }
            candidate.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.status = "TCP доступен. Требуется ADB-аутентификация."
                        self?.isConnected = false
                        finish()
                    case .failed(let error):
                        self?.status = "Ошибка соединения: \(error.localizedDescription)"
                        self?.isConnected = false
                        finish()
                    case .cancelled:
                        self?.status = "Соединение закрыто"
                        self?.isConnected = false
                        finish()
                    default: break
                    }
                }
            }
            candidate.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + 8) {
                Task { @MainActor in
                    if !resumed {
                        self.status = "Тайм-аут подключения"
                        candidate.cancel()
                        finish()
                    }
                }
            }
        }
    }

    func run(command: String) async {
        output = "ADB-команды пока заблокированы: полноценный протокол CNXN/AUTH ещё не подключён.\nПроверка TCP-порта сама по себе не означает подключение к ADB."
    }
}
