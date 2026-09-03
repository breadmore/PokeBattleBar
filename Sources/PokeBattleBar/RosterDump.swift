import Foundation

/// `PokeBattleBar --roster`
/// 지금 내 도감이 배틀에서 어떻게 보이는지 출력한다.
/// UI 를 열지 않고도 자격·기술·쓸 수 있는 도구를 확인할 수 있다.
enum RosterDump {
    /// AppModel.itemReadiness 와 같은 규칙 (UI 없이 확인하기 위한 복제)
    static func probeReadiness(item: ItemDef, species sp: SpeciesDef,
                               moves: [MoveDef]) -> ItemReadiness {
        switch item.kind {
        case .megaStone(let form):
            guard sp.megaForms.contains(form) else {
                return ItemReadiness(ok: false, headline: "메가진화 불가",
                                     detail: "\(sp.display)의 스톤이 아닙니다")
            }
            let label = form.hasSuffix("-x") ? "메가 X" : (form.hasSuffix("-y") ? "메가 Y" : "메가")
            return ItemReadiness(ok: true, headline: "메가진화 가능", detail: "\(label) 로 진화")
        case .dynamaxBand:
            return ItemReadiness(ok: true, headline: "다이맥스 가능",
                                 detail: "일반 다이맥스 전용 (거다이맥스는 다이버섯)")
        case .maxMushroom:
            guard sp.canGigantamax else {
                return ItemReadiness(ok: false, headline: "거다이맥스 불가",
                                     detail: "\(sp.display)는 거다이맥스 폼이 없습니다")
            }
            return ItemReadiness(ok: true, headline: "거다이맥스 가능",
                                 detail: "전용기 " + (GMaxMove.forSpecies(sp.id)?.ko ?? "있음"))
        case .zCrystalType(let t):
            let match = moves.filter { $0.damageClass != .status && $0.isDamaging && $0.type == t }
            guard !match.isEmpty else {
                return ItemReadiness(ok: false, headline: "Z기술 불가",
                                     detail: "\(t.ko)타입 공격기가 없습니다")
            }
            return ItemReadiness(ok: true, headline: "Z기술 가능",
                                 detail: match.map(\.display).joined(separator: ", "))
        case .zCrystalSignature(let sid):
            guard sid == sp.id else {
                return ItemReadiness(ok: false, headline: "Z기술 불가",
                                     detail: "\(sp.display) 전용이 아닙니다")
            }
            let atk = moves.filter { $0.damageClass != .status && $0.isDamaging }
            guard !atk.isEmpty else {
                return ItemReadiness(ok: false, headline: "Z기술 불가", detail: "공격기가 없습니다")
            }
            return ItemReadiness(ok: true, headline: "전용 Z기술 가능", detail: "타입 제한 없음")
        default:
            return ItemReadiness(ok: true, headline: "상시 효과",
                                 detail: item.shortEffect.isEmpty ? item.display : item.shortEffect)
        }
    }

