import Foundation
import Network

/// 다른 네트워크의 상대와 붙기.
///
/// Bonjour(mDNS)는 **링크 로컬**이라 라우터를 넘지 못한다. 그래서 같은 LAN 이
/// 아니면 자동 검색이 안 된다. 대신 주소로 직접 붙을 수 있게 한다 —
/// 이렇게 해두면 Tailscale 같은 가상 LAN, 포트포워딩, 터널이 모두 쓰인다.
enum DirectConnect {

    /// "100.64.1.2:51234" / "example.com:51234" / "100.64.1.2" (포트 생략 시 기본값)
    ///
    /// - Parameter defaultPort: 포트를 안 적었을 때 쓸 번호.
    ///   방은 51234, 중계 서버는 51235 로 서로 다르다.
    static func endpoint(from text: String,
                         defaultPort: UInt16 = RoomHost.preferredPort) -> NWEndpoint? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }

        var hostPart = t
        var portPart = defaultPort

        // IPv6 은 대괄호로 감싼다: [fd00::1]:51234
        if t.hasPrefix("[") {
            guard let close = t.firstIndex(of: "]") else { return nil }
            hostPart = String(t[t.index(after: t.startIndex)..<close])
            let rest = t[t.index(after: close)...]
            if rest.hasPrefix(":"), let p = UInt16(rest.dropFirst()) { portPart = p }
        } else if let colon = t.lastIndex(of: ":"),
                  // IPv6 을 포트 구분으로 오해하지 않게 — 콜론이 하나일 때만
                  t.filter({ $0 == ":" }).count == 1 {
            hostPart = String(t[t.startIndex..<colon])
            if let p = UInt16(t[t.index(after: colon)...]) { portPart = p }
        }

        guard !hostPart.isEmpty, let port = NWEndpoint.Port(rawValue: portPart) else {
            return nil
        }
        return .hostPort(host: NWEndpoint.Host(hostPart), port: port)
    }

    /// 화면에 보여줄 내 주소들.
    ///
    /// 루프백과 링크 로컬은 남에게 알려줘도 소용없으니 뺀다.
    /// Tailscale 주소(100.64.0.0/10)는 다른 네트워크에서 바로 쓸 수 있으므로 앞에 둔다.
    static func myAddresses(port: UInt16) -> [(address: String, note: String)] {
        var out: [(String, String)] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return out }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            guard let sa = ptr.pointee.ifa_addr else { continue }
            let family = sa.pointee.sa_family
            guard family == UInt8(AF_INET) else { continue }   // IPv4 만 (안내가 단순해진다)

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len),
                              &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            guard !ip.hasPrefix("169.254") else { continue }    // 링크 로컬은 소용없다

            let name = String(cString: ptr.pointee.ifa_name)
            let note: String
            if ip.hasPrefix("100.") && isTailscaleRange(ip) {
                note = "Tailscale — 다른 네트워크에서도 이 주소로 붙을 수 있습니다"
            } else if isPrivate(ip) {
                note = "같은 네트워크(\(name))에서만 — 밖에서는 포트포워딩이 필요합니다"
            } else {
                note = "공인 주소(\(name))"
            }
            out.append(("\(ip):\(port)", note))
        }
        // Tailscale 을 맨 위로
        return out.sorted { a, b in
            a.1.hasPrefix("Tailscale") && !b.1.hasPrefix("Tailscale")
        }
    }

    /// 100.64.0.0/10 (CGNAT 대역 — Tailscale 이 쓴다)
    private static func isTailscaleRange(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts[0] == 100 else { return false }
        return (64...127).contains(parts[1])
    }

    private static func isPrivate(_ ip: String) -> Bool {
        let p = ip.split(separator: ".").compactMap { Int($0) }
        guard p.count == 4 else { return false }
        if p[0] == 10 { return true }
        if p[0] == 192 && p[1] == 168 { return true }
        if p[0] == 172 && (16...31).contains(p[1]) { return true }
        return false
    }
}
