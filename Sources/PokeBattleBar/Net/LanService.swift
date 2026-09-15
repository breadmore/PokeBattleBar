import Foundation
import Network

let pokeBattleServiceType = "_pokebattle._tcp"

/// 브라우저가 찾아낸 방 하나.
struct DiscoveredRoom: Identifiable, Sendable {
    var id: String { name }
    var name: String
    var hostName: String
    var teamCap: Int
    var level: Int
    var occupied: Bool
    var endpoint: NWEndpoint
    /// 방장의 프로토콜 버전. 다르면 접속해도 통신이 안 되므로 목록에서 미리 막는다.
    var protocolVersion: Int
    /// 게임 모드 요약 (목록에 표시)
    var mode: String = "일반"

    var compatible: Bool { protocolVersion == PokeBattleProtocol.version }
    var versionNote: String? {
        guard !compatible else { return nil }
        return protocolVersion > PokeBattleProtocol.version ? "내 앱이 구버전" : "상대가 구버전"
    }
}

/// 방을 광고하고 게스트 한 명을 받는다.
final class RoomHost: @unchecked Sendable {
    /// 다른 네트워크에서 붙을 때 안내할 기본 포트.
    /// 포트포워딩을 걸거나 방화벽을 열 때 이 번호 하나만 알면 된다.
    static let preferredPort: UInt16 = 51234

    /// 실제로 열린 포트 (고정 포트가 이미 쓰이면 다른 번호가 된다)
    var listeningPort: UInt16? {
        currentListener?.port?.rawValue
    }

    /// 리스너는 **양쪽 스레드에서** 만진다 — 메인(start/stop)과
    /// 콜백 큐(포트 충돌로 다시 여는 경우). 그래서 락으로 감싼다.
    private var _listener: NWListener?
    private var currentListener: NWListener? {
        lock.lock(); defer { lock.unlock() }
        return _listener
    }
    /// stop() 이후에 뒤늦게 도착한 실패 콜백이 방을 다시 열어버리지 않게 한다
    private var stopped = true
    private let queue = DispatchQueue(label: "poke.roomhost")

    /// `guest` 와 `pendingRejections` 는 Network.framework 콜백 스레드와
    /// UI 스레드(send/stop)에서 같이 만지므로 락으로 감싼다.
    private let lock = NSLock()
    private var _guest: PeerLink?
    private var pendingRejections: [PeerLink] = []

    var guest: PeerLink? {
        lock.lock(); defer { lock.unlock() }
        return _guest
    }

    var onGuestConnected: (@Sendable (PeerLink) -> Void)?
    var onGuestMessage: (@Sendable (Wire) -> Void)?
    var onGuestDisconnected: (@Sendable () -> Void)?
    var onError: (@Sendable (String) -> Void)?
    /// 게스트가 다른 프로토콜 버전으로 붙었을 때
    var onProtocolError: (@Sendable (String) -> Void)?
    /// 방을 **아예 열지 못했을 때** (포트 충돌·권한).
    /// 이걸 알려주지 않으면 열리지도 않은 방에서 상대를 기다리게 된다.
    var onListenFailed: (@Sendable () -> Void)?
    /// 중계 서버에 방이 등록됐다 (아직 상대는 없다)
    var onRelayRegistered: (@Sendable () -> Void)?

    // MARK: 중계 모드
    //
    // 중계를 쓰면 **리스너를 열지 않는다.** 대신 중계기로 나가는 연결을 걸고
    // 방을 등록해 둔다 — 그래서 방장도 NAT 뒤에 있을 수 있다.
    // 짝이 맞으면 그 연결이 곧 게스트 링크가 되므로, 그 뒤 배선은 LAN 과 같다.

    private var relayEndpoint: NWEndpoint?
    private var relayRoom = ""
    private var relaySecret: String?
    /// 중계 모드인가 (Bonjour 광고를 하지 않는다)
    private var usingRelay: Bool { relayEndpoint != nil }

    private var roomName = ""
    private var hostName = ""
    private var rules = BattleRules.default
    private var modeSummary = "일반"

    func start(roomName: String, hostName: String, rules: BattleRules, modeSummary: String = "일반") {
        stop()
        self.roomName = roomName
        self.hostName = hostName
        self.rules = rules
        self.modeSummary = modeSummary
        lock.lock(); stopped = false; lock.unlock()
        openListener(useFixedPort: true)
    }

    /// 중계 서버에 방을 등록하고 상대를 기다린다.
    ///
    /// LAN 과 달리 리스너를 열지 않으므로 포트를 열 필요가 없다 — 열려 있어야
    /// 하는 곳은 중계기 한 대뿐이다. 짝이 맞으면 그 연결을 그대로 게스트 링크로
    /// 쓰기 때문에, 그 뒤의 배틀 진행은 LAN 과 **완전히 같은 코드**를 탄다.
    func startRelay(server: NWEndpoint, room: String, secret: String?,
                    hostName: String, rules: BattleRules, modeSummary: String = "일반") {
        stop()
        self.roomName = room
        self.hostName = hostName
        self.rules = rules
        self.modeSummary = modeSummary
        lock.lock()
        stopped = false
        relayEndpoint = server
        relayRoom = room
        relaySecret = secret
        lock.unlock()
        dialRelay()
    }

