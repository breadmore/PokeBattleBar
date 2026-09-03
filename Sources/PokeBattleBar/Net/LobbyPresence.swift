import Foundation
import Network

/// 로비 존재 알림 서비스.
///
/// 방(`_pokebattle._tcp`)은 **배틀을 열었을 때만** 광고된다. 그래서 방을 열지
/// 않은 사람은 서로를 볼 수 없고, 초대할 대상도 알 수 없다. 이 서비스는 앱이
/// 켜져 있는 동안 계속 광고돼서 "지금 로비에 누가 있는지" 를 만든다.
///
/// 초대는 상대의 이 리스너로 직접 붙어서 보낸다 — 방을 먼저 열고, 방 이름을
/// 실어 보내면 상대가 그 방을 찾아 들어온다.
let pokeLobbyServiceType = "_pokelobby._tcp"

/// `POKEBATTLE_NETLOG=1` 이면 로비 광고·검색 상태를 stderr 로 찍는다.
/// GUI 안에서 벌어지는 mDNS 문제는 이것 없이는 원인을 알 수가 없다.
enum NetLog {
    static let on = ProcessInfo.processInfo.environment["POKEBATTLE_NETLOG"] == "1"
    static func say(_ m: String) {
        guard on else { return }
        FileHandle.standardError.write(
            Data("[net \(TestProfile.tag ?? "-")] \(m)\n".utf8))
    }
}

enum PeerStatus: String, Sendable, Codable {
    case free       // 로비에 있음
    case hosting    // 방을 열고 기다림
    case battling   // 배틀 중

    var ko: String {
        switch self {
        case .free:     "로비"
        case .hosting:  "방 열림"
        case .battling: "배틀 중"
        }
    }

    /// 초대를 보낼 수 있는 상태인가
    var invitable: Bool { self == .free }
}

struct LobbyPeer: Identifiable, Sendable, Equatable {
    /// Bonjour 서비스 이름 — 같은 이름이 둘일 수 없어 식별자로 쓸 수 있다
    var id: String
    var displayName: String
    var status: PeerStatus
    var endpoint: NWEndpoint
    var protocolVersion: Int

    var compatible: Bool { protocolVersion == PokeBattleProtocol.version }

    static func == (a: LobbyPeer, b: LobbyPeer) -> Bool {
        a.id == b.id && a.displayName == b.displayName
            && a.status == b.status && a.protocolVersion == b.protocolVersion
    }
}

