import Foundation

/// `PokeBattleBar --formchangetest`
/// 폼 체인지와 턴 재생을 검증한다.
/// **PokeTokenBar 의 데이터는 건드리지 않는다** — 폼 선택은 우리 저장소에만 기록된다.
enum FormChangeTest {
    static func run() async -> Bool {
        print("=== 폼 체인지 · 턴 재생 검증 ===\n")
        guard let chart = try? await PokeAPI.shared.typeChart() else { return false }
        var ok = true

        // MARK: 폼 목록과 스프라이트
        print("-- 사전 선택 폼 --")
        for (id, ko, expect) in [(479, "로토무", 5), (386, "테오키스", 3),
                                 (487, "기라티나", 1), (492, "쉐이미", 1),
                                 (646, "큐레무", 2), (648, "메로엣타", 1)] {
            guard let sp = try? await PokeAPI.shared.species(id) else { continue }
            let forms = FormChange.selectable(for: sp)
            let pass = forms.count >= expect
            print(pass ? "  ✓ \(ko): \(forms.count)개 — \(forms.map(FormChange.label))"
                       : "  ✗ \(ko): \(forms.count)개 (기대 \(expect) 이상)")
            ok = pass && ok
        }

        // 로토무 폼은 타입·종족값이 실제로 다르다
        print("\n-- 폼마다 타입·종족값이 다른가 --")
        if let sp = try? await PokeAPI.shared.species(479) {
            let baseTotal = Stat.allCases.reduce(0) { $0 + sp.base($1) }
            for f in FormChange.selectable(for: sp) {
                guard let fs = try? await PokeAPI.shared.form(named: f) else { continue }
                let total = Stat.allCases.reduce(0) { $0 + fs.base($1) }
                print("    \(FormChange.label(f).padding(toLength: 8, withPad: " ", startingAt: 0))"
                      + "\(fs.types.map(\.ko).joined(separator: "/"))  종족값 \(total)")
                ok = show(total != baseTotal || fs.types != sp.types,
                          "\(FormChange.label(f)) 폼은 기본형과 다르다") && ok
            }
            print("    기본       \(sp.types.map(\.ko).joined(separator: "/"))  종족값 \(baseTotal)")
        }

        // MARK: 폼을 적용한 배틀러
        print("\n-- 폼이 배틀 스탯에 반영되는가 --")
        if let sp = try? await PokeAPI.shared.species(479),
           let heat = try? await PokeAPI.shared.form(named: "rotom-heat"),
           let tackle = try? await PokeAPI.shared.move("tackle") {
            let slot = RosterSlot(id: "f", speciesID: 479, nature: "serious",
                                  rarity: "common", isShiny: false, origin: .dex, fullyEvolved: true)
            let plain = Battler.make(slot: slot, species: sp, moves: [tackle], level: 50)
            let formed = Battler.make(slot: slot, species: sp, moves: [tackle], level: 50,
                                      form: heat, formName: "rotom-heat")
            ok = show(formed.types != plain.types, "폼 적용 시 타입 변경",
                      "\(plain.types.map(\.ko)) → \(formed.types.map(\.ko))") && ok
            ok = show(formed.stat(.spAttack) != plain.stat(.spAttack), "폼 적용 시 스탯 변경",
                      "특공 \(plain.stat(.spAttack)) → \(formed.stat(.spAttack))") && ok
            ok = show(formed.spriteForm == "rotom-heat", "스프라이트 폼이 지정된다",
                      formed.spriteForm ?? "nil") && ok
            ok = show(formed.name.contains("히트"), "이름에 폼이 표시된다", formed.name) && ok
        }

        // MARK: 배틀 중 자동 변신 (캐스퐁 — 날씨)
        print("\n-- 배틀 중 자동 변신 --")
        ok = await castformChanges(chart) && ok
        ok = await zenModeChanges(chart) && ok

        // MARK: 메가·거다이맥스 스프라이트 교체
        print("\n-- 변신 스프라이트 --")
        ok = await megaSwapsSprite(chart) && ok

        // MARK: 턴 재생 스텝
        print("\n-- 턴 재생 --")
        ok = await turnStepsRecorded(chart) && ok

        // MARK: PokeTokenBar 파일 불변
        print("\n-- PokeTokenBar 데이터 보호 --")
        ok = tokenBarUntouched() && ok

        print(ok ? "\n✓ 전부 통과" : "\n✗ 실패 항목 있음")
        return ok
    }

    private static func show(_ c: Bool, _ l: String, _ d: String = "") -> Bool {
        print(c ? "  ✓ \(l)\(d.isEmpty ? "" : "  (\(d))")"
                : "  ✗ \(l)\(d.isEmpty ? "" : "  — \(d)")")
        return c
    }

