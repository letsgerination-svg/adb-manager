import SwiftUI

struct ContentView: View {
    @StateObject private var adb = ADBSession()
    @State private var host = ""
    @State private var port = "5555"
    @State private var command = "shell getprop ro.build.version.release"

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.035, green: 0.055, blue: 0.09).ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("ADB MANAGER")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .tracking(2.2)
                                .foregroundStyle(.cyan)
                            Text("Управление Android")
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                            Text("Подключение и инструменты ADB по Wi-Fi")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.6))
                        }

                        panel(title: "Подключение") {
                            TextField("IP-адрес Android, например 192.168.1.20", text: $host)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.decimalPad)
                                .fieldStyle()
                            TextField("Порт", text: $port)
                                .keyboardType(.numberPad)
                                .fieldStyle()
                            Button {
                                Task { await adb.connect(host: host, port: UInt16(port) ?? 5555) }
                            } label: {
                                Label(adb.isConnected ? "Подключено" : "Подключить", systemImage: "dot.radiowaves.left.and.right")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(host.isEmpty || adb.isBusy)
                            Text(adb.status)
                                .font(.footnote)
                                .foregroundStyle(adb.isConnected ? .green : .white.opacity(0.65))
                        }

                        panel(title: "ADB-терминал") {
                            TextField("Команда ADB", text: $command, axis: .vertical)
                                .lineLimit(2...4)
                                .fieldStyle()
                            Button {
                                Task { await adb.run(command: command) }
                            } label: {
                                Label("Выполнить команду", systemImage: "terminal")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(!adb.isConnected || adb.isBusy || command.isEmpty)
                            ScrollView {
                                Text(adb.output.isEmpty ? "Вывод команд появится здесь." : adb.output)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .padding(12)
                            }
                            .frame(minHeight: 100, maxHeight: 220)
                            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                        }

                        panel(title: "Инструменты") {
                            toolRow("Приложения", "square.grid.2x2", detail: "Список пакетов Android")
                            toolRow("Установка APK", "arrow.down.app", detail: "Установка файлов APK")
                            toolRow("Системные пакеты", "gearshape.2", detail: "Отключение и включение пакетов")
                            toolRow("Информация", "info.circle", detail: "Модель, Android и состояние")
                        }
                    }
                    .padding(20)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func panel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            content()
        }
        .padding(16)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.08)))
    }

    private func toolRow(_ title: String, _ icon: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(.cyan).frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.white.opacity(0.35))
        }
        .padding(.vertical, 5)
    }
}

private extension View {
    func fieldStyle() -> some View {
        self.padding(12)
            .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(.white.opacity(0.08)))
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(13)
            .background(Color.cyan.opacity(configuration.isPressed ? 0.55 : 0.9), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(Color.black)
    }
}