    static func run() async -> Bool {
        print("=== 내 로스터 ===\n")
        let state: CompanionState
        do { state = try CompanionStore.load() }
        catch {
            print("✗ PokeTokenBar 상태 파일을 읽을 수 없습니다: \(error.localizedDescription)")
            return false
        }
        let roster = RosterSlot.roster(from: state)
        guard !roster.isEmpty else { print("포켓몬이 없습니다."); return false }

        await ItemCatalog.shared.loadAll()
        print("총 \(roster.count)마리 (도감 \(state.dex.count) + 진행중 \(state.active == nil ? 0 : 1))\n")

        for slot in roster {
            guard let sp = try? await PokeAPI.shared.species(slot.speciesID) else { continue }
            let statTotal = Stat.allCases.reduce(0) { $0 + sp.base($1) }
            let origin = slot.origin == .active ? "진행중" : "도감"
            print("── \(sp.display)  (#\(sp.id), \(origin))")
            print("   타입 \(sp.types.map(\.ko).joined(separator: "/"))  종족값 합 \(statTotal)"
                  + "  성격 \(Nature.named(slot.nature).ko)"
                  + (slot.isShiny ? "  ✨샤이니" : "")
                  + (slot.fullyEvolved ? "" : "  (진화 미완성)"))

            // 특수 변신 자격
            var badges: [String] = ["◉ 다이맥스"]
            if sp.canMega {
                badges.append("✦ 메가" + (sp.megaForms.count > 1 ? " X/Y" : ""))
            }
            if sp.canGigantamax { badges.append("◈ 거다이맥스") }
            let items = await ItemCatalog.shared.available(forSpecies: sp)
            let sigZ = items.compactMap { d -> String? in
                if case .zCrystalSignature = d.kind { return d.display }
                return nil
            }
            if !sigZ.isEmpty { badges.append("⚡ 전용Z(\(sigZ.joined(separator: ",")))") }
            print("   자격: \(badges.joined(separator: "  "))")

            // 특성
            let abils = await AbilityCatalog.shared.abilities(for: sp)
            let abilText = abils.map {
                $0.display + ($0.isHidden ? "(숨겨진)" : "") + ($0.isImplemented ? "" : "·표시만")
            }.joined(separator: ", ")
            print("   특성: \(abilText.isEmpty ? "-" : abilText)")

            // 기술
            let moves = await MovesetStore.shared.moveset(for: slot, species: sp)
            print("   기술: " + moves.map {
                "\($0.display)(\($0.type.ko)/\($0.power.map(String.init) ?? "-"))"
            }.joined(separator: ", "))

            // 쓸 수 있는 변신 도구
            let transform = items.filter(\.isTransformItem)
            let grouped = Dictionary(grouping: transform, by: \.group)
            for (g, list) in grouped.sorted(by: { $0.key < $1.key }) {
                print("   \(g): " + list.map(\.display).sorted().joined(separator: ", "))
            }
            print("   배틀 도구 \(items.count - transform.count)종 선택 가능")
            print()
        }

        // 도구를 끼웠을 때 어떻게 판정되는지 — UI 에 나오는 것과 같은 로직이다
        print("── 도구 착용 시 판정 (UI 표시와 동일) ──")
        let probe = ["charizardite-x", "alakazite", "dynamax-band", "max-mushrooms",
                     "normalium-z--held", "firium-z--held", "snorlium-z--held",
                     "mewnium-z--held", "leftovers"]
        for slot in roster {
            guard let sp = try? await PokeAPI.shared.species(slot.speciesID) else { continue }
            print("\n  \(sp.display)")
            for name in probe {
                guard let item = await ItemCatalog.shared.item(name) else { continue }
                // 그 종에게 목록에 노출되는 도구만 검사한다
                let avail = await ItemCatalog.shared.available(forSpecies: sp)
                let visible = avail.contains { $0.name == name }
                guard visible else { continue }
                let r = probeReadiness(item: item, species: sp,
                                       moves: await MovesetStore.shared.moveset(for: slot, species: sp))
                print("    \(r.ok ? "✓" : "✗") \(item.display.padding(toLength: 14, withPad: " ", startingAt: 0))"
                      + "\(r.headline)  — \(r.detail)")
            }
        }
        print()

        // 요약
        var megaCount = 0, gmaxCount = 0, sigZCount = 0
        for slot in roster {
            guard let sp = try? await PokeAPI.shared.species(slot.speciesID) else { continue }
            if sp.canMega { megaCount += 1 }
            if sp.canGigantamax { gmaxCount += 1 }
            if ItemCatalog.signatureZ.values.contains(sp.id) { sigZCount += 1 }
        }
        print("── 요약 ──")
        print("  메가진화 가능: \(megaCount)마리")
        print("  거다이맥스 가능: \(gmaxCount)마리")
        print("  전용 Z기술 보유: \(sigZCount)마리")
        print("  다이맥스: \(roster.count)마리 전원 (종족 제한 없음)")
        return true
    }
}