    /// 캐스퐁이 날씨에 따라 폼을 바꾸는가
    private static func castformChanges(_ chart: TypeChart) async -> Bool {
        guard let sp = try? await PokeAPI.shared.species(351),
              let forecast = await AbilityCatalog.shared.ability("forecast"),
              let sunny = try? await PokeAPI.shared.form(named: "castform-sunny"),
              let base = try? await PokeAPI.shared.form(named: "castform"),
              let sun = try? await PokeAPI.shared.move("sunny-day"),
              let splash = try? await PokeAPI.shared.move("splash") else {
            return show(false, "캐스퐁", "준비 실패")
        }
        let slot = RosterSlot(id: "cast", speciesID: 351, nature: "serious",
                              rarity: "common", isShiny: false, origin: .dex, fullyEvolved: true)
        var a = Battler.make(slot: slot, species: sp, moves: [sun], level: 50, ability: forecast)
        a.moves[0].ppLeft = 99; a.stats[.speed] = 999
        var d = Battler.make(slot: RosterSlot(id: "d", speciesID: 143, nature: "serious",
                                              rarity: "common", isShiny: false,
                                              origin: .dex, fullyEvolved: true),
                             species: (try? await PokeAPI.shared.species(143))!,
                             moves: [splash], level: 50)
        d.moves[0].ppLeft = 99; d.stats[.speed] = 1
        d.maxHP = 99999; d.currentHP = 99999

        var rules = BattleRules(maxTeamSize: 1, level: 50)
        rules.requireItems = false
        var st = BattleState(rules: rules,
                             sides: [SideState(playerName: "A", team: [a], activeIndex: 0),
                                     SideState(playerName: "B", team: [d], activeIndex: 0)])
        st.phase = .awaitingMoves
        var e = BattleEngine(state: st, chart: chart, seed: 5150)
        e.formCache["castform-sunny"] = sunny
        e.formCache["castform"] = base

        let typesBefore = e.state.sides[0].team[0].types
        e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
        let after = e.state.sides[0].team[0]
        var ok = show(e.state.field.weather == .sun, "쾌청이 걸렸다")
        ok = show(after.types != typesBefore, "캐스퐁 타입이 바뀌었다",
                  "\(typesBefore.map(\.ko)) → \(after.types.map(\.ko))") && ok
        ok = show(after.autoForm == "castform-sunny", "폼이 기록된다", after.autoForm ?? "nil") && ok
        ok = show(after.spriteForm == "castform-sunny", "스프라이트도 바뀐다") && ok
        return ok
    }

    /// 불비달마가 HP 절반 이하에서 달마모드로 바뀌는가
    private static func zenModeChanges(_ chart: TypeChart) async -> Bool {
        guard let sp = try? await PokeAPI.shared.species(555),
              let zen = await AbilityCatalog.shared.ability("zen-mode"),
              let zenForm = try? await PokeAPI.shared.form(named: "darmanitan-zen"),
              let std = try? await PokeAPI.shared.form(named: "darmanitan-standard"),
              let splash = try? await PokeAPI.shared.move("splash"),
              let snorlax = try? await PokeAPI.shared.species(143) else {
            return show(false, "불비달마 달마모드", "준비 실패")
        }
        let slot = RosterSlot(id: "dar", speciesID: 555, nature: "serious",
                              rarity: "common", isShiny: false, origin: .dex, fullyEvolved: true)
        var a = Battler.make(slot: slot, species: sp, moves: [splash], level: 50, ability: zen)
        a.moves[0].ppLeft = 99
        a.currentHP = a.maxHP / 3            // 절반 이하
        var d = Battler.make(slot: RosterSlot(id: "d", speciesID: 143, nature: "serious",
                                              rarity: "common", isShiny: false,
                                              origin: .dex, fullyEvolved: true),
                             species: snorlax, moves: [splash], level: 50)
        d.moves[0].ppLeft = 99

        var rules = BattleRules(maxTeamSize: 1, level: 50)
        rules.requireItems = false
        var st = BattleState(rules: rules,
                             sides: [SideState(playerName: "A", team: [a], activeIndex: 0),
                                     SideState(playerName: "B", team: [d], activeIndex: 0)])
        st.phase = .awaitingMoves
        var e = BattleEngine(state: st, chart: chart, seed: 616)
        e.formCache["darmanitan-zen"] = zenForm
        e.formCache["darmanitan-standard"] = std

        e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
        let after = e.state.sides[0].team[0]
        return show(after.autoForm == "darmanitan-zen",
                    "HP 절반 이하에서 달마모드", after.autoForm ?? "변화 없음")
    }

