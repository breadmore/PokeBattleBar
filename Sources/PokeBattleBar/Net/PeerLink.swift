import Foundation
import Network

/// 한 상대와의 TCP 연결. 프레이밍을 처리하고 Wire 메시지를 스트림으로 흘린다.
final class PeerLink: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "poke.peerlink")
    private var buffer = Data()

    private var messageHandler: (@Sendable (Wire) -> Void)?
    private var stateHandler: (@Sendable (NWConnection.State) -> Void)?
    /// 수신 루프가 이미 돌고 있는가.
    ///
    /// `.ready` 는 **다시 올 수 있다** — 경로가 바뀌거나 잠시 끊겼다 복구되면
    /// `.ready → .waiting → .ready` 로 돌아온다. 그때마다 루프를 새로 걸면
    /// 같은 버퍼를 두 루프가 나눠 먹어서 메시지가 중복 전달되거나 순서가 뒤바뀐다.
    /// (연결 큐가 직렬이므로 이 플래그도 그 큐에서만 만진다.)
    private var receiving = false

    // MARK: 중계 핸드셰이크
    //
    // 중계 서버를 거칠 때는 게임 스트림 **앞에** 핸드셰이크가 붙는다.
    // 이 단계를 PeerLink 안에서 처리하는 이유는 버퍼가 하나이기 때문이다 —
    // 밖에서 소켓을 먼저 읽고 나중에 PeerLink 에 넘기면, 핸드셰이크 응답과
    // 같은 패킷에 실려 온 게임 바이트가 그대로 사라진다.

    /// 아직 핸드셰이크 응답을 기다리는 중인가 (nil 이면 평범한 직접 연결)
    private var pendingHello: RelayHello?
    /// 방이 등록됐을 때 (호스트만). 짝이 맞기 전이다.
    private var onRelayRegistered: (@Sendable () -> Void)?
    /// 짝이 맞았다 — 이 뒤로는 평범한 게임 연결이다. (상대 이름)
    private var onRelayPaired: (@Sendable (String?) -> Void)?
    /// 중계기가 거절했다
    private var onRelayRejected: (@Sendable (String) -> Void)?
    /// 로비 연결에서 온 프레임 (스냅샷·초대·거절).
    ///
    /// 이 연결은 짝 맞춤이 없어서 **핸드셰이크가 끝나지 않는다** — 같은 형식의
    /// 프레임이 계속 흘러오므로 Wire 로 넘기지 않고 여기서 계속 받는다.
    /// 종류를 나누지 않고 프레임째로 올린다 — 판단은 RelayLobby 가 한다.
    private var onRelayLobby: (@Sendable (RelayServerFrame) -> Void)?
    /// 로비 연결인가 (게임 스트림으로 넘어가지 않는다)
    private var isLobbyLink = false
    /// 프레임 해석 실패 (특히 프로토콜 버전 불일치) 를 위로 올린다.
    /// 이걸 안 하면 그냥 연결이 끊겨서 사용자는 이유를 알 수 없다.
    var onProtocolError: (@Sendable (String) -> Void)?

    var endpointDescription: String { "\(connection.endpoint)" }

    /// 아직 살아 있는 연결인가.
    /// 좀비 링크(상대가 앱을 강제 종료했는데 TCP 가 아직 안 끊긴 상태)를
    /// 붙잡고 있으면 방이 영구히 막히므로 판별할 수단이 필요하다.
    var isAlive: Bool {
        switch connection.state {
        case .failed, .cancelled: return false
        default: return true
        }
    }

    init(connection: NWConnection) {
        self.connection = connection
    }

    convenience init(to endpoint: NWEndpoint) {
        self.init(connection: NWConnection(to: endpoint, using: PeerLink.params))
    }

    static var params: NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10
        tcp.noDelay = true
        let p = NWParameters(tls: nil, tcp: tcp)
        p.includePeerToPeer = true          // 같은 LAN / AWDL 허용
        return p
    }

    func start(onMessage: @escaping @Sendable (Wire) -> Void,
               onState: @escaping @Sendable (NWConnection.State) -> Void) {
        messageHandler = onMessage
        stateHandler = onState
        connection.stateUpdateHandler = { [weak self] st in
            self?.stateHandler?(st)
            if st == .ready { self?.startReceivingIfNeeded() }
        }
        connection.start(queue: queue)
    }

    /// `then` 은 데이터가 실제로 소켓에 넘어간 뒤 호출된다.
    /// 보낸 직후 cancel() 하면 플러시 전에 끊겨 상대가 못 받으므로, 그럴 때는 반드시 `then` 을 쓴다.
    func send(_ w: Wire, then: (@Sendable () -> Void)? = nil) {
        do {
            let data = try WireCodec.encode(w)
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { NSLog("PokeBattleBar: 전송 실패 \(error)") }
                then?()
            })
        } catch {
            NSLog("PokeBattleBar: 전송 인코딩 실패 \(error)")
            then?()
        }
    }

    /// 중계 서버를 거쳐 시작한다.
    ///
    /// 연결되면 먼저 `hello` 를 보내고, 중계기가 짝을 맞춰줄 때까지 기다린다.
    /// 짝이 맞은 뒤로는 직접 연결과 **완전히 같다** — 그래서 그 시점에
    /// `onPaired` 를 받은 쪽이 평소 경로(joinAccepted·battleBegan …)를 그대로 탄다.
    func startRelay(hello: RelayHello,
                    onRegistered: @escaping @Sendable () -> Void,
                    onPaired: @escaping @Sendable (String?) -> Void,
                    onRejected: @escaping @Sendable (String) -> Void,
                    onMessage: @escaping @Sendable (Wire) -> Void,
                    onState: @escaping @Sendable (NWConnection.State) -> Void) {
        pendingHello = hello
        onRelayRegistered = onRegistered
        onRelayPaired = onPaired
        onRelayRejected = onRejected
        messageHandler = onMessage
        stateHandler = onState
        connection.stateUpdateHandler = { [weak self] st in
            self?.stateHandler?(st)
            guard st == .ready, let self else { return }
            self.sendHelloIfNeeded()
            self.startReceivingIfNeeded()
        }
        connection.start(queue: queue)
    }

    /// 중계 로비 연결을 시작한다.
    ///
    /// 배틀 연결과 달리 **끝까지 중계기와 이야기한다** — 짝을 맞추는 것이 아니라
    /// "누가 있는지" 를 계속 받는 것이 목적이다. 그래서 Wire 로 넘어가지 않는다.
    func startRelay(hello: RelayHello,
                    onRegistered: @escaping @Sendable () -> Void,
                    onPaired: @escaping @Sendable (String?) -> Void,
                    onRejected: @escaping @Sendable (String) -> Void,
                    onLobby: @escaping @Sendable (RelayServerFrame) -> Void,
                    onState: @escaping @Sendable (NWConnection.State) -> Void) {
        isLobbyLink = true
        onRelayLobby = onLobby
        startRelay(hello: hello, onRegistered: onRegistered, onPaired: onPaired,
                   onRejected: onRejected, onMessage: { _ in }, onState: onState)
    }

    /// 로비 연결로 프레임 하나를 보낸다 (상태 알림·핑)
    func sendRelay(_ frame: RelayClientFrame) {
        do {
            let data = try RelayCodec.encode(frame)
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { NSLog("PokeBattleBar: 중계 로비 전송 실패 \(error)") }
            })
        } catch {
            NSLog("PokeBattleBar: 중계 로비 인코딩 실패 \(error)")
        }
    }

    private func sendHelloIfNeeded() {
        guard let hello = pendingHello else { return }
        do {
            let data = try RelayCodec.encode(hello)
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { NSLog("PokeBattleBar: 중계 인사 전송 실패 \(error)") }
            })
        } catch {
            NSLog("PokeBattleBar: 중계 인사 인코딩 실패 \(error)")
        }
    }

    /// 버퍼 앞쪽의 핸드셰이크 프레임을 소화한다.
    /// 핸드셰이크가 끝나면 true 를 돌려주고, 남은 바이트는 게임 스트림으로 넘어간다.
    /// - Returns: 계속 진행해도 되는가 (false 면 연결이 끊겼다)
    private func consumeHandshake() throws -> Bool {
        while pendingHello != nil {
            // 로비 연결은 스냅샷도 같은 스트림으로 오므로 함께 해석한다
            guard let frame = try RelayCodec.decode(RelayServerFrame.self, from: &buffer) else {
                return true             // 아직 다 안 왔다 — 더 기다린다
            }
            if frame.isRejection {
                let why = frame.reason ?? "알 수 없는 이유"
                pendingHello = nil
                onRelayRejected?(why)
                return false
            }
            if frame.isLobbyEvent {
                onRelayLobby?(frame)
                continue                // 로비 연결은 계속 여기서 받는다
            }
            if frame.isRegistered {
                onRelayRegistered?()
                continue                // 호스트는 짝 맞춤을, 로비는 스냅샷을 더 기다린다
            }
            if frame.isPaired {
                // 이 뒤로는 평범한 게임 연결이다
                pendingHello = nil
                onRelayPaired?(frame.peer)
            }
        }
        return true
    }

    func cancel() {
        connection.cancel()
    }

    private func startReceivingIfNeeded() {
        guard !receiving else { return }
        receiving = true
        receiveLoop()
    }

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                do {
                    // 중계 핸드셰이크가 남아 있으면 **그것부터** 소화한다.
                    // 같은 버퍼를 쓰므로, 응답과 한 패킷에 실려 온 게임 바이트도
                    // 그대로 이어서 처리된다.
                    guard try self.consumeHandshake() else {
                        self.receiving = false
                        self.connection.cancel()
                        return
                    }
                    if self.pendingHello == nil {
                        for msg in try WireCodec.drain(&self.buffer) {
                            self.messageHandler?(msg)
                        }
                    }
                } catch {
                    let msg = (error as? WireError)?.errorDescription
                        ?? "통신 형식을 해석할 수 없습니다: \(error.localizedDescription)"
                    NSLog("PokeBattleBar: 프레임 해석 실패 — \(msg)")
                    self.receiving = false
                    self.onProtocolError?(msg)
                    self.connection.cancel()
                    return
                }
            }
            if isComplete || error != nil {
                self.receiving = false
                self.connection.cancel()
                return
            }
            self.receiveLoop()
        }
    }
}
