import Foundation

/// 기술 **작동 방식** 감사.
///
/// "바로 나가지 않는 기술", "상태·능력치를 바꾸는 기술", "반동이 있는 기술" 처럼
/// 부류별로 묶어, 우리 로스터가 쓸 수 있는 기술 중 **무엇이 처리되고 무엇이
/// 남았는지** 한 번에 본다. 하나씩 발견하지 않기 위한 것이다.
enum MechanicAudit {

    struct Group {
        var name: String
        var why: String                    // 왜 특별한가
        var supported: Bool                // 우리가 처리하는가
        var note: String                   // 어떻게 처리하는가 / 왜 아직 아닌가
        var match: (MoveDef, ShowdownMove) -> Bool
    }

    static let groups: [Group] = [
        .init(name: "모으는 턴이 있다", why: "첫 턴에 안 나간다",
              supported: true,
              note: "charge 플래그 · 메테오빔/일렉트로빔은 특공 상승 · 맑음/비/파워허브면 즉시",
              match: { _, s in s.isCharge }),

        .init(name: "다음 턴에 못 움직인다", why: "파괴광선 계열",
              supported: true, note: "recharge 플래그",
              match: { _, s in s.mustRecharge }),

        .init(name: "여러 턴 조작 불가", why: "난동부리기 — 끝나면 혼란",
              supported: true, note: "2~3턴 강제, 끝나면 혼란 (lockedmove 플래그)",
              match: { _, s in s.locksUser }),

        .init(name: "연속으로 굴러간다", why: "데구르르 — 위력이 배로",
              supported: true, note: "연속 사용 횟수로 위력 계산 (5턴 고정은 아직)",
              match: { _, s in s.rollsOn }),

        .init(name: "몇 턴 뒤에 터진다", why: "미래예지 · 파멸의소원",
              supported: true, note: "시전 시점 데미지로 예약, 2턴 뒤 발동",
              match: { m, _ in ["future-sight", "doom-desire"].contains(m.name) }),

        .init(name: "쓴 뒤 교체된다", why: "유턴 계열",
              supported: true, note: "selfSwitch — 피벗 단계로",
              match: { _, s in s.selfSwitch }),

        .init(name: "자신이 쓰러진다", why: "대폭발 · 목숨걸기",
              supported: true, note: "selfdestruct (always / ifHit 구분)",
              match: { _, s in s.selfDestruct }),

        .init(name: "반동 데미지", why: "받은 만큼 자신도 깎인다",
              supported: true, note: "PokeAPI drain 음수로 처리",
              match: { m, s in s.recoil != nil || m.drainPercent < 0 }),

        .init(name: "체력 흡수", why: "준 데미지만큼 회복",
              supported: true, note: "PokeAPI drain 양수",
              match: { m, s in (s.drain != nil) || m.drainPercent > 0 }),

        .init(name: "자신을 회복", why: "회복기",
              supported: true, note: "PokeAPI healing (잠자기는 손으로)",
              match: { m, s in m.healingPercent > 0 || s.heal != nil || m.name == "rest" }),

        .init(name: "상대 능력치를 내린다", why: "랭크 변화",
              supported: true, note: "PokeAPI stat_changes",
              match: { m, s in
                  (s.boosts?.values.contains { $0 < 0 } ?? false)
                  || m.statChanges.contains { $0.change < 0 } && !m.targetsSelf }),

        .init(name: "자신 능력치를 올린다", why: "랭크 변화",
              supported: true, note: "PokeAPI stat_changes (targetsSelf)",
              match: { m, s in
                  (s.selfBoosts?.values.contains { $0 > 0 } ?? false)
                  || m.statChanges.contains { $0.change > 0 } && m.targetsSelf }),

        .init(name: "상태이상을 건다", why: "독·화상·마비·잠듦·얼음",
              supported: true, note: "PokeAPI ailment (맹독은 별도 표)",
              match: { m, s in m.ailment != .none || s.status != nil }),

        .init(name: "상대를 묶는다", why: "조임 — 매 턴 데미지 + 교체 불가",
              supported: true, note: "PokeAPI turn_range",
              match: { m, _ in m.trapTurns != nil }),

        .init(name: "다단히트", why: "한 턴에 여러 번",
              supported: true, note: "PokeAPI min/max hits",
              match: { m, _ in (m.maxHits ?? 1) > 1 }),

        .init(name: "일격필살", why: "맞으면 즉시 쓰러진다",
              supported: true,
              note: "명중률 30 + (내 레벨 - 상대 레벨), 상대가 높으면 실패",
              match: { _, s in s.ohko }),

        .init(name: "상대를 물러나게 한다", why: "울부짖기 계열",
              supported: false, note: "1대1 에서는 의미가 없다 (해당 없음)",
              match: { _, s in s.forceSwitch }),

        .init(name: "상대에게 지속 상태", why: "앙코르·사슬묶기 등",
              supported: false,
              note: "많이 처리했다 (앙코르·저주·대타출동·도발·기충전·길동무·검은눈빛·"
                  + "전자부유·비축·하품·묶기·방어) — 아래가 남은 것",
              match: { _, s in
                  guard let v = s.volatileStatus else { return false }
                  return !["lockedmove", "rollout"].contains(v) }),
    ]

