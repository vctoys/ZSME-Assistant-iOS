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

    enum CodingKeys: String, CodingKey {
        case id
        case senderName
        case senderClass
        case channel
        case text
        case timestampMillis
        case hopCount
        case ttl
        case originNodeId
        case relayTrail
        case isMine
        case targetRecipient
        case isProbe
        case isProbeAck
    }

    init(
        id: String,
        senderName: String,
        senderClass: String = "",
        channel: String = "#ogólny",
        text: String,
        timestampMillis: Int64,
        hopCount: Int = 0,
        ttl: Int = defaultTTL,
        originNodeId: String,
        relayTrail: [String] = [],
        isMine: Bool = false,
        targetRecipient: String = "",
        isProbe: Bool = false,
        isProbeAck: Bool = false
    ) {
        self.id = id
        self.senderName = senderName
        self.senderClass = senderClass
        self.channel = channel
        self.text = text
        self.timestampMillis = timestampMillis
        self.hopCount = hopCount
        self.ttl = ttl
        self.originNodeId = originNodeId
        self.relayTrail = relayTrail
        self.isMine = isMine
        self.targetRecipient = targetRecipient
        self.isProbe = isProbe
        self.isProbeAck = isProbeAck
    }

    /// Custom Decodable initializer so packets from Android (kotlinx.serialization with encodeDefaults = false)
    /// decode cleanly even when default-valued fields are omitted from JSON.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        senderName = try c.decodeIfPresent(String.self, forKey: .senderName) ?? "Uczeń ZSME"
        senderClass = try c.decodeIfPresent(String.self, forKey: .senderClass) ?? ""
        channel = try c.decodeIfPresent(String.self, forKey: .channel) ?? "#ogólny"
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        timestampMillis = try c.decodeIfPresent(Int64.self, forKey: .timestampMillis) ?? Int64(Date().timeIntervalSince1970 * 1000)
        hopCount = try c.decodeIfPresent(Int.self, forKey: .hopCount) ?? 0
        ttl = try c.decodeIfPresent(Int.self, forKey: .ttl) ?? Self.defaultTTL
        originNodeId = try c.decodeIfPresent(String.self, forKey: .originNodeId) ?? ""
        relayTrail = try c.decodeIfPresent([String].self, forKey: .relayTrail) ?? []
        isMine = try c.decodeIfPresent(Bool.self, forKey: .isMine) ?? false
        targetRecipient = try c.decodeIfPresent(String.self, forKey: .targetRecipient) ?? ""
        isProbe = try c.decodeIfPresent(Bool.self, forKey: .isProbe) ?? false
        isProbeAck = try c.decodeIfPresent(Bool.self, forKey: .isProbeAck) ?? false
    }
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
/// bytes 2..5: 32-bit big-endian packet tag
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
        frames.reserveCapacity(totalChunks)
        for idx in 0..<totalChunks {
            let start = idx * maxSlice
            let end = min(start + maxSlice, raw.count)
            var frame = Data([magic0, magic1])
            frame.append(UInt8((tag >> 24) & 0xFF))
            frame.append(UInt8((tag >> 16) & 0xFF))
            frame.append(UInt8((tag >> 8) & 0xFF))
            frame.append(UInt8(tag & 0xFF))
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
                  data[data.startIndex] == magic0,
                  data[data.startIndex + 1] == magic1 else { return nil }

            let b2 = UInt32(data[data.startIndex + 2])
            let b3 = UInt32(data[data.startIndex + 3])
            let b4 = UInt32(data[data.startIndex + 4])
            let b5 = UInt32(data[data.startIndex + 5])
            let tag = (b2 << 24) | (b3 << 16) | (b4 << 8) | b5

            let chunkIdx = Int(data[data.startIndex + 6])
            let totalChunks = Int(data[data.startIndex + 7])
            guard totalChunks > 0, chunkIdx < totalChunks else { return nil }

            let key = "\(sourceKey):\(tag)"
            var partial = buffers[key] ?? PartialPacket(totalChunks: totalChunks)
            let payloadStart = data.startIndex + headerSize
            partial.chunks[chunkIdx] = Data(data[payloadStart..<data.endIndex])
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
    nonisolated static let androidManufacturerId: UInt16 = 0x5A53

    @Published private(set) var radioState: MeshRadioState = .idle
    @Published private(set) var peers: [MeshPeer] = []
    @Published private(set) var messages: [MeshMessage] = []
    @Published private(set) var stats = MeshStats()
    @Published private(set) var isRunning = false
    @Published private(set) var isScanningActive = false
    @Published private(set) var isAdvertisingActive = false

    let myNodeId = String(UUID().uuidString.prefix(8)).uppercased()
    private var myDisplayLabel = "Uczeń ZSME"

    private var centralManager: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    private var packetCharacteristic: CBMutableCharacteristic?
    private var serviceAdded = false

    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var peerLastSeen: [UUID: Date] = [:]
    private var activeCharacteristics: [UUID: CBCharacteristic] = [:]

    private struct OutgoingPacketTask {
        let messageId: String
        let frames: [Data]
        var nextFrameIndex: Int = 0
    }
    private var sendQueues: [UUID: [OutgoingPacketTask]] = [:]
    private var isWritingToPeer: Set<UUID> = []
    private var deliveredToPeer: [UUID: Set<String>] = [:]

    private var seenIds: Set<String> = []
    private var relayCache: [MeshMessage] = []
    private let assembler = MeshPacketChunker.FrameAssembler()
    private var maintenanceTask: Task<Void, Never>?

    func start(displayName: String) {
        myDisplayLabel = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Uczeń ZSME"
            : displayName.trimmingCharacters(in: .whitespacesAndNewlines)

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
            ensureServiceAndAdvertise()
        }
        startMaintenanceLoop()
    }

    func stop() {
        isRunning = false
        isScanningActive = false
        isAdvertisingActive = false
        maintenanceTask?.cancel()
        maintenanceTask = nil
        centralManager?.stopScan()
        for (_, peripheral) in discoveredPeripherals where peripheral.state != .disconnected {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        peripheralManager?.stopAdvertising()
        sendQueues.removeAll()
        isWritingToPeer.removeAll()
        activeCharacteristics.removeAll()
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
        var relayCopy = msg
        relayCopy.isMine = false
        relayCache.append(relayCopy)
        if relayCache.count > 80 { relayCache.removeFirst() }
        messages.append(msg)
        stats.sentCount += 1
        broadcastToNearbyPeers(relayCopy)
    }

    private func startMaintenanceLoop() {
        maintenanceTask?.cancel()
        maintenanceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self = self, self.isRunning else { break }
                self.performMaintenanceTick()
            }
        }
    }

    private func performMaintenanceTick() {
        let now = Date()
        let staleCutoff = now.addingTimeInterval(-45)
        let staleIds = peerLastSeen.filter { $0.value < staleCutoff }.map { $0.key }
        for uuid in staleIds {
            peerLastSeen.removeValue(forKey: uuid)
            if let p = discoveredPeripherals.removeValue(forKey: uuid), p.state != .disconnected {
                centralManager?.cancelPeripheralConnection(p)
            }
            activeCharacteristics.removeValue(forKey: uuid)
            sendQueues.removeValue(forKey: uuid)
            isWritingToPeer.remove(uuid)
            peers.removeAll { $0.deviceIdentifier == uuid.uuidString }
        }

        // Store-and-carry delivery for newly discovered or previously unreachable peers
        let msgCutoffMs = Int64(now.addingTimeInterval(-15 * 60).timeIntervalSince1970 * 1000)
        let recentPackets = relayCache.filter { $0.timestampMillis >= msgCutoffMs && $0.ttl > 0 }
        for (uuid, _) in discoveredPeripherals {
            let delivered = deliveredToPeer[uuid] ?? []
            let queuedIds = Set((sendQueues[uuid] ?? []).map(\.messageId))
            for pkt in recentPackets where !delivered.contains(pkt.id) && !queuedIds.contains(pkt.id) {
                enqueuePacket(pkt, to: uuid)
            }
        }
    }

    private func broadcastToNearbyPeers(_ message: MeshMessage, excluding sourcePeerUUID: UUID? = nil) {
        for uuid in discoveredPeripherals.keys where uuid != sourcePeerUUID {
            enqueuePacket(message, to: uuid)
        }
    }

    private func enqueuePacket(_ message: MeshMessage, to uuid: UUID) {
        guard isRunning, let peripheral = discoveredPeripherals[uuid] else { return }
        let frames = MeshPacketChunker.split(message)
        guard !frames.isEmpty else { return }

        var queue = sendQueues[uuid] ?? []
        if queue.contains(where: { $0.messageId == message.id }) { return }
        queue.append(OutgoingPacketTask(messageId: message.id, frames: frames))
        sendQueues[uuid] = queue

        driveSendQueue(for: peripheral)
    }

    private func driveSendQueue(for peripheral: CBPeripheral) {
        let uuid = peripheral.identifier
        guard !(sendQueues[uuid]?.isEmpty ?? true) else { return }
        guard !isWritingToPeer.contains(uuid) else { return }

        peripheral.delegate = self

        if peripheral.state != .connected {
            if peripheral.state != .connecting {
                centralManager?.connect(peripheral, options: nil)
            }
            return
        }

        guard let char = activeCharacteristics[uuid] else {
            peripheral.discoverServices([Self.meshServiceUUID])
            return
        }

        sendNextFrame(on: peripheral, characteristic: char)
    }

    private func sendNextFrame(on peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        let uuid = peripheral.identifier
        guard var queue = sendQueues[uuid], !queue.isEmpty else {
            isWritingToPeer.remove(uuid)
            return
        }

        let current = queue[0]
        if current.nextFrameIndex >= current.frames.count {
            deliveredToPeer[uuid, default: []].insert(current.messageId)
            queue.removeFirst()
            sendQueues[uuid] = queue
            if queue.isEmpty {
                isWritingToPeer.remove(uuid)
                // Disconnect cleanly after short delay so peer GATT server accepts future sessions cleanly
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard let self = self else { return }
                    if (self.sendQueues[uuid]?.isEmpty ?? true), peripheral.state == .connected {
                        self.centralManager?.cancelPeripheralConnection(peripheral)
                    }
                }
                return
            }
            sendNextFrame(on: peripheral, characteristic: characteristic)
            return
        }

        let frame = current.frames[current.nextFrameIndex]
        isWritingToPeer.insert(uuid)

        if characteristic.properties.contains(.write) {
            peripheral.writeValue(frame, for: characteristic, type: .withResponse)
        } else if characteristic.properties.contains(.writeWithoutResponse) {
            if peripheral.canSendWriteWithoutResponse {
                peripheral.writeValue(frame, for: characteristic, type: .withoutResponse)
                queue[0].nextFrameIndex += 1
                sendQueues[uuid] = queue
                isWritingToPeer.remove(uuid)
                sendNextFrame(on: peripheral, characteristic: characteristic)
            }
            // Otherwise CoreBluetooth invokes peripheralIsReady(toSendWriteWithoutResponse:)
        } else {
            queue.removeFirst()
            sendQueues[uuid] = queue
            isWritingToPeer.remove(uuid)
        }
    }

    private func beginScanning() {
        guard isRunning, centralManager?.state == .poweredOn else { return }
        centralManager?.scanForPeripherals(
            withServices: [Self.meshServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanningActive = true
        radioState = .active
    }

    private func ensureServiceAndAdvertise() {
        guard isRunning, peripheralManager?.state == .poweredOn else { return }
        if !serviceAdded {
            let char = CBMutableCharacteristic(
                type: Self.meshPacketCharUUID,
                properties: [.write, .writeWithoutResponse],
                value: nil,
                permissions: [.writeable]
            )
            let service = CBMutableService(type: Self.meshServiceUUID, primary: true)
            service.characteristics = [char]
            packetCharacteristic = char
            serviceAdded = true
            peripheralManager?.add(service)
            return
        }
        startAdvertisingNow()
    }

    private func startAdvertisingNow() {
        guard isRunning, peripheralManager?.state == .poweredOn else { return }
        peripheralManager?.stopAdvertising()
        let shortLabel = String(myDisplayLabel.prefix(12))
        peripheralManager?.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Self.meshServiceUUID],
            CBAdvertisementDataLocalNameKey: "ZSME-\(myNodeId.prefix(4))|\(shortLabel)"
        ])
    }

    private func handleDecodedMessage(_ msg: MeshMessage, fromPeer sourceKey: String) {
        guard msg.originNodeId != myNodeId, !seenIds.contains(msg.id) else { return }
        seenIds.insert(msg.id)

        let isDirect = !msg.targetRecipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let cleanTarget = msg.targetRecipient.trimmingCharacters(in: .whitespacesAndNewlines)
        let isForMe = !isDirect ||
            cleanTarget.caseInsensitiveCompare(myDisplayLabel) == .orderedSame ||
            cleanTarget.caseInsensitiveCompare(myNodeId) == .orderedSame

        if msg.isProbe {
            if isForMe {
                let ack = MeshMessage(
                    id: String(UUID().uuidString.prefix(12)),
                    senderName: myDisplayLabel,
                    senderClass: "",
                    channel: MeshMessage.directChannel,
                    text: "ACK",
                    timestampMillis: Int64(Date().timeIntervalSince1970 * 1000),
                    hopCount: 0,
                    ttl: MeshMessage.defaultTTL,
                    originNodeId: myNodeId,
                    relayTrail: [],
                    isMine: false,
                    targetRecipient: msg.senderName,
                    isProbe: false,
                    isProbeAck: true
                )
                seenIds.insert(ack.id)
                relayCache.append(ack)
                broadcastToNearbyPeers(ack)
            } else if msg.ttl > 1 {
                relayForward(msg)
            }
            return
        }

        if msg.isProbeAck {
            if !isForMe && msg.ttl > 1 {
                relayForward(msg)
            }
            return
        }

        if isForMe {
            stats.receivedCount += 1
            var display = msg
            display.isMine = false
            messages.append(display)
        }

        if msg.ttl > 1 && !(isDirect && isForMe) {
            relayForward(msg)
        }
        _ = sourceKey
    }

    private func relayForward(_ msg: MeshMessage) {
        var forward = msg
        forward.ttl -= 1
        forward.hopCount += 1
        forward.relayTrail = Array((msg.relayTrail + [myDisplayLabel]).suffix(6))
        forward.isMine = false
        relayCache.append(forward)
        if relayCache.count > 80 { relayCache.removeFirst() }
        stats.relayedCount += 1
        broadcastToNearbyPeers(forward)
    }

    nonisolated private static func parsePeerIdentity(advertisementData: [String: Any], peripheralName: String?, fallbackId: String) -> (nodeId: String, displayName: String) {
        if let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data, mfg.count >= 3 {
            let companyId = UInt16(mfg[mfg.startIndex]) | (UInt16(mfg[mfg.startIndex + 1]) << 8)
            if companyId == androidManufacturerId {
                let payload = mfg.subdata(in: (mfg.startIndex + 2)..<mfg.endIndex)
                if let text = String(data: payload, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    let parts = text.split(separator: "|", maxSplits: 1).map(String.init)
                    if parts.count == 2 {
                        let nid = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                        let lbl = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                        return (nid.isEmpty ? fallbackId : nid, lbl.isEmpty ? "ZSME-\(nid)" : lbl)
                    }
                    return (String(text.prefix(4)).uppercased(), text)
                }
            }
        }

        let rawName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheralName ?? ""
        if rawName.hasPrefix("ZSME-"), let sep = rawName.firstIndex(of: "|") {
            let prefixPart = String(rawName[..<sep]).replacingOccurrences(of: "ZSME-", with: "")
            let labelPart = String(rawName[rawName.index(after: sep)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (prefixPart.isEmpty ? fallbackId : prefixPart, labelPart.isEmpty ? rawName : labelPart)
        }
        let cleanName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        return (fallbackId, cleanName.isEmpty ? "Uczeń ZSME" : cleanName)
    }
}

extension BleMeshManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                if self.isRunning { self.beginScanning() }
            case .poweredOff:
                self.isScanningActive = false
                self.radioState = .poweredOff
            case .unauthorized:
                self.isScanningActive = false
                self.radioState = .unauthorized
            case .unsupported:
                self.isScanningActive = false
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
        let fallbackNode = String(peripheral.identifier.uuidString.prefix(4)).uppercased()
        let identity = Self.parsePeerIdentity(advertisementData: advertisementData, peripheralName: peripheral.name, fallbackId: fallbackNode)
        let rssiVal = RSSI.intValue
        Task { @MainActor in
            self.discoveredPeripherals[peripheral.identifier] = peripheral
            self.peerLastSeen[peripheral.identifier] = Date()
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let peer = MeshPeer(
                deviceIdentifier: peripheral.identifier.uuidString,
                nodeId: identity.nodeId,
                displayName: identity.displayName,
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
        Task { @MainActor in
            peripheral.delegate = self
            peripheral.discoverServices([BleMeshManager.meshServiceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            let uuid = peripheral.identifier
            self.isWritingToPeer.remove(uuid)
            self.activeCharacteristics.removeValue(forKey: uuid)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            let uuid = peripheral.identifier
            self.isWritingToPeer.remove(uuid)
            self.activeCharacteristics.removeValue(forKey: uuid)
            if self.isRunning, !(self.sendQueues[uuid]?.isEmpty ?? true) {
                self.driveSendQueue(for: peripheral)
            }
        }
    }
}

extension BleMeshManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else {
            Task { @MainActor in
                self.isWritingToPeer.remove(peripheral.identifier)
            }
            return
        }
        for service in services where service.uuid == BleMeshManager.meshServiceUUID {
            peripheral.discoverCharacteristics([BleMeshManager.meshPacketCharUUID], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let chars = service.characteristics else {
            Task { @MainActor in
                self.isWritingToPeer.remove(peripheral.identifier)
            }
            return
        }
        for char in chars where char.uuid == BleMeshManager.meshPacketCharUUID {
            Task { @MainActor in
                self.activeCharacteristics[peripheral.identifier] = char
                self.sendNextFrame(on: peripheral, characteristic: char)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == BleMeshManager.meshPacketCharUUID else { return }
        Task { @MainActor in
            let uuid = peripheral.identifier
            guard var queue = self.sendQueues[uuid], !queue.isEmpty else {
                self.isWritingToPeer.remove(uuid)
                return
            }
            if let _ = error {
                // Drop failed packet attempt and allow maintenance loop to retry
                queue.removeFirst()
                self.sendQueues[uuid] = queue
                self.isWritingToPeer.remove(uuid)
                self.centralManager?.cancelPeripheralConnection(peripheral)
                return
            }
            queue[0].nextFrameIndex += 1
            self.sendQueues[uuid] = queue
            self.sendNextFrame(on: peripheral, characteristic: characteristic)
        }
    }

    nonisolated func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        Task { @MainActor in
            guard let char = self.activeCharacteristics[peripheral.identifier] else { return }
            self.sendNextFrame(on: peripheral, characteristic: char)
        }
    }
}

extension BleMeshManager: CBPeripheralManagerDelegate {
    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        Task { @MainActor in
            switch peripheral.state {
            case .poweredOn:
                if self.isRunning { self.ensureServiceAndAdvertise() }
            case .poweredOff:
                self.isAdvertisingActive = false
            case .unauthorized:
                self.isAdvertisingActive = false
                self.radioState = .unauthorized
            default:
                break
            }
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        Task { @MainActor in
            if error == nil && self.isRunning {
                self.startAdvertisingNow()
            } else if error != nil {
                self.serviceAdded = false
                self.isAdvertisingActive = false
            }
        }
    }

    nonisolated func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        Task { @MainActor in
            self.isAdvertisingActive = (error == nil)
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        // Respond strictly once per callback batch per Apple CoreBluetooth guidelines
        if let first = requests.first {
            peripheral.respond(to: first, withResult: .success)
        }

        let frames: [(sourceKey: String, data: Data)] = requests.compactMap { req in
            guard req.characteristic.uuid == BleMeshManager.meshPacketCharUUID,
                  let value = req.value else { return nil }
            return (req.central.identifier.uuidString, value)
        }
        guard !frames.isEmpty else { return }

        Task { @MainActor in
            for (sourceKey, data) in frames {
                if let decoded = self.assembler.acceptFrame(sourceKey: sourceKey, data: data) {
                    self.handleDecodedMessage(decoded, fromPeer: sourceKey)
                }
            }
        }
    }
}