final class LobbyPresence: @unchecked Sendable {
    private var listener: NWListener?
    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "poke.lobby")

    private let lock = NSLock()
    /// 들어온 초대 연결은 회신을 보낼 때까지 붙잡아 둬야 한다.
    /// 먼저 끊으면 상대가 회신을 못 받는다.
    private var openLinks: [String: PeerLink] = [:]

    /// 내 서비스 이름 — 이름이 겹치면 Bonjour 가 알아서 바꾸므로
    /// 처음부터 고유하게 만든다.
    private let instanceTag = String(UInt32.random(in: 0x1000...0xFFFF), radix: 16)

    private var displayName = ""
    private var status: PeerStatus = .free
    private var lastPeerCount = 0
    private var rebrowseGeneration = 0

    var onPeers: (@Sendable ([LobbyPeer]) -> Void)?
    /// 초대를 받았다 (보낸 사람, 방 이름)
    var onInvite: (@Sendable (String, String) -> Void)?
    /// 내가 보낸 초대가 거절됐다
    var onDeclined: (@Sendable (String) -> Void)?
    /// 초대를 보내지 못했다 (상대가 이미 없는 경우 — mDNS 에 남은 유령 항목).
    /// 이걸 알려주지 않으면 "초대 보냄" 이 영원히 남는다.
    var onInviteFailed: (@Sendable (String) -> Void)?
    var onError: (@Sendable (String) -> Void)?

    var serviceName: String { "\(displayName)#\(instanceTag)" }

    // MARK: 광고 + 검색

    func start(displayName: String) {
        stop()
        self.displayName = displayName
        do {
            let l = try NWListener(using: PeerLink.params)
            l.service = NWListener.Service(name: serviceName, type: pokeLobbyServiceType,
                                           domain: nil, txtRecord: txt().data)
            l.newConnectionHandler = { [weak self] conn in
                guard let self else { conn.cancel(); return }
                self.accept(conn)
            }
            l.stateUpdateHandler = { [weak self] st in
                NetLog.say("리스너 상태: \(st)")
                if case .failed(let e) = st {
                    self?.onError?("로비 광고 실패: \(e.localizedDescription)")
                }
            }
            listener = l
            l.start(queue: queue)
            NetLog.say("광고 시작: \(serviceName)")
        } catch {
            NetLog.say("광고 실패: \(error)")
            onError?("로비 광고 실패: \(error.localizedDescription)")
        }

        let params = NWParameters()
        params.includePeerToPeer = true
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: pokeLobbyServiceType, domain: nil),
                          using: params)
        b.browseResultsChangedHandler = browseHandler
        b.stateUpdateHandler = { [weak self] st in
            NetLog.say("브라우저 상태: \(st)")
            if case .failed(let e) = st {
                self?.onError?("로비 검색 실패: \(e.localizedDescription)")
            }
        }
        browser = b
        b.start(queue: queue)
        scheduleRebrowse()
    }

    private var browseHandler: (Set<NWBrowser.Result>, Set<NWBrowser.Result.Change>) -> Void {
        { [weak self] results, _ in
            guard let self else { return }
            let mine = self.serviceName
            NetLog.say("검색 결과 \(results.count)건 (나=\(mine)): "
                       + results.map { r in
                           if case .service(let n, _, _, _) = r.endpoint { return n }
                           return "?"
                       }.joined(separator: ", "))
            let peers: [LobbyPeer] = results.compactMap { r in
                guard case .service(let name, _, _, _) = r.endpoint else { return nil }
                guard name != mine else { return nil }        // 나는 목록에 넣지 않는다
                var display = name, st = PeerStatus.free, pv = 0
                if case .bonjour(let t) = r.metadata {
                    display = t["name"] ?? name
                    st = PeerStatus(rawValue: t["st"] ?? "") ?? .free
                    pv = Int(t["pv"] ?? "0") ?? 0
                }
                return LobbyPeer(id: name, displayName: display, status: st,
                                 endpoint: r.endpoint, protocolVersion: pv)
            }
            // 같은 서비스가 인터페이스마다(loopback, Wi-Fi, AWDL…) 따로 올라온다.
            // 걸러내지 않으면 목록에 같은 사람이 여러 번 보인다.
            var unique: [String: LobbyPeer] = [:]
            for p in peers where unique[p.id] == nil { unique[p.id] = p }
            let list = unique.values.sorted { $0.displayName < $1.displayName }
            self.lastPeerCount = list.count
            self.onPeers?(list)
        }
    }

    /// 아무도 못 찾은 상태가 이어지면 검색을 다시 건다.
    ///
    /// NWBrowser 는 검색을 시작한 **뒤에** 올라온 서비스를 간혹 놓친다
    /// (실제로 dns-sd 로는 보이는데 앱에서는 0명인 경우가 있었다).
    /// 찾은 게 있을 때는 건드리지 않아 목록이 깜빡이지 않게 한다.
    private func scheduleRebrowse() {
        rebrowseGeneration += 1
        let gen = rebrowseGeneration
        queue.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, gen == self.rebrowseGeneration else { return }
            guard self.browser != nil else { return }
            if self.lastPeerCount == 0 {
                NetLog.say("아무도 못 찾아서 검색을 다시 건다")
                self.browser?.cancel()
                self.browser = nil
                self.startBrowsingOnly()
            } else {
                self.scheduleRebrowse()
            }
        }
    }

    /// 광고는 그대로 두고 검색만 다시 시작한다
    private func startBrowsingOnly() {
        let params = NWParameters()
        params.includePeerToPeer = true
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: pokeLobbyServiceType, domain: nil),
                          using: params)
        b.browseResultsChangedHandler = browseHandler
        b.stateUpdateHandler = { [weak self] st in
            NetLog.say("브라우저 상태: \(st)")
            if case .failed(let e) = st {
                self?.onError?("로비 검색 실패: \(e.localizedDescription)")
            }
        }
        browser = b
        b.start(queue: queue)
        scheduleRebrowse()
    }

    /// 상태가 바뀌면 다시 광고한다 (배틀 중인 사람에게 초대를 보내지 않도록)
    func update(status: PeerStatus) {
        guard status != self.status else { return }
        self.status = status
        listener?.service = NWListener.Service(name: serviceName, type: pokeLobbyServiceType,
                                              domain: nil, txtRecord: txt().data)
    }

    func update(displayName: String) {
        guard displayName != self.displayName, !displayName.isEmpty else { return }
        // 서비스 이름이 바뀌므로 다시 올려야 한다
        start(displayName: displayName)
    }

    func stop() {
        rebrowseGeneration += 1        // 예약된 재검색을 무효화한다
        listener?.cancel(); listener = nil
        browser?.cancel(); browser = nil
        lock.lock(); let links = openLinks; openLinks = [:]; lock.unlock()
        for l in links.values { l.cancel() }
    }

    private func txt() -> NWTXTRecord {
        var t = NWTXTRecord()
        t["name"] = displayName
        t["st"] = status.rawValue
        t["pv"] = String(PokeBattleProtocol.version)
        return t
    }

    // MARK: 초대 주고받기

    /// 상대에게 초대를 보낸다. 방을 **먼저 열어둬야** 상대가 찾아올 수 있다.
    func sendInvite(to peer: LobbyPeer, roomName: String) {
        let link = PeerLink(to: peer.endpoint)
        let key = "out-\(peer.id)-\(UUID().uuidString)"
        retain(link, key: key)
        link.onProtocolError = { [weak self] msg in self?.onError?(msg) }
        link.start(
            onMessage: { [weak self] msg in
                guard let self else { return }
                if case .inviteDeclined(let who) = msg { self.onDeclined?(who) }
                self.release(key)
                link.cancel()
            },
            onState: { [weak self] st in
                guard let self else { return }
                switch st {
                case .ready:
                    link.send(.invite(from: self.displayName, roomName: roomName))
                case .failed:
                    NetLog.say("초대 전송 실패: \(peer.displayName)")
                    if self.release(key) { self.onInviteFailed?(peer.displayName) }
                case .cancelled:
                    self.release(key)
                default: break
                }
            }
        )
        // 회신이 없어도 영원히 붙잡고 있지는 않는다.
        // 시간이 다 되면 "못 보냈다" 로 처리해 UI 를 풀어준다.
        queue.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self else { return }
            if self.release(key) {
                link.cancel()
                self.onInviteFailed?(peer.displayName)
            }
        }
    }

    private func accept(_ conn: NWConnection) {
        let link = PeerLink(connection: conn)
        let key = "in-\(UUID().uuidString)"
        retain(link, key: key)
        link.onProtocolError = { [weak self] msg in self?.onError?(msg) }
        link.start(
            onMessage: { [weak self] msg in
                guard let self else { return }
                if case .invite(let from, let room) = msg {
                    self.lock.lock(); self.pendingReplies[from] = key; self.lock.unlock()
                    self.onInvite?(from, room)
                }
            },
            onState: { [weak self] st in
                guard let self else { return }
                switch st {
                case .failed, .cancelled: self.release(key)
                default: break
                }
            }
        )
        queue.asyncAfter(deadline: .now() + 120) { [weak self] in
            guard let self else { return }
            if self.release(key) { link.cancel() }
        }
    }

    /// 초대를 보낸 사람 -> 붙잡아 둔 연결. 거절 회신을 보낼 때 쓴다.
    private var pendingReplies: [String: String] = [:]

    /// 초대를 거절한다고 알린다 (상대가 계속 기다리지 않게)
    func decline(from: String, myName: String) {
        lock.lock()
        let key = pendingReplies.removeValue(forKey: from)
        let link = key.flatMap { openLinks[$0] }
        lock.unlock()
        guard let link, let key else { return }
        link.send(.inviteDeclined(from: myName)) { [weak self] in
            link.cancel()
            self?.release(key)
        }
    }

    /// 수락했으면 초대 연결은 더 필요 없다 — 이제 방으로 붙는다
    func closeInvite(from: String) {
        lock.lock()
        let key = pendingReplies.removeValue(forKey: from)
        lock.unlock()
        if let key, release(key) { /* 링크는 release 안에서 목록에서만 빠진다 */ }
    }

    private func retain(_ link: PeerLink, key: String) {
        lock.lock(); openLinks[key] = link; lock.unlock()
    }

    @discardableResult
    private func release(_ key: String) -> Bool {
        lock.lock(); let had = openLinks.removeValue(forKey: key) != nil; lock.unlock()
        return had
    }
}
