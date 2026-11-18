import SwiftUI

struct MessengerView: View {
    @ObservedObject var viewModel: ZsmeViewModel
    @ObservedObject var mesh: BleMeshManager

    @State private var activeChannel = "#ogólny"
    @State private var messageInput = ""
    @State private var targetRecipient = ""
    @State private var showPeersSheet = false

    private var channels: [String] {
        let clsCode = ScheduleFilterMatcher.extractPrimaryClassCode(viewModel.preferences.selectedClassName)
        let clsChannel = clsCode.isEmpty ? "#klasa" : "#\(clsCode.lowercased())"
        let base = ["#ogólny", MeshMessage.directChannel, clsChannel, "#zastępstwa", "#pomoc"]
        let receivedChannels = mesh.messages.map(\.channel).filter { !$0.isEmpty }
        return Array(NSOrderedSet(array: base + receivedChannels)) as? [String] ?? ["#ogólny"]
    }

    private var filteredMessages: [MeshMessage] {
        if activeChannel == MeshMessage.directChannel {
            return mesh.messages.filter { $0.channel == MeshMessage.directChannel || !$0.targetRecipient.isEmpty }
        }
        return mesh.messages.filter { $0.channel == activeChannel && $0.targetRecipient.isEmpty }
    }

    private var myDisplayName: String {
        let nick = viewModel.preferences.meshNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nick.isEmpty { return nick }
        if viewModel.preferences.userRole == .teacher && !viewModel.preferences.teacherAbbreviation.isEmpty {
            return "Prof. \(viewModel.preferences.teacherAbbreviation)"
        }
        let cls = ScheduleFilterMatcher.extractPrimaryClassCode(viewModel.preferences.selectedClassName)
        return cls.isEmpty ? "Uczeń-\(mesh.myNodeId.prefix(4))" : "\(cls)-\(mesh.myNodeId.prefix(3))"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                radioStatusBar
                channelBar
                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if filteredMessages.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                        .font(.largeTitle)
                                        .foregroundStyle(ZsmeTheme.cobalt)
                                    Text("Szkolny komunikator BLE Mesh")
                                        .font(.headline)
                                    Text("Wiadomości przesyłane są bezpośrednio między telefonami przez Bluetooth Low Energy (TTL=5), bez internetu i serwerów.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .padding(24)
                            } else {
                                ForEach(filteredMessages) { msg in
                                    MeshMessageBubble(message: msg)
                                        .id(msg.id)
                                }
                            }
                        }
                        .padding(14)
                    }
                    .onChange(of: filteredMessages.count) { _ in
                        if let last = filteredMessages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()
                composerBar
            }
            .navigationTitle("Komunikator BLE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showPeersSheet = true
                    } label: {
                        Label("Węzły (\(mesh.peers.count))", systemImage: "dot.radiowaves.left.and.right")
                    }
                }
            }
            .sheet(isPresented: $showPeersSheet) {
                peersSheet
            }
        }
    }

    private var radioStatusBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(mesh.radioState.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(mesh.isRunning ? ZsmeTheme.liveGreen : .secondary)
                Text("Węzły: \(mesh.peers.count) • Odb.: \(mesh.stats.receivedCount) • Wysł.: \(mesh.stats.sentCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                if mesh.isRunning {
                    Text("Skan: \(mesh.isScanningActive ? "OK" : "…") • Nadawanie GATT: \(mesh.isAdvertisingActive ? "OK" : "…")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(mesh.isRunning ? "Zatrzymaj" : "Uruchom BLE") {
                if mesh.isRunning {
                    mesh.stop()
                } else {
                    mesh.start(displayName: myDisplayName)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(mesh.isRunning ? .gray : ZsmeTheme.cobalt)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    private var channelBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(channels, id: \.self) { ch in
                    Button {
                        activeChannel = ch
                    } label: {
                        Text(ch)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(activeChannel == ch ? ZsmeTheme.cobalt : Color(.tertiarySystemFill))
                            .foregroundStyle(activeChannel == ch ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private var composerBar: some View {
        VStack(spacing: 6) {
            if activeChannel == MeshMessage.directChannel {
                TextField("Nick lub ID odbiorcy...", text: $targetRecipient)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }
            HStack(spacing: 8) {
                TextField("Napisz wiadomość w \(activeChannel)...", text: $messageInput)
                    .textFieldStyle(.roundedBorder)
                Button {
                    let text = messageInput
                    messageInput = ""
                    mesh.sendMessage(
                        senderName: myDisplayName,
                        senderClass: ScheduleFilterMatcher.extractPrimaryClassCode(viewModel.preferences.selectedClassName),
                        channel: activeChannel,
                        text: text,
                        targetRecipient: activeChannel == MeshMessage.directChannel ? targetRecipient : ""
                    )
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(ZsmeTheme.cobalt)
                .disabled(messageInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
    }

    private var peersSheet: some View {
        NavigationStack {
            List {
                if mesh.peers.isEmpty {
                    Text("Nie wykryto jeszcze innych urządzeń ZSME Assistant w pobliżu.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(mesh.peers) { peer in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(peer.displayName).font(.headline)
                                Text("ID: \(peer.nodeId)").font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(peer.rssi) dBm")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Urządzenia w sieci BLE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zamknij") { showPeersSheet = false }
                }
            }
        }
    }
}

private struct MeshMessageBubble: View {
    let message: MeshMessage

    var body: some View {
        HStack {
            if message.isMine { Spacer(minLength: 48) }
            VStack(alignment: message.isMine ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(message.senderName)
                        .font(.caption2.weight(.bold))
                    if !message.senderClass.isEmpty {
                        Text(message.senderClass)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if message.hopCount > 0 {
                        Text("• \(message.hopCount) skok")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Text(message.text)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(message.isMine ? ZsmeTheme.cobalt : Color(.secondarySystemBackground))
                    .foregroundStyle(message.isMine ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            if !message.isMine { Spacer(minLength: 48) }
        }
    }
}