    private func dialRelay() {
        guard !isStopped(), let server = relayEndpoint else { return }
        let link = PeerLink(to: server)
        link.onProtocolError = { [weak self] msg in self?.onProtocolError?(msg) }
        setGuest(link)
        link.startRelay(
            hello: RelayHello(role: .host, room: relayRoom, name: hostName, secret: relaySecret),
            onRegistered: { [weak self] _ in
                guard let self, self.isCurrentGuest(link) else { return }
                self.onRelayRegistered?()
            },
            onPaired: { [weak self] _ in
                guard let self, self.isCurrentGuest(link) else { return }
                self.onGuestConnected?(link)
            },
            onRejected: { [weak self] why in
                guard let self else { return }
                self.setGuest(nil)
                self.onError?("중계 서버가 거절했습니다: \(why)")
                self.onListenFailed?()
            },
            onMessage: { [weak self] msg in self?.onGuestMessage?(msg) },
            onState: { [weak self] st in
                guard let self, self.isCurrentGuest(link) else { return }
                switch st {
                case .failed(let e):
                    self.setGuest(nil)
                    self.onError?("중계 서버에 연결하지 못했습니다: \(e.localizedDescription)")
                    self.onListenFailed?()
                case .cancelled:
                    // 상대가 나갔거나 중계기가 끊었다.
                    // 방은 계속 열어둔다 — LAN 에서 게스트가 나가도 방이 유지되는 것과 같다.
                    self.setGuest(nil)
                    self.onGuestDisconnected?()
                    self.dialRelay()
                default: break
                }
            }
        )
    }

    /// 리스너를 연다.
    ///
    /// **고정 포트를 먼저 시도한다.** 같은 LAN 은 Bonjour 로 찾지만, 다른
    /// 네트워크(Tailscale·포트포워딩·터널)에서는 주소로 직접 붙어야 한다.
    /// 포트가 매번 바뀌면 안내할 수가 없다.
    ///
    /// 포트가 이미 쓰이고 있으면 **생성자가 아니라 `.failed` 로** 알려준다
    /// (NWError 48, Address already in use). 예전에는 `try?` 가 nil 을 주는지로
    /// 폴백을 걸었는데 생성자는 그 경우에 던지지 않는다 — 그래서 폴백이 한 번도
    /// 발동하지 않았고, 두 번째로 방을 여는 쪽은 임의 포트로 넘어가지 못하고
    /// 그냥 실패했다 (혼자 테스트하는 dev-two.sh 가 여기 걸렸다).
    private func openListener(useFixedPort: Bool) {
        guard !isStopped() else { return }
        do {
            let l: NWListener
            if useFixedPort, let fixed = NWEndpoint.Port(rawValue: RoomHost.preferredPort) {
                l = try NWListener(using: PeerLink.params, on: fixed)
            } else {
                l = try NWListener(using: PeerLink.params)
            }
            l.service = NWListener.Service(
                name: roomName,
                type: pokeBattleServiceType,
                domain: nil,
                txtRecord: txtRecord(occupied: false).data
            )
            l.newConnectionHandler = { [weak self] conn in
                guard let self else { conn.cancel(); return }
                self.accept(conn)
            }
            l.stateUpdateHandler = { [weak self] st in
                guard let self, case .failed(let e) = st else { return }
                self.setListener(nil)
                l.cancel()
                // 고정 포트가 막혔을 뿐이면 임의 포트로 다시 연다.
                // 이때 안내 주소의 포트도 자동으로 따라간다 (listeningPort 를 읽는다).
                if useFixedPort {
                    self.openListener(useFixedPort: false)
                    return
                }
                self.onError?("방 개설 실패: \(e.localizedDescription)")
                self.onListenFailed?()
            }
            setListener(l)
            l.start(queue: queue)
        } catch {
            if useFixedPort {
                openListener(useFixedPort: false)
                return
            }
            onError?("방 개설 실패: \(error.localizedDescription)")
            onListenFailed?()
        }
    }

