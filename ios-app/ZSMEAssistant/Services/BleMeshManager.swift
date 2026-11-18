import Foundation
import CoreBluetooth

struct MeshMessage: Codable, Identifiable, Hashable {
    static let defaultTTL = 5
    static let directChannel = "@prywatne"

    let id: String
    let senderName: String
    var senderClass: String = ""
    var channel: String = "#ogólny"
    let text: String
    let timestampMillis: Int64
    var hopCount: Int = 0
    var ttl: Int = defaultTTL
    let originNodeId: String
    var relayTrail: [String] = []
    var isMine: Bool = false
    var targetRecipient: String = ""
    var isProbe: Bool = false
    var isProbeAck: Bool = false
}

struct MeshPeer: Identifiable, Hashable {
    var id: String { deviceIdentifier }
    let deviceIdentifier: String
    let nodeId: String
    let displayName: String
    let rssi: Int
    let lastSeenMillis: Int64
}

enum MeshRadioState: String {
    case idle = "Wyłączona"
    case starting = "Uruchamianie sieci BLE..."
    case active = "Aktywna sieć kratowa"
    case unauthorized = "Wymagane uprawnienia Bluetooth"
    case poweredOff = "Bluetooth wyłączony"
    case unsupported = "Brak modułu BLE"
}

struct MeshStats {
    var sentCount: Int = 0
    var receivedCount: Int = 0
    var relayedCount: Int = 0
}

/// 20-byte ATT MTU safe frame chunker matching Android ZSME-Assistant protocol:
/// bytes 0..1: magic 'Z','M' (0x5A, 0x4D)
/// bytes 2..5: 32-bit packet tag
/// byte 6: chunk index
/// byte 7: total chunks
/// bytes 8..19: UTF-8 JSON payload slice
enum MeshPacketChunker {
    private static let magic0: UInt8 = 0x5A
    private static let magic1: UInt8 = 0x4D
    private static let headerSize = 8
    private static let maxSlice = 12

    static func split(_ message: MeshMessage) -> [Data] {
        guard let raw = try? JSONEncoder().encode(message) else { return [] }
        let tag = UInt32.random(in: 1...UInt32.max)
        let totalChunks = max(1, (raw.count + maxSlice - 1) / maxSlice)
        guard totalChunks <= 255 else { return [] }

        var frames: [Data] = []
        for idx in 0..<totalChunks {
            let start = idx * maxSlice
            let end = min(start + maxSlice, raw.count)
            var frame = Data([magic0, magic1])
            var bigEndianTag = tag.bigEndian
            frame.append(Data(bytes: &bigEndianTag, count: 4))
            frame.append(UInt8(idx))
            frame.append(UInt8(totalChunks))
            frame.append(raw[start..<end])
            frames.append(frame)
        }
        return frames
    }

    final class FrameAssembler {
        private struct PartialPacket {
            let totalChunks: Int
            var chunks: [Int: Data] = [:]
            let createdAt = Date()
        }
        private var buffers: [String: PartialPacket] = [:]

        func acceptFrame(sourceKey: String, data: Data) -> MeshMessage? {
            guard data.count >= headerSize,
                  data[0] == magic0,
                  data[1] == magic1 else { return nil }
            let tag = data.subdata(in: 2..<6).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            let chunkIdx = Int(data[6])
            let totalChunks = Int(data[7])
            guard totalChunks > 0, chunkIdx < totalChunks else { return nil }

            let key = "\(sourceKey):\(tag)"
            var partial = buffers[key] ?? PartialPacket(totalChunks: totalChunks)
            partial.chunks[chunkIdx] = data.subdata(in: headerSize..<data.count)
            buffers[key] = partial

            if partial.chunks.count == partial.totalChunks {
                buffers.removeValue(forKey: key)
                var assembled = Data()
                for i in 0..<partial.totalChunks {
                    guard let part = partial.chunks[i] else { return nil }
                    assembled.append(part)
                }
                return try? JSONDecoder().decode(MeshMessage.self, from: assembled)
            }

            let cutoff = Date().addingTimeInterval(-30)
            buffers = buffers.filter { $0.value.createdAt >= cutoff }
            return nil
        }
    }
}

@MainActor
final class BleMeshManager: NSObject, ObservableObject {
    nonisolated static let meshServiceUUID = CBUUID(string: "7A534D45-0001-4000-8000-5A534D454D45")
    nonisolated static let meshPacketCharUUID = CBUUID(string: "7A534D45-0002-4000-8000-5A534D454D45")

    @Published private(set) var radioState: MeshRadioState = .idle
    @Published private(set) var peers: [MeshPeer] = []
    @Published private(set) var messages: [MeshMessage] = []
    @Published private(set) var stats = MeshStats()
    @Published private(set) var isRunning = false

    let myNodeId = String(UUID().uuidString.prefix(8)).uppercased()
    private var myDisplayLabel = "Uczeń ZSME"

    private var centralManager: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    private var packetCharacteristic: CBMutableCharacteristic?

    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var pendingWrites: [UUID: [Data]] = [:]
    private var seenIds: Set<String> = []
    private var relayCache: [MeshMessage] = []
    private let assembler = MeshPacketChunker.FrameAssembler()

