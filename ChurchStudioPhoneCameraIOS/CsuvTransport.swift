import Foundation
import Network

protocol CsuvTransportDelegate: AnyObject {
    func transportDidBecomeVideoReady(_ transport: CsuvTransport)
    func transportDidDisconnect(_ transport: CsuvTransport)
    func transport(_ transport: CsuvTransport, didChangeStatus text: String)
}

/// USB-facing transport for iPhone. The iOS app listens on TCP 39877; on Windows,
/// usbmux/iproxy forwards localhost:39877 to this device port over the USB cable.
/// The control handshake and CSUV framing intentionally match Android V3.8.7.
final class CsuvTransport {
    weak var delegate: CsuvTransportDelegate?

    private let port: NWEndpoint.Port = 39877
    private let stateQueue = DispatchQueue(label: "ChurchStudio.iOS.transport.state")
    private let writerQueue = DispatchQueue(label: "ChurchStudio.iOS.transport.writer")
    private var listener: NWListener?
    private var connection: NWConnection?
    private var receiveBuffer = Data()

    private struct PendingPacket {
        let type: CsuvPacketType
        let flags: UInt16
        let ptsUs: UInt64
        let payload: Data
        let isVideo: Bool
    }

    private var sequence: UInt32 = 0
    private var priorityPackets: [PendingPacket] = []
    private var latestVideo: PendingPacket?
    private var rawControls: [Data] = []
    private var writeInFlight = false
    private var awaitFreshKeyframe = false
    private(set) var videoDrops: UInt64 = 0
    private(set) var lastQueueWaitUs: UInt64 = 0
    private(set) var lastWriteUs: UInt64 = 0
    private var videoQueuedAtNs: UInt64 = 0

    func start() {
        stateQueue.async { [weak self] in self?.startLocked() }
    }

    func stop() {
        stateQueue.async { [weak self] in
            guard let self else { return }
            self.listener?.cancel()
            self.listener = nil
            self.replaceConnection(nil)
        }
    }