    static func run(verbose: Bool) async -> Bool {
        print("=== 기술 작동 방식 감사 ===\n")
        var ok = true

        // 우리 로스터가 배울 수 있는 기술만 본다
        let roster: [Int]
        if let state = try? CompanionStore.load() {
            roster = RosterSlot.roster(from: state).map(\.speciesID)
        } else {
            roster = [143, 94, 65, 151, 317, 555, 479, 351, 386, 137, 87, 6]
        }
        var pool: Set<String> = []
        for id in Set(roster) {
            guard let sp = try? await PokeAPI.shared.species(id) else { continue }
            pool.formUnion(sp.learnableMoves)
        }
        print("  후보 기술 \(pool.count)개\n")

        var defs: [(MoveDef, ShowdownMove)] = []
        for name in pool.sorted() {
            guard let m = try? await PokeAPI.shared.move(name),
                  let s = Showdown.move(name), s.isUsable else { continue }
            defs.append((m, s))
        }

        var unsupportedTotal = 0
        for g in groups {
            let hits = defs.filter { g.match($0.0, $0.1) }
            guard !hits.isEmpty else { continue }
            let mark = g.supported ? "✓" : "·"
            print("\(mark) \(g.name) — \(hits.count)개   [\(g.why)]")
            print("    \(g.note)")
            // 이미 손으로 구현한 기술은 남은 목록에서 뺀다 —
            // 안 그러면 끝낸 것까지 계속 "남았다" 고 나온다
            let remaining = hits.filter { m, _ in
                let id = Showdown.id(fromPokeAPI: m.name)
                return !MoveAudit.implemented.contains(id)
                    && !MoveAudit.notApplicable.contains(id)
            }
            if verbose || !g.supported {
                let names = (g.supported ? hits : remaining).map(\.0.display).sorted()
                if names.isEmpty {
                    print("    (남은 것 없음)")
                } else {
                    print("    \(names.prefix(20).joined(separator: ", "))"
                          + (names.count > 20 ? " …" : ""))
                }
            }
            if !g.supported { unsupportedTotal += remaining.count }
            print("")
        }

        print("-- 요약 --")
        let supported = groups.filter(\.supported).count
        print("  처리하는 부류 \(supported)개 / 전체 \(groups.count)개")
        print("  아직 처리하지 않는 기술 \(unsupportedTotal)개")

        ok = show(defs.count > 200, "충분한 기술을 훑었다", "\(defs.count)개") && ok
        // 이 감사는 목록이 목적이라 개수로 실패시키지 않는다
        print(ok ? "\n✓ 통과" : "\n✗ 실패 항목 있음")
        return ok
    }

    private static func show(_ c: Bool, _ l: String, _ d: String = "") -> Bool {
        print("  \(c ? "✓" : "✗") \(l)\(d.isEmpty ? "" : "  (\(d))")")
        return c
    }
}
