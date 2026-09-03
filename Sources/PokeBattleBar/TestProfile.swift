import Foundation
import SwiftUI

/// 한 대의 맥에서 앱을 두 개 띄워 혼자 배틀을 테스트하기 위한 장치.
///
/// 배포본에는 영향이 없다 — 환경변수를 주지 않으면 `.none` 이고
/// 모든 경로·이름이 기존과 완전히 같다.
///
/// 두 인스턴스가 실제로 충돌하는 것은 승패 기록(`record.json`) 하나뿐이다.
/// 리스너 포트는 커널이 자동 할당하고, PokeAPI 디스크 캐시는
/// 읽기 위주라 **일부러 공유한다** (같은 데이터를 두 번 받을 이유가 없다).
enum TestProfile {
    /// `POKEBATTLE_PROFILE=B` 처럼 주면 그 이름으로 격리된다.
    /// 파일 이름에 들어가므로 영숫자로만 제한한다.
    static let tag: String? = sanitize(ProcessInfo.processInfo.environment["POKEBATTLE_PROFILE"])

    /// 파일 이름에 들어가므로 영숫자로만 제한한다.
    static func sanitize(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let safe = raw.filter { $0.isLetter || $0.isNumber }
        return safe.isEmpty ? nil : String(safe.prefix(16))
    }

    static var isTest: Bool { tag != nil }

    /// 이 인스턴스만 쓰는 승패 기록 파일 이름.
    static var recordFileName: String { recordFileName(tag: tag) }

    static func recordFileName(tag: String?) -> String {
        fileName("record.json", tag: tag)
    }

    /// 인스턴스마다 따로 써야 하는 파일 이름.
    /// 두 앱이 같은 파일에 쓰면 나중에 쓴 쪽이 앞의 내용을 덮는다.
    static func fileName(_ base: String) -> String { fileName(base, tag: tag) }

    static func fileName(_ base: String, tag: String?) -> String {
        guard let tag else { return base }
        let stem = (base as NSString).deletingPathExtension
        let ext = (base as NSString).pathExtension
        return ext.isEmpty ? "\(stem)-test-\(tag)" : "\(stem)-test-\(tag).\(ext)"
    }

    /// 창 제목 — 두 창을 눈으로 구분할 수 있어야 한다.
    static var windowTitle: String { windowTitle(tag: tag) }

    static func windowTitle(tag: String?) -> String {
        guard let tag else { return "PokeBattleBar" }
        return "PokeBattleBar 〔테스트 \(tag)〕"
    }

    /// 로비에서 어느 쪽이 내 방인지 알아볼 수 있게 기본 이름에 표시를 붙인다.
    static func decorate(playerName: String) -> String {
        decorate(playerName: playerName, tag: tag)
    }

    static func decorate(playerName: String, tag: String?) -> String {
        guard let tag else { return playerName }
        return "\(playerName)-\(tag)"
    }

    /// `POKEBATTLE_TEAM=94,555,479` — 이 인스턴스의 로스터를 지정한 종으로 바꾼다.
    ///
    /// PokeTokenBar 의 데이터는 읽지도 쓰지도 않는다. 특정 포켓몬끼리
    /// 붙여보려고 도감을 만질 필요가 없게 하는 것이 목적이다.
    static let overrideTeam: [Int]? = parseTeam(ProcessInfo.processInfo.environment["POKEBATTLE_TEAM"])

    /// 잘못된 종 번호는 버리고, 배틀 최대 인원인 6마리까지만 받는다.
    static func parseTeam(_ raw: String?) -> [Int]? {
        guard let raw, !raw.isEmpty else { return nil }
        let ids = raw.split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .filter { (1...1025).contains($0) }
        return ids.isEmpty ? nil : Array(ids.prefix(6))
    }

    /// `POKEBATTLE_NATURE=고집` — 지정 팀 전원의 성격. 없으면 성실(보정 없음).
    ///
    /// 실제 로스터의 성격은 언제나 PokeTokenBar 를 따른다. 이건 지정 팀에만 쓴다.
    static var overrideNature: String {
        ProcessInfo.processInfo.environment["POKEBATTLE_NATURE"] ?? "serious"
    }

    /// 지정 팀을 로스터 형태로 만든다.
    static func overrideRoster() -> [RosterSlot]? {
        guard let ids = overrideTeam else { return nil }
        let nature = overrideNature
        return ids.enumerated().map { idx, id in
            RosterSlot(id: "test-\(idx)-\(id)", speciesID: id, nature: nature,
                       rarity: "common", isShiny: false, origin: .dex, fullyEvolved: true)
        }
    }

    /// 테스트 인스턴스를 좌우로 나눠 띄운다 — 두 창이 정확히 겹치면
    /// 뒤쪽을 손으로 찾아 옮겨야 해서 혼자 테스트하기가 번거롭다.
    /// 접근성 권한이 필요한 AppleScript 대신 앱이 직접 자리를 잡는다.
    static var windowPosition: UnitPoint { windowPosition(tag: tag) }

    static func windowPosition(tag: String?) -> UnitPoint {
        switch tag {
        case .none:   return .center           // 배포본은 기존 그대로
        case "A":     return .topLeading
        case "B":     return .topTrailing
        default:      return .top
        }
    }

    /// 두 창이 나란히 들어가도록 테스트 인스턴스는 조금 좁게 띄운다.
    /// (RootView 의 minWidth 720 보다는 커야 한다)
    static var windowWidth: CGFloat { isTest ? 760 : 860 }

    /// 실행 중인 인스턴스가 무엇인지 로그에 한 줄 남긴다.
    static func describe() -> String? {
        guard let tag else { return nil }
        var parts = ["테스트 프로필 \(tag)", "기록: \(recordFileName)"]
        if let t = overrideTeam { parts.append("지정 팀: \(t.map(String.init).joined(separator: ","))") }
        return parts.joined(separator: " · ")
    }
}
