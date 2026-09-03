import Foundation

/// 개체별 **지닌 도구 + 특성** 선택을 저장한다.
/// PokeTokenBar 에는 도구·특성 개념이 없으므로, 여기서 자유롭게 골라 끼운다.
actor LoadoutStore {
    static let shared = LoadoutStore()

    struct Loadout: Codable, Hashable, Sendable {
        var item: String?        // 도구 slug
        var ability: String?     // 특성 slug
        /// 폼 이름 (로토무 히트 등). **PokeTokenBar 에는 기록하지 않는다** —
        /// 도감은 그쪽 소유이고, 어떤 폼으로 싸울지는 여기서만 정한다.
        var form: String?
    }

    private let fileURL: URL
    private var table: [String: Loadout] = [:]

    init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/PokeBattleBar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appending(path: "loadouts.json")
        if let d = try? Data(contentsOf: fileURL),
           let t = try? JSONDecoder().decode([String: Loadout].self, from: d) {
            table = t
        }
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(table) { try? d.write(to: fileURL) }
    }

    private func key(_ slot: RosterSlot) -> String { "\(slot.id)#\(slot.speciesID)" }

    func loadout(for slot: RosterSlot) -> Loadout {
        table[key(slot)] ?? Loadout()
    }

    func setItem(_ item: String?, for slot: RosterSlot) {
        var l = table[key(slot)] ?? Loadout()
        l.item = item
        table[key(slot)] = l
        persist()
    }

    func setForm(_ form: String?, for slot: RosterSlot) {
        var l = table[key(slot)] ?? Loadout()
        l.form = form
        table[key(slot)] = l
        persist()
    }

    func setAbility(_ ability: String?, for slot: RosterSlot) {
        var l = table[key(slot)] ?? Loadout()
        l.ability = ability
        table[key(slot)] = l
        persist()
    }

    /// 실제 도구·특성 정의로 해석한다. 특성을 안 골랐으면 첫 슬롯(숨겨진 특성 제외) 을 쓴다.
    func resolve(for slot: RosterSlot, species: SpeciesDef) async -> (item: ItemDef?, ability: AbilityDef?) {
        let l = loadout(for: slot)

        var item: ItemDef?
        if let name = l.item { item = await ItemCatalog.shared.item(name) }

        var ability: AbilityDef?
        if let name = l.ability {
            ability = await AbilityCatalog.shared.ability(name)
        } else if let first = species.abilitySlots.first(where: { !$0.hidden })
                            ?? species.abilitySlots.first {
            ability = await AbilityCatalog.shared.ability(first.name)
        }
        return (item, ability)
    }
}
