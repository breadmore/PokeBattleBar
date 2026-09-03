import Foundation

/// `PokeBattleBar --abilitytest`
/// **등장 가능한 특성 중 몇 개가 실제로 배틀에 반영되는지** 측정한다.
///
/// PokeAPI 는 특성 효과를 산문으로만 주고, Showdown 조차 특성은 데이터가 아니라
/// JavaScript 함수다. 그래서 특성만은 하나씩 손으로 구현해야 하고,
/// "표시만" 인 것이 얼마나 남았는지 숫자로 알고 있어야 한다.
enum AbilityCoverageTest {

    static func run(full: Bool) async -> Bool {
        print("=== 특성 구현률 ===\n")
        var ok = true

        // 내 도감에서 실제로 나올 수 있는 종을 모은다
        let roster: [RosterSlot]
        if let st = try? CompanionStore.load() {
            roster = RosterSlot.roster(from: st)
        } else {
            roster = []
        }

        // PokeTokenBar 가 줄 수 있는 베이스 종 (5세대까지)
        var speciesIDs = Set(roster.map(\.speciesID))
        // 표본을 넓히려면 대표 종을 더 섞는다
        let extra = [3, 6, 9, 12, 25, 35, 52, 65, 68, 94, 95, 105, 112, 121, 130, 131,
                     143, 149, 151, 197, 208, 212, 214, 229, 232, 248, 260, 282, 289,
                     306, 317, 330, 350, 373, 376, 381, 385, 392, 395, 405, 445, 448,
                     460, 466, 467, 468, 472, 473, 479, 494, 497, 508, 526, 530, 534,
                     537, 545, 553, 560, 563, 567, 571, 579, 584, 589, 596, 601, 604,
                     609, 612, 615, 621, 623, 625, 630, 635, 637, 644, 649]
        speciesIDs.formUnion(full ? extra : Array(extra.prefix(30)))

        print("표본 종 \(speciesIDs.count)개에서 특성 수집 중…")
        var abilities: [String: AbilityDef] = [:]
        for id in speciesIDs.sorted() {
            guard let sp = try? await PokeAPI.shared.species(id) else { continue }
            for a in await AbilityCatalog.shared.abilities(for: sp) {
                abilities[a.name] = a
            }
        }

        let total = abilities.count
        let done = abilities.values.filter(\.isImplemented)
        let todo = abilities.values.filter { !$0.isImplemented }
        let pct = total == 0 ? 0 : done.count * 100 / total

        print()
        print("  등장 가능한 특성: \(total)종")
        print("  배틀에 반영됨:   \(done.count)종  (\(pct)%)")
        print("  표시만:         \(todo.count)종")
        print()

        ok = show(total > 50, "충분한 표본", "\(total)종") && ok
        ok = show(pct >= 60, "구현률 60% 이상", "\(pct)%") && ok

        if !todo.isEmpty {
            print("  -- 아직 반영 안 되는 특성 --")
            for a in todo.sorted(by: { $0.display < $1.display }).prefix(full ? 200 : 30) {
                print("    \(a.display.padding(toLength: 12, withPad: " ", startingAt: 0))"
                      + " \(a.shortEffect.prefix(72))")
            }
            if todo.count > (full ? 200 : 30) { print("    … 외 \(todo.count - 30)종") }
        }

        // 구현된 것들이 실제로 kind 를 가지는지 (매핑 오타 방지)
        print()
        var broken: [String] = []
        for a in done where AbilityCatalog.kind(for: a.name) == .none {
            broken.append(a.name)
        }
        ok = show(broken.isEmpty, "구현 표시된 특성은 전부 실제 효과가 있다",
                  broken.isEmpty ? "" : "\(broken)") && ok

        // 내 로스터 기준
        if !roster.isEmpty {
            print()
            print("  -- 내 로스터 --")
            for slot in roster {
                guard let sp = try? await PokeAPI.shared.species(slot.speciesID) else { continue }
                let list = await AbilityCatalog.shared.abilities(for: sp)
                let impl = list.filter(\.isImplemented).count
                print("    \(sp.display.padding(toLength: 8, withPad: " ", startingAt: 0))"
                      + " \(impl)/\(list.count) 반영"
                      + " — " + list.map {
                          $0.display + ($0.isImplemented ? "" : "(표시만)")
                      }.joined(separator: ", "))
            }
        }

        print(ok ? "\n✓ 통과" : "\n✗ 실패 항목 있음")
        return ok
    }

    private static func show(_ c: Bool, _ l: String, _ d: String = "") -> Bool {
        print(c ? "  ✓ \(l)\(d.isEmpty ? "" : "  (\(d))")"
                : "  ✗ \(l)\(d.isEmpty ? "" : "  — \(d)")")
        return c
    }
}
