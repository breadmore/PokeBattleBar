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
}

/// 방을 광고하고 게스트 한 명을 받는다.
final class RoomHost: @unchecked Sendable {
    private var listener: NWListener?
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

    private var roomName = ""
    private var hostName = ""
    private var rules = BattleRules.default

    func start(roomName: String, hostName: String, rules: BattleRules) {
        stop()
        self.roomName = roomName
        self.hostName = hostName
        self.rules = rules

        do {
            let l = try NWListener(using: PeerLink.params)
            l.service = NWListener.Service(
                name: roomName,
                type: pokeBattleServiceType,
                domain: nil,
                txtRecord: txtRecord(occupied: false).data
            )
            l.newConnectionHandler = { [weak self] conn in
                guard let self else { conn.cancel(); return }
                // 이미 게스트가 있으면 거절한다 (1:1 전용)
                if self.guest != nil {
                    let link = PeerLink(connection: conn)
                    // 거절 메시지가 플러시될 때까지 링크를 붙잡아 둔다
                    self.retainRejection(link)
                    link.start(onMessage: { _ in }, onState: { st in
                        guard st == .ready else { return }
                        link.send(.joinRejected(reason: "이미 다른 사람이 방에 있습니다")) {
                            // 전송이 소켓에 넘어간 뒤에 끊는다 (먼저 끊으면 상대가 못 받는다)
                            link.cancel()
                            self.releaseRejection(link)
                        }
                    })
                    return
                }
                let link = PeerLink(connection: conn)
                self.setGuest(link)
                self.advertise(occupied: true)
                link.start(
                    onMessage: { [weak self] msg in self?.onGuestMessage?(msg) },
                    onState: { [weak self] st in
                        guard let self else { return }
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
            l.stateUpdateHandler = { [weak self] st in
                if case .failed(let e) = st {
                    self?.onError?("방 개설 실패: \(e.localizedDescription)")
                }
            }
            listener = l
            l.start(queue: queue)
        } catch {
            onError?("방 개설 실패: \(error.localizedDescription)")
        }
    }

    private func txtRecord(occupied: Bool) -> NWTXTRecord {
        var t = NWTXTRecord()
        t["host"] = hostName
        t["cap"] = String(rules.maxTeamSize)
        t["lvl"] = String(rules.level)
        t["busy"] = occupied ? "1" : "0"
        return t
    }

    private func advertise(occupied: Bool) {
        listener?.service = NWListener.Service(
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

    private func retainRejection(_ link: PeerLink) {
        lock.lock(); pendingRejections.append(link); lock.unlock()
    }

    private func releaseRejection(_ link: PeerLink) {
        lock.lock(); pendingRejections.removeAll { $0 === link }; lock.unlock()
    }

    func stop() {
        lock.lock()
        let g = _guest
        let pending = pendingRejections
        _guest = nil
        pendingRejections.removeAll()
        lock.unlock()

        g?.cancel()
        for l in pending { l.cancel() }
        listener?.cancel()
        listener = nil
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
                if case .bonjour(let txt) = r.metadata {
                    hostName = txt["host"] ?? name
                    cap = Int(txt["cap"] ?? "6") ?? 6
                    lvl = Int(txt["lvl"] ?? "50") ?? 50
                    busy = (txt["busy"] ?? "0") == "1"
                }
                return DiscoveredRoom(name: name, hostName: hostName, teamCap: cap,
                                      level: lvl, occupied: busy, endpoint: r.endpoint)
            }
            self?.onRooms?(rooms.sorted { $0.name < $1.name })
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
