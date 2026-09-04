import Foundation

/// **내 로스터가 실제로 배울 수 있는 기술 중 몇 개가 배틀에서 작동하는가.**
///
/// 기존 감사(--mechaudit)는 "부류" 단위로 셌다 — 18개 부류 중 16개를
/// 처리하면 "남은 기술 0개" 가 나온다. 그런데 사용자는 화면에서
/// "못 쓰는 기술이 너무 많다" 고 느꼈다. 두 말이 다 맞을 수 있다:
/// 부류는 덮었지만 **개별 기술**이 조용히 아무 일도 안 하는 것이다.
///
/// 그래서 이 감사는 부류가 아니라 **기술 하나하나**를 센다. 기준은
/// "이 기술이 배틀에서 무언가 일으키는가" 다.
///
///     PokeBattleBar --usability
///     PokeBattleBar --usability --all
/// 검증은 **메인 스레드에서** 돌아야 한다 — 배틀 엔진의 한 턴 계산은
/// 디버그 빌드에서 스택 프레임이 커서 협조 스레드(512KB)를 넘긴다.
/// nonisolated async 로 두면 MainActor 에서 불러도 협조 풀로 넘어간다.
@MainActor
enum MoveUsabilityAudit {

    static func run(verbose: Bool) async -> Bool {
        print("=== 기술이 실제로 작동하는가 (내 로스터 기준) ===\n")

        let roster: [RosterSlot]
        if let st = try? CompanionStore.load() {
            roster = RosterSlot.roster(from: st)
        } else {
            roster = []
        }
        guard !roster.isEmpty else {
            print("  도감을 읽을 수 없습니다 (PokeTokenBar 가 필요합니다)")
            return true
        }

        // 로스터가 배울 수 있는 기술 전체를 모은다
        var names = Set<String>()
        var speciesCount = 0
        for slot in roster {
            guard let sp = try? await PokeAPI.shared.species(slot.speciesID) else { continue }
            speciesCount += 1
            names.formUnion(sp.learnableMoves)
        }
        print("  종 \(speciesCount)마리가 배울 수 있는 기술 \(names.count)개\n")

        var dead: [(String, String)] = []      // (이름, 왜 아무 일도 없는가)
        var working = 0
        var checked = 0

        for name in names.sorted() {
            guard let mv = try? await PokeAPI.shared.move(name) else { continue }
            checked += 1
            if let why = whyDead(mv) { dead.append((mv.display, why)) } else { working += 1 }
        }

        let pct = checked == 0 ? 0 : working * 100 / checked
        print("  작동 \(working)/\(checked)개 (\(pct)%)")
        if dead.isEmpty {
            print("  ✓ 아무 일도 하지 않는 기술 없음\n")
            return true
        }

        // 이유별로 묶어 보여준다 — 같은 이유는 한 번에 고칠 수 있다
        var byReason: [String: [String]] = [:]
        for (n, why) in dead { byReason[why, default: []].append(n) }
        print("  아무 일도 하지 않는 기술 \(dead.count)개 — 이유별:\n")
        for why in byReason.keys.sorted(by: { byReason[$0]!.count > byReason[$1]!.count }) {
            let list = byReason[why]!
            print("  · \(why) — \(list.count)개")
            let shown = verbose ? list : Array(list.prefix(10))
            print("      \(shown.joined(separator: ", "))"
                  + (!verbose && list.count > 10 ? " … +\(list.count - 10)" : ""))
        }
        print("")
        return true
    }

    /// 더블배틀에서만 의미가 있는 기술. 1대1 에서는 발동 자체가 불가능하므로
    /// **미구현이 아니라 해당 없음**이다. 섞어두면 진짜 빠진 것을 가린다.
    private static let doublesOnlyMoves: Set<String> = [
        "helping-hand", "ally-switch", "after-you", "quash",
        "guard-split", "guard-swap", "power-split", "power-swap",
        "heal-pulse", "aromatherapy", "heal-bell", "life-dew",
        "coaching", "decorate", "follow-me", "rage-powder",
        "wide-guard", "quick-guard", "crafty-shield", "mat-block",
        "spotlight", "instruct", "hold-hands", "aromatic-mist",
        "flower-shield", "gear-up", "magnetic-flux", "make-it-rain-x",
        "simple-beam", "entrainment", "role-play", "skill-swap",
    ]

    /// 이 기술이 배틀에서 **아무 일도 일으키지 않는** 이유. nil 이면 작동한다.
    private static func whyDead(_ mv: MoveDef) -> String? {
        // 데미지를 주면 작동한다
        if mv.isDamaging { return nil }
        // 상태이상을 건다
        if mv.ailment != .none, mv.ailment != .unknown { return nil }
        // 랭크를 바꾼다
        if !mv.statChanges.isEmpty { return nil }
        // 회복한다
        if mv.healingPercent != 0 { return nil }
        // 손으로 구현한 기술 목록에 있다
        if BattleEngine.scriptedMoveNames.contains(mv.name) { return nil }
        // 조건부 기술 표에 있다
        if ConditionalMove.all.contains(mv.name) { return nil }
        // 방어 계열 — MoveFlags 로 판정해 처리한다
        if MoveFlags.isProtect(mv.name) { return nil }
        // 날씨·필드를 만드는 기술 — 이름으로 판정해 처리한다
        if Weather.from(moveName: mv.name) != nil { return nil }
        if Terrain.from(moveName: mv.name) != nil { return nil }
        // 자기 교체 기술 (유턴 계열)
        if mv.isPivot { return nil }
        // 더블배틀 전용 기술 — 1대1 에서는 발동할 수 없다 (미구현이 아니다)
        if doublesOnlyMoves.contains(mv.name) { return "더블배틀 전용 (1대1 해당 없음)" }
        // 장애물·화면·필드·날씨를 만든다

        // 여기까지 오면 아무 경로도 타지 않는다. 왜인지 나눠준다.
        if mv.damageClass == .status {
            if let vs = Showdown.move(mv.name)?.volatileStatus {
                return "지속 상태를 걸지만 구현되지 않음 (\(vs))"
            }
            if Showdown.move(mv.name)?.hasCustomCode == true {
                return "Showdown 이 코드로 처리하는 변화기 (개별 구현 필요)"
            }
            return "효과가 데이터에 없는 변화기"
        }
        if Showdown.move(mv.name)?.nonstandard != nil {
            return "이 세대에 없는 기술 (표시만)"
        }
        return "위력·효과가 모두 비어 있음"
    }
}