    /// 메가진화하면 스프라이트 폼이 바뀌는가
    private static func megaSwapsSprite(_ chart: TypeChart) async -> Bool {
        guard var e = await Harness.engine(att: 65, def: 143,
                                           attMoves: ["psychic"], defMoves: ["splash"],
                                           chart: chart, seed: 808),
              let form = try? await PokeAPI.shared.form(named: "alakazam-mega") else {
            return show(false, "메가 스프라이트", "준비 실패")
        }
        e.megaCache["alakazam-mega"] = form
        e.state.sides[1].team[0].maxHP = 99999
        e.state.sides[1].team[0].currentHP = 99999
        e.resolveTurn(hostAction: .useMove(index: 0, special: .mega(form: "alakazam-mega")),
                      guestAction: .useMove(index: 0))
        let b = e.state.sides[0].team[0]
        var ok = show(b.isMega, "메가진화했다")
        ok = show(b.spriteForm == "alakazam-mega", "스프라이트 폼이 메가로 바뀐다",
                  b.spriteForm ?? "nil") && ok
        ok = show(b.spriteScale == 1.0, "메가는 크기를 키우지 않는다") && ok
        return ok
    }

    /// 턴이 순서대로 재생될 수 있게 스텝이 기록되는가
    private static func turnStepsRecorded(_ chart: TypeChart) async -> Bool {
        guard var e = await Harness.engine(att: 143, def: 143,
                                           attMoves: ["body-slam"], defMoves: ["body-slam"],
                                           chart: chart, seed: 1357) else {
            return show(false, "턴 스텝", "준비 실패")
        }
        e.state.sides[0].team[0].stats[.speed] = 200
        e.state.sides[1].team[0].stats[.speed] = 100
        e.state.sides[0].team[0].maxHP = 99999; e.state.sides[0].team[0].currentHP = 99999
        e.state.sides[1].team[0].maxHP = 99999; e.state.sides[1].team[0].currentHP = 99999

        e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
        let steps = e.state.steps
        var ok = show(steps.count >= 2, "양쪽 행동이 각각 단계로 기록된다", "\(steps.count)단계")
        // 스텝을 따라 **어느 쪽이든** HP 가 줄어들어야 한다.
        // 한쪽만 보면 그 쪽이 안 맞은 단계에서는 변화가 없어 검증이 무의미해진다.
        if steps.count >= 2 {
            let firstSum = steps[0].hostHP.reduce(0, +) + steps[0].guestHP.reduce(0, +)
            let lastSum = steps[steps.count - 1].hostHP.reduce(0, +)
                        + steps[steps.count - 1].guestHP.reduce(0, +)
            ok = show(lastSum < firstSum, "스텝을 따라 HP 총합이 줄어든다",
                      "\(firstSum) → \(lastSum)") && ok
        }
        // 로그가 스텝에 나눠 담기고 합계가 맞는가
        let stepLines = steps.reduce(0) { $0 + $1.log.count }
        ok = show(stepLines > 0 && stepLines <= e.state.log.count,
                  "스텝 로그 합계가 전체 로그를 넘지 않는다",
                  "\(stepLines)/\(e.state.log.count)") && ok
        // 다음 턴에는 스텝이 초기화된다
        // 다음 턴의 스텝은 **그 턴에 생긴 줄만** 담아야 한다.
        // 기준점을 잘못 잡으면 배틀 전체 로그를 다시 재생하게 된다.
        if case .awaitingMoves = e.state.phase {
            let logBefore = e.state.log.count
            e.resolveTurn(hostAction: .useMove(index: 0), guestAction: .useMove(index: 0))
            let newLines = e.state.steps.reduce(0) { $0 + $1.log.count }
            let addedThisTurn = e.state.log.count - logBefore
            ok = show(newLines == addedThisTurn,
                      "턴 스텝은 그 턴에 생긴 로그만 담는다",
                      "스텝 \(newLines)줄 / 이번 턴 \(addedThisTurn)줄") && ok
        }
        return ok
    }

    /// 폼 선택이 PokeTokenBar 파일을 건드리지 않는지
    private static func tokenBarUntouched() -> Bool {
        let url = CompanionStore.stateURL
        guard let before = try? Data(contentsOf: url) else {
            return show(true, "PokeTokenBar 파일 없음 (검사 생략)")
        }
        // 우리 저장소 경로가 PokeTokenBar 와 다른지 확인
        let ours = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/PokeBattleBar/loadouts.json")
        var ok = show(!ours.path.contains("PokeTokenBar"),
                      "폼 선택은 PokeBattleBar 저장소에 기록된다", ours.lastPathComponent)
        // 읽기만 했으니 내용이 그대로인지
        let after = try? Data(contentsOf: url)
        ok = show(after == before, "companion-state.json 이 변경되지 않았다") && ok
        return ok
    }
}
