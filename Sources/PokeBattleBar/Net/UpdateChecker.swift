import Foundation

/// 업데이트 확인.
///
/// GitHub Releases 를 배포처로 쓴다. 앱을 열면 최신 릴리스 태그를 받아
/// 지금 버전과 비교하고, 새 버전이 있으면 우측 상단 버튼을 켠다.
///
/// **왜 필요한가**: 프로토콜 버전이 다르면 배틀이 안 된다. 파일을 손으로
/// 나눠주면 누군가는 꼭 구버전으로 남는다.
enum UpdateChecker {

    /// 배포 저장소 ("소유자/저장소").
    ///
    /// **한 곳에서만 정한다** — `scripts/config.sh` 의 `REPO` 를 바꾸면
    /// 번들의 Info.plist 에 박히고 앱이 그것을 읽는다.
    /// 정하지 않으면 업데이트 확인을 아예 하지 않는다 (버튼도 나오지 않는다).
    static let repo: String = {
        if let env = ProcessInfo.processInfo.environment["POKEBATTLE_REPO"], !env.isEmpty {
            return env
        }
        let fromBundle = Bundle.main.object(forInfoDictionaryKey: "PBBUpdateRepo") as? String
        return fromBundle ?? ""
    }()

    struct Update: Sendable, Equatable {
        var version: String
        /// 설치 파일(.command) 주소. 없으면 릴리스 페이지를 연다.
        var installerURL: URL?
        var pageURL: URL
        var notes: String
    }

    static var isConfigured: Bool { !repo.isEmpty && repo.contains("/") }

    /// 최신 릴리스를 확인한다. 새 버전이 없으면 nil.
    static func check(current: String) async -> Update? {
        guard isConfigured,
              let api = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")
        else { return nil }

        var req = URLRequest(url: api)
        req.timeoutInterval = 10
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = j["tag_name"] as? String
        else { return nil }

        let latest = normalize(tag)
        guard isNewer(latest, than: normalize(current)) else { return nil }

        // .command 설치 파일을 찾는다
        var installer: URL?
        if let assets = j["assets"] as? [[String: Any]] {
            for a in assets {
                guard let name = a["name"] as? String, name.hasSuffix(".command"),
                      let s = a["browser_download_url"] as? String else { continue }
                installer = URL(string: s)
                break
            }
        }
        let page = (j["html_url"] as? String).flatMap(URL.init(string:))
            ?? URL(string: "https://github.com/\(repo)/releases/latest")!

        return Update(version: latest, installerURL: installer, pageURL: page,
                      notes: (j["body"] as? String) ?? "")
    }

    /// "v1.11.0" -> "1.11.0"
    static func normalize(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// 의미 있는 버전 비교. 문자열 비교로는 1.10.0 < 1.9.0 이 되어버린다.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0
            let r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    private static func parts(_ v: String) -> [Int] {
        v.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }
}