    /// 들어온 연결 하나를 받는다. 1:1 이므로 이미 게스트가 있으면 거절한다.
    private func accept(_ conn: NWConnection) {
        // 이미 게스트가 있으면 거절한다 (1:1 전용).
        // 단 상대가 앱을 강제 종료해 TCP 만 남은 좀비 링크라면
        // 붙잡고 있을 이유가 없다 — 그러면 방이 영구히 막힌다.
        if let stale = guest, !stale.isAlive {
            setGuest(nil)
            stale.cancel()
        }
        if guest != nil {
            let link = PeerLink(connection: conn)
            // 거절 메시지가 플러시될 때까지 링크를 붙잡아 둔다
            retainRejection(link)
            link.start(onMessage: { _ in }, onState: { [weak self] st in
                guard st == .ready else { return }
                link.send(.joinRejected(reason: "이미 다른 사람이 방에 있습니다")) {
                    // 전송이 소켓에 넘어간 뒤에 끊는다 (먼저 끊으면 상대가 못 받는다)
                    link.cancel()
                    self?.releaseRejection(link)
                }
            })
            return
        }
        let link = PeerLink(connection: conn)
        link.onProtocolError = { [weak self] msg in self?.onProtocolError?(msg) }
        setGuest(link)
        advertise(occupied: true)
        link.start(
            onMessage: { [weak self] msg in self?.onGuestMessage?(msg) },
            onState: { [weak self] st in
                guard let self else { return }
                // **어느 링크의 상태인지 확인해야 한다.**
                // 지난 접속의 종료 콜백은 한참 뒤에 도착할 수 있고,
                // 그때 이미 새 게스트가 들어와 배틀을 시작했다면
                // 그 배틀을 끊어버린다 (양쪽이 무한 대기에 빠졌던 원인).
                guard self.isCurrentGuest(link) else { return }
                switch st {
                case .ready: self.onGuestConnected?(link)
                case .failed, .cancelled:
                    self.setGuest(nil)
                    self.advertise(occupied: false)
                    self.onGuestDisconnected?()
                default: break
                }
            }
        )
    }

    private func txtRecord(occupied: Bool) -> NWTXTRecord {
        var t = NWTXTRecord()
        t["host"] = hostName
        t["cap"] = String(rules.maxTeamSize)
        t["lvl"] = String(rules.level)
        t["busy"] = occupied ? "1" : "0"
        t["pv"] = String(PokeBattleProtocol.version)
        t["mode"] = modeSummary
        return t
    }

    private func advertise(occupied: Bool) {
        guard !usingRelay else { return }   // 중계 모드에는 Bonjour 광고가 없다
        currentListener?.service = NWListener.Service(
            name: roomName,
            type: pokeBattleServiceType,
            domain: nil,
            txtRecord: txtRecord(occupied: occupied).data
        )
    }

    func send(_ w: Wire) { guest?.send(w) }

    private func setGuest(_ link: PeerLink?) {
        lock.lock(); _guest = link; lock.unlock()
    }

    private func setListener(_ l: NWListener?) {
        lock.lock(); _listener = l; lock.unlock()
    }

    private func isStopped() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped
    }

    /// 이 링크가 지금의 게스트인가 (지난 접속의 뒤늦은 콜백을 걸러낸다)
    private func isCurrentGuest(_ link: PeerLink) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return _guest === link
    }

    private func retainRejection(_ link: PeerLink) {
        lock.lock(); pendingRejections.append(link); lock.unlock()
    }

    private func releaseRejection(_ link: PeerLink) {
        lock.lock(); pendingRejections.removeAll { $0 === link }; lock.unlock()
    }

    func stop() {
        lock.lock()
        stopped = true
        relayEndpoint = nil          // 재접속 루프를 끊는다
        let g = _guest
        let pending = pendingRejections
        let l = _listener
        _guest = nil
        _listener = nil
        pendingRejections.removeAll()
        lock.unlock()

        g?.cancel()
        for link in pending { link.cancel() }
        l?.cancel()
    }
}

/// LAN 의 방들을 찾는다.
final class RoomBrowser: @unchecked Sendable {
    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "poke.roombrowser")

    var onRooms: (@Sendable ([DiscoveredRoom]) -> Void)?
    var onError: (@Sendable (String) -> Void)?

    func start() {
        stop()
        let params = NWParameters()
        params.includePeerToPeer = true
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: pokeBattleServiceType, domain: nil), using: params)

        b.browseResultsChangedHandler = { [weak self] results, _ in
            let rooms: [DiscoveredRoom] = results.compactMap { r in
                guard case .service(let name, _, _, _) = r.endpoint else { return nil }
                var hostName = name, cap = 6, lvl = 50, busy = false
                // pv 가 없으면 버전 정보를 싣지 않던 최초 배포판(v1) 이다
                var pv = 1
                var mode = "일반"
                if case .bonjour(let txt) = r.metadata {
                    hostName = txt["host"] ?? name
                    cap = Int(txt["cap"] ?? "6") ?? 6
                    lvl = Int(txt["lvl"] ?? "50") ?? 50
                    busy = (txt["busy"] ?? "0") == "1"
                    pv = Int(txt["pv"] ?? "1") ?? 1
                    mode = txt["mode"] ?? "일반"
                }
                return DiscoveredRoom(name: name, hostName: hostName, teamCap: cap,
                                      level: lvl, occupied: busy, endpoint: r.endpoint,
                                      protocolVersion: pv, mode: mode)
            }
            // 같은 방이 인터페이스마다 따로 올라온다 — 이름으로 하나만 남긴다
            var unique: [String: DiscoveredRoom] = [:]
            for r in rooms where unique[r.name] == nil { unique[r.name] = r }
            self?.onRooms?(unique.values.sorted { $0.name < $1.name })
        }
        b.stateUpdateHandler = { [weak self] st in
            if case .failed(let e) = st {
                self?.onError?("방 검색 실패: \(e.localizedDescription)")
            }
        }
        browser = b
        b.start(queue: queue)
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }
}