    private func startLocked() {
        guard listener == nil else { return }
        do {
            let listener = try NWListener(using: .tcp, on: port)
            self.listener = listener
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.status("USB/TCP 대기 중 :39877")
                case .failed(let error):
                    self.status("listener 실패: \(error)")
                    self.listener = nil
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] newConnection in
                self?.stateQueue.async { self?.accept(newConnection) }
            }
            listener.start(queue: stateQueue)
        } catch {
            status("listener 생성 실패: \(error)")
        }
    }

    private func accept(_ newConnection: NWConnection) {
        // One ChurchStudio host at a time. A new validated USB tunnel replaces the old one.
        replaceConnection(newConnection)
        receiveBuffer.removeAll(keepingCapacity: true)
        sequence = 0
        writerQueue.async { [weak self] in
            self?.priorityPackets.removeAll()
            self?.latestVideo = nil
            self?.rawControls.removeAll()
            self?.pendingRawCompletions.removeAll()
            self?.writeInFlight = false
            self?.awaitFreshKeyframe = false
        }
        newConnection.stateUpdateHandler = { [weak self, weak newConnection] state in
            guard let self, let conn = newConnection else { return }
            self.stateQueue.async {
                guard self.connection === conn else { return }
                switch state {
                case .ready:
                    self.status("Windows USB tunnel 연결됨; HELO 대기")
                    self.receiveNext(on: conn)
                case .failed(let error):
                    self.status("USB tunnel 실패: \(error)")
                    self.replaceConnection(nil)
                case .cancelled:
                    self.replaceConnection(nil)
                default:
                    break
                }
            }
        }
        newConnection.start(queue: stateQueue)
    }

    private func replaceConnection(_ newValue: NWConnection?) {
        if let old = connection, old !== newValue { old.cancel() }
        let hadConnection = connection != nil
        connection = newValue
        if newValue == nil && hadConnection {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.transportDidDisconnect(self)
            }
            status("USB tunnel 연결 종료")
        }
    }

    private func receiveNext(on conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak conn] content, _, isComplete, error in
            guard let self, let conn else { return }
            self.stateQueue.async {
                guard self.connection === conn else { return }
                if let content, !content.isEmpty {
                    self.receiveBuffer.append(content)
                    self.consumeControlMessages()
                }
                if let error {
                    self.status("USB tunnel read 실패: \(error)")
                    self.replaceConnection(nil)
                    return
                }
                if isComplete {
                    self.replaceConnection(nil)
                    return
                }
                self.receiveNext(on: conn)
            }
        }
    }

    private func consumeControlMessages() {
        while receiveBuffer.count >= 4 {
            let prefixData = receiveBuffer.prefix(4)
            guard let prefix = String(data: prefixData, encoding: .ascii) else {
                failProtocol("ASCII prefix 오류")
                return
            }
            switch prefix {
            case "HELO":
                receiveBuffer.removeFirst(4)
                sendRawControl(Data("HACK".utf8))
            case "PING":
                guard receiveBuffer.count >= 12 else { return }
                let nonce = receiveBuffer.subdata(in: 4..<12)
                receiveBuffer.removeFirst(12)
                var pong = Data("PONG".utf8)
                pong.append(nonce)
                sendRawControl(pong) { [weak self] ok in
                    guard let self, ok else { return }
                    self.status("handshake PASS; video mode ready")
                    DispatchQueue.main.async {
                        self.delegate?.transportDidBecomeVideoReady(self)
                    }
                }
            default:
                failProtocol("unknown prefix \(prefixData.map { String(format: "%02X", $0) }.joined())")
                return
            }
        }
    }

    private func failProtocol(_ text: String) {
        status("protocol 오류: \(text)")
        replaceConnection(nil)
    }

    func sendConfig(ptsUs: UInt64 = 0, annexB: Data) -> Bool {
        submit(type: .config, flags: 0, ptsUs: ptsUs, payload: annexB, priority: true)
    }

    func sendStatus(_ text: String) -> Bool {
        submit(type: .status, flags: 0, ptsUs: 0, payload: Data(text.utf8), priority: true)
    }

    @discardableResult
    func sendVideo(ptsUs: UInt64, keyframe: Bool, annexB: Data) -> Bool {
        submit(type: .video, flags: keyframe ? CsuvProtocol.keyframeFlag : 0, ptsUs: ptsUs, payload: annexB, priority: false)
    }

    private func submit(type: CsuvPacketType, flags: UInt16, ptsUs: UInt64, payload: Data, priority: Bool) -> Bool {
        guard payload.count <= CsuvProtocol.maxPayload else { return false }
        guard connection != nil else { return false }
        let packet = PendingPacket(type: type, flags: flags, ptsUs: ptsUs, payload: payload, isVideo: type == .video)
        writerQueue.async { [weak self] in
            guard let self else { return }
            if priority {
                self.priorityPackets.append(packet)
            } else {
                let isKey = (flags & CsuvProtocol.keyframeFlag) != 0
                if self.awaitFreshKeyframe {
                    if !isKey {
                        self.videoDrops += 1
                        return
                    }
                    if self.latestVideo != nil { self.videoDrops += 1 }
                    self.latestVideo = nil
                    self.awaitFreshKeyframe = false
                } else if self.latestVideo != nil {
                    // Android V3.8.7 MAX_VIDEO_QUEUE=1 semantics: preserve only the freshest frame.
                    self.videoDrops += 1
                    if !isKey {
                        self.latestVideo = nil
                        self.awaitFreshKeyframe = true
                        return
                    }
                }
                if isKey, self.latestVideo != nil {
                    self.videoDrops += 1
                    self.latestVideo = nil
                }
                self.latestVideo = packet
                self.videoQueuedAtNs = DispatchTime.now().uptimeNanoseconds
            }
            self.pumpWriter()
        }
        return true
    }

    private func sendRawControl(_ data: Data, completion: ((Bool) -> Void)? = nil) {
        writerQueue.async { [weak self] in
            guard let self else { completion?(false); return }
            self.rawControls.append(data)
            self.pumpWriter(rawCompletion: completion)
        }
    }

    private var pendingRawCompletions: [((Bool) -> Void)?] = []

    private func pumpWriter(rawCompletion: ((Bool) -> Void)? = nil) {
        if let rawCompletion { pendingRawCompletions.append(rawCompletion) }
        guard !writeInFlight else { return }
        guard let conn = connection else { return }

        enum Item {
            case raw(Data, ((Bool) -> Void)?)
            case packet(PendingPacket, UInt64)
        }

        let item: Item?
        if !rawControls.isEmpty {
            let raw = rawControls.removeFirst()
            let completion = pendingRawCompletions.isEmpty ? nil : pendingRawCompletions.removeFirst()
            item = .raw(raw, completion)
        } else if !priorityPackets.isEmpty {
            item = .packet(priorityPackets.removeFirst(), DispatchTime.now().uptimeNanoseconds)
        } else if let video = latestVideo {
            latestVideo = nil
            item = .packet(video, videoQueuedAtNs)
        } else {
            item = nil
        }
        guard let item else { return }
        writeInFlight = true
        let writeStart = DispatchTime.now().uptimeNanoseconds

        let data: Data
        var rawCompletionBlock: ((Bool) -> Void)?
        var isVideo = false
        var queuedAt = writeStart
        switch item {
        case .raw(let raw, let completion):
            data = raw
            rawCompletionBlock = completion
        case .packet(let packet, let queued):
            let seq = sequence
            sequence &+= 1
            data = CsuvProtocol.packet(type: packet.type, flags: packet.flags, sequence: seq, ptsUs: packet.ptsUs, payload: packet.payload)
            isVideo = packet.isVideo
            queuedAt = queued
        }

        conn.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            self.writerQueue.async {
                let end = DispatchTime.now().uptimeNanoseconds
                let ok = error == nil
                if isVideo {
                    self.lastQueueWaitUs = (writeStart &- queuedAt) / 1_000
                    self.lastWriteUs = (end &- writeStart) / 1_000
                }
                rawCompletionBlock?(ok)
                self.writeInFlight = false
                if let error {
                    self.status("USB tunnel write 실패: \(error)")
                    self.stateQueue.async { self.replaceConnection(nil) }
                    return
                }
                self.pumpWriter()
            }
        })
    }

    private func status(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.transport(self, didChangeStatus: text)
        }
    }
}
