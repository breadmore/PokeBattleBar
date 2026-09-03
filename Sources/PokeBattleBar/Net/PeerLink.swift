import Foundation
import Network

/// 한 상대와의 TCP 연결. 프레이밍을 처리하고 Wire 메시지를 스트림으로 흘린다.
final class PeerLink: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "poke.peerlink")
    private var buffer = Data()

    private var messageHandler: (@Sendable (Wire) -> Void)?
    private var stateHandler: (@Sendable (NWConnection.State) -> Void)?
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
            if st == .ready { self?.receiveLoop() }
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

    func cancel() {
        connection.cancel()
    }

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                do {
                    for msg in try WireCodec.drain(&self.buffer) {
                        self.messageHandler?(msg)
                    }
                } catch {
                    let msg = (error as? WireError)?.errorDescription
                        ?? "통신 형식을 해석할 수 없습니다: \(error.localizedDescription)"
                    NSLog("PokeBattleBar: 프레임 해석 실패 — \(msg)")
                    self.onProtocolError?(msg)
                    self.connection.cancel()
                    return
                }
            }
            if isComplete || error != nil {
                self.connection.cancel()
                return
            }
            self.receiveLoop()
        }
    }
}