    func start(displayName: String) {
        myDisplayLabel = displayName.isEmpty ? "Uczeń ZSME" : displayName
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        }
        if peripheralManager == nil {
            peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        }
        isRunning = true
        radioState = .starting
        if centralManager?.state == .poweredOn {
            beginScanning()
        }
        if peripheralManager?.state == .poweredOn {
            beginAdvertising()
        }
    }

    func stop() {
        isRunning = false
        centralManager?.stopScan()
        peripheralManager?.stopAdvertising()
        radioState = .idle
    }

    func sendMessage(senderName: String, senderClass: String, channel: String, text: String, targetRecipient: String = "") {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }
        let cleanTarget = targetRecipient.trimmingCharacters(in: .whitespacesAndNewlines)
        let msg = MeshMessage(
            id: String(UUID().uuidString.prefix(12)),
            senderName: senderName.isEmpty ? "Uczeń ZSME" : senderName,
            senderClass: senderClass,
            channel: cleanTarget.isEmpty ? channel : MeshMessage.directChannel,
            text: cleanText,
            timestampMillis: Int64(Date().timeIntervalSince1970 * 1000),
            hopCount: 0,
            ttl: MeshMessage.defaultTTL,
            originNodeId: myNodeId,
            relayTrail: [],
            isMine: true,
            targetRecipient: cleanTarget
        )
        seenIds.insert(msg.id)
        relayCache.append(msg)
        if relayCache.count > 80 { relayCache.removeFirst() }
        messages.append(msg)
        stats.sentCount += 1
        broadcastToNearbyPeers(msg)
    }

    private func broadcastToNearbyPeers(_ message: MeshMessage) {
        let frames = MeshPacketChunker.split(message)
        guard !frames.isEmpty else { return }
        for (uuid, peripheral) in discoveredPeripherals {
            pendingWrites[uuid] = frames
            peripheral.delegate = self
            if peripheral.state == .connected {
                peripheral.discoverServices([Self.meshServiceUUID])
            } else {
                centralManager?.connect(peripheral, options: nil)
            }
        }
    }

    private func beginScanning() {
        guard isRunning, centralManager?.state == .poweredOn else { return }
        centralManager?.scanForPeripherals(
            withServices: [Self.meshServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        radioState = .active
    }

    private func beginAdvertising() {
        guard isRunning, peripheralManager?.state == .poweredOn else { return }
        if packetCharacteristic == nil {
            let char = CBMutableCharacteristic(
                type: Self.meshPacketCharUUID,
                properties: [.write, .writeWithoutResponse, .notify],
                value: nil,
                permissions: [.writeable]
            )
            let service = CBMutableService(type: Self.meshServiceUUID, primary: true)
            service.characteristics = [char]
            peripheralManager?.add(service)
            packetCharacteristic = char
        }
        peripheralManager?.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Self.meshServiceUUID],
            CBAdvertisementDataLocalNameKey: "ZSME-\(myNodeId.prefix(4))"
        ])
    }

    private func handleDecodedMessage(_ msg: MeshMessage, fromPeer source: String) {
        guard msg.originNodeId != myNodeId, !seenIds.contains(msg.id) else { return }
        seenIds.insert(msg.id)
        stats.receivedCount += 1

        let isDirect = !msg.targetRecipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isForMe = !isDirect ||
            msg.targetRecipient.caseInsensitiveCompare(myDisplayLabel) == .orderedSame ||
            msg.targetRecipient.caseInsensitiveCompare(myNodeId) == .orderedSame

        if isForMe && !msg.isProbe && !msg.isProbeAck {
            var display = msg
            display.isMine = false
            messages.append(display)
        }

        if msg.ttl > 1 && !(isDirect && isForMe) {
            var forward = msg
            forward.ttl -= 1
            forward.hopCount += 1
            forward.relayTrail = Array((msg.relayTrail + [myDisplayLabel]).suffix(6))
            forward.isMine = false
            relayCache.append(forward)
            stats.relayedCount += 1
            broadcastToNearbyPeers(forward)
        }
        _ = source
    }
}

extension BleMeshManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                if self.isRunning { self.beginScanning() }
            case .poweredOff:
                self.radioState = .poweredOff
            case .unauthorized:
                self.radioState = .unauthorized
            case .unsupported:
                self.radioState = .unsupported
            default:
                break
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let localName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "Uczeń ZSME"
        let rssiVal = RSSI.intValue
        Task { @MainActor in
            self.discoveredPeripherals[peripheral.identifier] = peripheral
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let peer = MeshPeer(
                deviceIdentifier: peripheral.identifier.uuidString,
                nodeId: String(peripheral.identifier.uuidString.prefix(4)).uppercased(),
                displayName: localName,
                rssi: rssiVal,
                lastSeenMillis: nowMs
            )
            if let idx = self.peers.firstIndex(where: { $0.id == peer.id }) {
                self.peers[idx] = peer
            } else {
                self.peers.append(peer)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([BleMeshManager.meshServiceUUID])
    }
}

extension BleMeshManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == BleMeshManager.meshServiceUUID {
            peripheral.discoverCharacteristics([BleMeshManager.meshPacketCharUUID], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for char in chars where char.uuid == BleMeshManager.meshPacketCharUUID {
            Task { @MainActor in
                if let frames = self.pendingWrites.removeValue(forKey: peripheral.identifier) {
                    for frame in frames {
                        peripheral.writeValue(frame, for: char, type: .withoutResponse)
                    }
                }
            }
        }
    }
}

extension BleMeshManager: CBPeripheralManagerDelegate {
    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        Task { @MainActor in
            if peripheral.state == .poweredOn && self.isRunning {
                self.beginAdvertising()
            }
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for req in requests {
            if let value = req.value {
                let sourceKey = req.central.identifier.uuidString
                Task { @MainActor in
                    if let decoded = self.assembler.acceptFrame(sourceKey: sourceKey, data: value) {
                        self.handleDecodedMessage(decoded, fromPeer: sourceKey)
                    }
                }
            }
            peripheral.respond(to: req, withResult: .success)
        }
    }
}
