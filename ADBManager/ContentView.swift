import SwiftUI

struct ContentView: View {
    @StateObject private var adb = ADBSession()
    @State private var host = ""
    @State private var port = "5555"
    @State private var command = "getprop ro.build.version.release"

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
                            Text("ADB-команды по локальной сети")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.6))
                        }

                        panel(title: "Подключение") {
                            TextField("IP-адрес Android, например 192.168.1.20", text: $host)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.decimalPad)
                                .fieldStyle()
                            TextField("Порт ADB", text: $port)
                                .keyboardType(.numberPad)
                                .fieldStyle()
                            Button {
                                Task { await adb.connect(host: host, port: UInt16(port) ?? 5555) }
                            } label: {
                                Label(adb.isConnected ? "Подключено" : "Подключить", systemImage: "dot.radiowaves.left.and.right")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(host.isEmpty || adb.isBusy || adb.isConnected)

                            if adb.isConnected {
                                Button {
                                    adb.disconnect()
                                } label: {
                                    Label("Отключить", systemImage: "xmark.circle")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(SecondaryButtonStyle())
                                .disabled(adb.isBusy)
                            }

                            Text(adb.status)
                                .font(.footnote)
                                .foregroundStyle(adb.isConnected ? .green : .white.opacity(0.65))
                        }

                        panel(title: "Быстрые действия") {
                            Button {
                                Task { await adb.run(command: "getprop ro.product.manufacturer; getprop ro.product.model; getprop ro.build.version.release; getprop ro.build.version.sdk") }
                            } label: {
                                toolRow("Информация об устройстве", "info.circle", detail: "Производитель, модель и версия Android")
                            }
                            .buttonStyle(.plain)
                            .disabled(!adb.isConnected || adb.isBusy)

                            Button {
                                Task { await adb.run(command: "pm list packages -3") }
                            } label: {
                                toolRow("Установленные приложения", "square.grid.2x2", detail: "Список пользовательских пакетов")
                            }
                            .buttonStyle(.plain)
                            .disabled(!adb.isConnected || adb.isBusy)

                            Button {
                                Task { await adb.run(command: "pm list packages -s") }
                            } label: {
                                toolRow("Системные пакеты", "gearshape.2", detail: "Список системных пакетов")
                            }
                            .buttonStyle(.plain)
                            .disabled(!adb.isConnected || adb.isBusy)
                        }

                        panel(title: "ADB-терминал") {
                            Text("Вводите shell-команду без префикса «shell:».")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.55))
                            TextField("Например: getprop ro.build.version.release", text: $command, axis: .vertical)
                                .lineLimit(2...4)
                                .textInputAutocapitalization(.never)
                                .fieldStyle()
                            Button {
                                Task { await adb.run(command: command) }
                            } label: {
                                Label("Выполнить команду", systemImage: "terminal")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(!adb.isConnected || adb.isBusy || command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            ScrollView {
                                Text(adb.output.isEmpty ? "Вывод команд появится здесь." : adb.output)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .padding(12)
                            }
                            .frame(minHeight: 100, maxHeight: 260)
                            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                        }

                        Text("Установка APK и управление состоянием пакетов пока не реализованы.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.45))
                            .padding(.horizontal, 4)
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
        .contentShape(Rectangle())
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

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(13)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.07), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white)
    }
}
