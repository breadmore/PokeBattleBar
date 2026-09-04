import Foundation
import Network

/// 중계 서버 로비에 상주하는 연결.
///
/// `LobbyPresence`(Bonjour) 와 **같은 역할, 다른 경로**다:
///  - `LobbyPresence` — 같은 네트워크. mDNS 로 광고하고 찾는다. 초대를 주고받는다.
///  - `RelayLobby`    — 중계 서버. TCP 한 줄을 붙여두고 목록을 받는다. 방 코드로 들어간다.
///
/// 두 목록을 **섞지 않는다.** 출처가 다르고 할 수 있는 것도 달라서, 한 칸에 합치면
/// "이 사람에게 초대를 보낼 수 있나?" 를 화면에서 판단할 수 없게 된다.
///
/// 배틀 연결(`role: host/guest`)과도 별개의 연결이다 — 배틀 연결은 짝이 맞는 순간
/// 중계기가 바이트만 흘리는 파이프로 바꿔버리므로 그 위에 로비를 얹을 수 없다.
final class RelayLobby: @unchecked Sendable {
    private let lock = NSLock()
    private var link: PeerLink?
    private var _connected = false
    private var stopped = true

    /// 지금 붙어 있는 중계 서버 (재접속에 쓴다)
    private var endpoint: NWEndpoint?
    private var displayName = ""
    private var secret: String?
    private var lastStatus: PeerStatus = .free
    private var lastRoom: String?

    private let queue = DispatchQueue(label: "poke.relaylobby")
    private var reconnectGeneration = 0
    private var pingGeneration = 0

    var isConnected: Bool {
        lock.lock(); defer { lock.unlock() }
        return _connected
    }

    /// 로비 상황이 갱신됐다
    var onSnapshot: (@Sendable (RelayLobbySnapshot) -> Void)?
    /// 붙었다 / 끊겼다 (화면에 "중계 로비 접속 중" 을 보여주기 위해)
    var onConnectedChanged: (@Sendable (Bool) -> Void)?
    /// 중계기가 거절했다 (암호 불일치 등) — 재접속하지 않는다
    var onRejected: (@Sendable (String) -> Void)?
    /// 초대를 받았다 (보낸 사람, 방 코드)
    var onInvite: (@Sendable (String, String) -> Void)?
    /// 내가 보낸 초대를 상대가 거절했다
    var onDeclined: (@Sendable (String) -> Void)?
    /// 초대를 전달하지 못했다 (상대가 나갔거나 방이 없다)
    var onInviteFailed: (@Sendable (String, String) -> Void)?
    var onError: (@Sendable (String) -> Void)?

    // MARK: 접속

    func start(server: NWEndpoint, displayName: String, secret: String?) {
        stop()
        lock.lock()
        stopped = false
        endpoint = server
        self.displayName = displayName
        self.secret = secret
        lock.unlock()
        dial()
    }

    private func dial() {
        lock.lock()
        let go = !stopped
        let server = endpoint
        let name = displayName
        let secret = self.secret
        lock.unlock()
        guard go, let server else { return }

        let link = PeerLink(to: server)
        setLink(link)
        link.startRelay(
            hello: RelayHello(role: .lobby, room: "", name: name, secret: secret),
            onRegistered: { [weak self] in
                guard let self, self.isCurrentLink(link) else { return }
                self.setConnected(true)
                // 붙자마자 지금 상태를 알려준다 (배틀 중이면 초대 대상이 아니다)
                self.pushStatus()
                self.schedulePing()
            },
            onPaired: { _ in },        // 로비 연결에는 짝 맞춤이 없다
            onRejected: { [weak self] why in
                guard let self else { return }
                self.setConnected(false)
                self.setLink(nil)
                self.lock.lock(); self.stopped = true; self.lock.unlock()   // 재접속 금지
                self.onRejected?(why)
            },
            onLobby: { [weak self] frame in
                guard let self, self.isCurrentLink(link) else { return }
                switch frame.type {
                case "lobby":
                    self.onSnapshot?(frame.snapshot)
                case "invite":
                    if let from = frame.peer, let room = frame.room {
                        self.onInvite?(from, room)
                    }
                case "declined":
                    if let who = frame.peer { self.onDeclined?(who) }
                case "invitefailed":
                    self.onInviteFailed?(frame.peer ?? "상대",
                                         frame.reason ?? "전달하지 못했습니다")
                default:
                    break
                }
            },
            onState: { [weak self] st in
                guard let self, self.isCurrentLink(link) else { return }
                switch st {
                case .failed(let e):
                    self.setConnected(false)
                    self.onError?("중계 로비 연결 실패: \(e.localizedDescription)")
                    self.scheduleReconnect()
                case .cancelled:
                    self.setConnected(false)
                    self.scheduleReconnect()
                default: break
                }
            }
        )
    }

