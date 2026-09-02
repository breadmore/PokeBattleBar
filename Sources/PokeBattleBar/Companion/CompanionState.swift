import Foundation

/// PokeTokenBar 가 쓰는 상태 파일을 **읽기 전용**으로 파싱한다.
/// 우리는 이 파일에 절대 쓰지 않는다 — 원본 앱이 소유자다.
enum CompanionStore {
    static let stateURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/PokeTokenBar/companion-state.json")

    static let spritesDir = FileManager.default
        .homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/PokeTokenBar/sprites")

    static func load() throws -> CompanionState {
        let data = try Data(contentsOf: stateURL)
        return try JSONDecoder().decode(CompanionState.self, from: data)
    }

    /// PokeTokenBar 가 이미 받아둔 스프라이트를 재활용한다. 없으면 nil.
    static func spriteURL(speciesID: Int, shiny: Bool) -> URL? {
        let names = shiny ? ["\(speciesID)-sha.gif", "\(speciesID)-a.gif"]
                          : ["\(speciesID)-a.gif", "\(speciesID)-s.png"]
        for n in names {
            let u = spritesDir.appending(path: n)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }
}

struct CompanionState: Codable {
    var dex: [DexEntry]
    var active: ActiveCompanion?
    var language: String?
    var usedSinceInstall: Int?
    var representativeSpeciesID: Int?

    struct DexEntry: Codable {
        var id: String                  // UUID 문자열 — 개체 식별자
        var baseID: Int
        var finalID: Int
        var chainOrder: [Int]
        var nature: String
        var rarity: String
        var isShiny: Bool
        var caughtAt: Double
        var names: [String: [String: String]]?

        /// 도감 개체는 최종 진화형으로 싸운다.
        var battleSpeciesID: Int { finalID }

        func localizedName(_ lang: String) -> String? {
            names?[String(finalID)]?[lang]
        }
    }

    struct ActiveCompanion: Codable {
        var baseID: Int
        var pathIDs: [Int]
        var plannedPathIDs: [Int]?
        var stageIndex: Int
        var totalForms: Int
        var nature: String
        var rarity: String
        var isShiny: Bool

        /// 진행중 개체는 **현재 진화 단계**로 싸운다 (미완성이면 약하다 — 의도된 것).
        var battleSpeciesID: Int {
            let idx = max(0, min(stageIndex, pathIDs.count - 1))
            return pathIDs.isEmpty ? baseID : pathIDs[idx]
        }
        var isFullyEvolved: Bool { stageIndex >= totalForms - 1 }
    }
}

/// 배틀에 낼 수 있는 후보 한 마리 (도감 개체 또는 진행중 동반).
struct RosterSlot: Identifiable, Codable, Hashable {
    enum Origin: String, Codable { case dex, active }
    var id: String
    var speciesID: Int
    var nature: String
    var rarity: String
    var isShiny: Bool
    var origin: Origin
    /// 진행중 개체는 진화가 덜 끝났을 수 있다 — UI 에서 표시용.
    var fullyEvolved: Bool

    static func roster(from state: CompanionState) -> [RosterSlot] {
        var out: [RosterSlot] = state.dex.map {
            RosterSlot(id: $0.id, speciesID: $0.battleSpeciesID, nature: $0.nature,
                       rarity: $0.rarity, isShiny: $0.isShiny, origin: .dex, fullyEvolved: true)
        }
        if let a = state.active {
            out.append(RosterSlot(id: "active-\(a.baseID)", speciesID: a.battleSpeciesID,
                                  nature: a.nature, rarity: a.rarity, isShiny: a.isShiny,
                                  origin: .active, fullyEvolved: a.isFullyEvolved))
        }
        return out
    }
}