    /// 중계기가 죽었다 살아나거나 네트워크가 끊겼다 붙을 수 있다.
    /// 로비는 상주가 목적이므로 조용히 다시 붙는다.
    private func scheduleReconnect() {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        reconnectGeneration += 1
        let gen = reconnectGeneration
        lock.unlock()
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let ok = !self.stopped && gen == self.reconnectGeneration
            self.lock.unlock()
            guard ok else { return }
            self.dial()
        }
    }

    /// 오래 조용하면 중간 장비가 연결을 끊는다. 주기적으로 한 줄 보낸다.
    private func schedulePing() {
        lock.lock()
        pingGeneration += 1
        let gen = pingGeneration
        lock.unlock()
        queue.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let ok = !self.stopped && gen == self.pingGeneration && self._connected
            let link = self.link
            self.lock.unlock()
            guard ok, let link else { return }
            link.sendRelay(.ping)
            self.schedulePing()
        }
    }

    func stop() {
        lock.lock()
        stopped = true
        reconnectGeneration += 1
        pingGeneration += 1
        let l = link
        link = nil
        let wasConnected = _connected
        _connected = false
        endpoint = nil
        lock.unlock()
        l?.cancel()
        if wasConnected { onConnectedChanged?(false) }
    }

    // MARK: 상태 알리기

    /// 내 상태를 중계 로비에 반영한다 (로비 / 방 열림 / 배틀 중).
    func update(status: PeerStatus, room: String?) {
        lock.lock()
        let changed = status != lastStatus || room != lastRoom
        lastStatus = status
        lastRoom = room
        lock.unlock()
        guard changed else { return }
        pushStatus()
    }

    // MARK: 초대
    //
    // 중계기는 메시지를 옮기기만 한다 — 수락 여부는 두 앱이 정한다.
    // 수락하면 방 코드로 들어가면 되므로 별도의 "수락" 메시지가 필요 없다.

    /// 중계 로비의 상대를 내 방으로 부른다. 방을 먼저 열어야 한다.
    func sendInvite(to peer: String, room: String) {
        guard let link = currentLink else { return }
        link.sendRelay(.invite(to: peer, room: room))
    }

    /// 초대를 거절한다고 알린다 (상대가 계속 기다리지 않게)
    func decline(to peer: String) {
        guard let link = currentLink else { return }
        link.sendRelay(.decline(to: peer))
    }

    private var currentLink: PeerLink? {
        lock.lock(); defer { lock.unlock() }
        return _connected ? link : nil
    }

    private func pushStatus() {
        lock.lock()
        let link = self.link
        let status = lastStatus
        let room = lastRoom
        let connected = _connected
        lock.unlock()
        guard connected, let link else { return }
        link.sendRelay(.status(status, room: room))
    }

    // MARK: 내부

    private func setLink(_ l: PeerLink?) {
        lock.lock(); link = l; lock.unlock()
    }

    private func isCurrentLink(_ l: PeerLink) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return link === l
    }

    private func setConnected(_ on: Bool) {
        lock.lock()
        let changed = _connected != on
        _connected = on
        lock.unlock()
        if changed { onConnectedChanged?(on) }
    }
}
