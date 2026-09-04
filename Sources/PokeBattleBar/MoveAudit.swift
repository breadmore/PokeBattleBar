import Foundation

/// 기술 효과 감사.
///
/// PokéAPI 도 Showdown 도 **구조화해 주지 않는** 효과가 있다. Showdown 은
/// 그런 기술에 코드(`onHit` 등)를 쓰고, 우리 데이터에는 `cc: 1` 로만 남는다.
/// 잠자기(회복+자신 잠듦), 저주(고스트면 HP 절반), 솔라빔(모으는 턴),
/// 파괴광선(다음 턴 못 움직임)이 전부 이 부류였다.
///
/// 그래서 하나씩 발견하는 대신 **목록을 뽑는다.** 실제로 배틀에 나올 수 있는
/// 기술(우리 로스터 종이 배울 수 있는 것) 중에서, 효과가 코드로만 있고
/// 우리가 구현하지 않은 것을 전부 보여준다.
enum MoveAudit {

    /// **행동 검증이 있는** 기술 (`--scriptedtest` 가 실제로 배틀을 돌려 확인한다).
    ///
    /// 예전에는 여기에 기억으로 100개가 넘게 적어놨는데, 확인해보니 대부분
    /// 코드에 흔적조차 없었다. 그래서 이제는 **테스트가 있는 것만** 적는다.
    static let verified: Set<String> = [
        "rest", "curse", "bellydrum", "substitute", "painsplit",
        "soak", "trickortreat", "forestscurse", "reflecttype",
        "conversion", "conversion2",
        // 2턴 / 반동은 플래그로 일반화해 처리하고 솔라빔·땅속·파괴광선으로 검증한다
        "solarbeam", "dig", "hyperbeam",
        // 앙코르 묶음
        "encore", "yawn", "stockpile", "swallow", "spitup",
        "magnetrise", "meanlook", "block", "spiderweb",
        // 연속으로 쓰면 세지는 기술
        "furycutter", "rollout", "iceball", "echoedvoice",
        // 화면
        "reflect", "lightscreen", "auroraveil", "brickbreak", "psychicfangs",
        // 턴을 넘나드는 것
        "outrage", "thrash", "petaldance", "ragingfury",
        "futuresight", "doomdesire", "taunt", "focusenergy", "destinybond",
        // 위력이 상황에 따라 바뀌는 것
        "return", "frustration", "gyroball", "electroball", "flail", "reversal",
        "wringout", "crushgrip", "psywave",
        // 원시회귀
        "groudonprimal", "kyogreprimal",
        // 지속 상태
        "endure", "imprison", "aquaring", "minimize", "gastroacid",
        "charge", "powertrick", "attract",
        // 일격필살 · 상대 HP 기반
        "horndrill", "fissure", "sheercold", "guillotine",
        "superfang", "endeavor",
        // 마지막 묶음
        "smackdown", "thousandarrows", "torment", "disable", "defensecurl",
    ]

    /// PokeAPI 가 효과를 구조화해 줘서 **일반 경로로 처리되는** 기술.
    /// 손으로 구현할 필요가 없다 — 감사에서 "남았다" 고 세면 안 된다.
    static let handledByData: Set<String> = [
        "swagger",      // 혼란 + 상대 공격 +2 (둘 다 데이터에 있다)
        "flatter",      // 혼란 + 상대 특공 +1
        "confuseray", "supersonic", "sweetkiss", "teeterdance",  // 혼란
        "minimize",     // 회피 +2
        "dragoncheer",  // 더블 전용 (아군 급소율) — 1대1 에서는 해당 없음
    ]

    /// 데이터로 일반화해 처리하는 기술 — 이름별 구현이 아니라 **한 경로**가 담당한다.
    /// (그래서 코드에서 이름을 찾아도 나오지 않는다)
    static let genericMechanism: Set<String> = [
        // PokéAPI 가 turn_range 를 주는 조임 기술 — trapTurns 한 경로가 처리한다
        "bind", "wrap", "firespin", "whirlpool", "sandtomb", "magmastorm",
        "infestation", "clamp", "snaptrap", "thundercage",
        // Showdown 의 selfdestruct
        "explosion", "selfdestruct", "finalgambit", "mistyexplosion",
        // Showdown 의 selfSwitch
        "uturn", "voltswitch", "flipturn", "partingshot", "batonpass",
        // Showdown 의 charge / recharge 플래그
        "solarblade", "fly", "bounce", "dive", "skyattack", "phantomforce",
        "meteorbeam", "blastburn", "frenzyplant", "gigaimpact", "hydrocannon",
        // 고정 데미지 (specialDamage 표)
        "seismictoss", "nightshade", "sonicboom", "dragonrage",
        // 손가락흔들기 (metronomePool)
        "metronome",
        // 방어 계열 (MoveFlags.isProtect)
        "protect", "detect",
    ]

    static var implemented: Set<String> {
        verified.union(genericMechanism).union(handledByData)
    }

    /// 1대1 에서는 의미가 없어 구현하지 않는 것 (미구현이 아니라 해당 없음)
    static let notApplicable: Set<String> = [
        // 더블/트리플 전용
        "helpinghand", "followme", "ragepowder", "allyswitch", "aromaticmist",
        "craftyshield", "matblock", "quash", "afteryou", "spotlight",
        "coaching", "decorate", "junglehealing", "lifedew", "healpulse",
        // 교체가 없거나 의미 없는 것
        "whirlwind", "roar", "dragontail", "circlethrow", "teleport",
        // 야생/스토리 전용
        "splash", "celebrate", "holdhands", "happyhour",
    ]

    static func run(verbose: Bool) async -> Bool {
        print("=== 기술 효과 감사 ===\n")
        var ok = true

        // 실제로 배틀에 나올 수 있는 기술만 본다 — 우리 로스터 종의 학습 기술
        let roster: [Int]
        if let state = try? CompanionStore.load() {
            roster = RosterSlot.roster(from: state).map(\.speciesID)
        } else {
            roster = [143, 94, 65, 151, 317, 555, 479, 351, 386, 137, 87, 6]
        }

        var pool: Set<String> = []
        var speciesSeen = 0
        for id in Set(roster) {
            guard let sp = try? await PokeAPI.shared.species(id) else { continue }
            speciesSeen += 1
            pool.formUnion(sp.learnableMoves)
        }
        print("  표본 \(speciesSeen)종이 배울 수 있는 기술: \(pool.count)개\n")
        guard pool.count > 200 else {
            print("  ✗ 표본이 너무 작습니다 (\(pool.count)개)")
            return false
        }

        // Showdown 이름은 하이픈이 없다 — 역매핑이 필요하다
        var chargeMoves: [String] = []
        var rechargeMoves: [String] = []
        var codeOnly: [String] = []
        var unknownToShowdown: [String] = []

        for name in pool.sorted() {
            let id = Showdown.id(fromPokeAPI: name)
            guard let sm = Showdown.move(name) else {
                unknownToShowdown.append(name)
                continue
            }
            guard sm.isUsable else { continue }
            if sm.isCharge { chargeMoves.append(name) }
            if sm.mustRecharge { rechargeMoves.append(name) }
            if sm.hasCustomCode,
               !implemented.contains(id), !notApplicable.contains(id),
               !sm.isCharge, !sm.mustRecharge {
                codeOnly.append(name)
            }
        }

        print("-- 2턴 기술 (모으는 턴) --")
        print("  \(chargeMoves.count)개: \(chargeMoves.prefix(12).joined(separator: ", "))"
              + (chargeMoves.count > 12 ? " …" : ""))
        ok = show(!chargeMoves.isEmpty, "모으는 기술을 데이터에서 찾을 수 있다") && ok

        print("\n-- 다음 턴 못 움직이는 기술 --")
        print("  \(rechargeMoves.count)개: \(rechargeMoves.joined(separator: ", "))")
        ok = show(!rechargeMoves.isEmpty, "반동 기술을 데이터에서 찾을 수 있다") && ok

        print("\n-- 효과가 코드로만 있고 우리가 구현하지 않은 기술 --")
        if codeOnly.isEmpty {
            print("  없음")
        } else {
            for n in codeOnly { print("  · \(n)") }
        }
        print("  총 \(codeOnly.count)개 / 후보 \(pool.count)개")

        if !unknownToShowdown.isEmpty && verbose {
            print("\n-- Showdown 에서 못 찾은 이름 (\(unknownToShowdown.count)개) --")
            for n in unknownToShowdown.prefix(20) { print("  · \(n)") }
        }

        // 이 감사는 **목록을 보여주는 것이 목적**이라 개수로 실패시키지 않는다.
        // 다만 구현 목록에 적어놓고 실제로는 없는 기술이 있으면 그건 거짓이다.
        // MARK: 추천 도구를 실제로 적용할 수 있는가
        //
        // 추천 세팅이 알려주는 도구가 우리 도구 목록에 없으면 조용히 넘어간다.
        // "실전 추천"을 눌렀는데 도구만 안 바뀌는 이유가 그것이다.
        // MARK: 위력이 없는 공격기 — 데이터가 null 이면 데미지가 0 이 된다
        //
        // PokéAPI 는 위력이 상황에 따라 바뀌는 기술을 power: null 로 준다
        // (은혜갚기·자이로볼·풀묶기 …). 계산에서 0 이 되어 **아무 데미지도
        // 들어가지 않는다.** 어떤 기술이 그런지 목록으로 본다.
        print("\n-- 위력이 없는 공격기 --")
        var nilPower: [(String, String)] = []
        for name in pool.sorted() {
            guard let mv = try? await PokeAPI.shared.move(name) else { continue }
            guard mv.damageClass != .status else { continue }     // 변화기는 위력이 없어도 정상
            guard mv.power == nil else { continue }
            guard mv.specialDamage == .none else { continue }     // 고정 데미지는 따로 처리한다
            nilPower.append((mv.display, name))
        }
        for (ko, id) in nilPower { print("  · \(ko)  (\(id))") }
        print("  총 \(nilPower.count)개")

        print("\n-- 추천 도구를 적용할 수 있는가 --")
        var wanted: [String: Int] = [:]
        var appliable = 0, total = 0
        for id in Set(roster) {
            guard let sp = try? await PokeAPI.shared.species(id),
                  let rec = Showdown.set(forSpeciesName: sp.name),
                  let want = rec.item else { continue }
            total += 1
            await ItemCatalog.shared.loadAll()
            let avail = await ItemCatalog.shared.available(forSpecies: sp)
            if avail.contains(where: { $0.name == want }) { appliable += 1 }
            else { wanted[want, default: 0] += 1 }
            _ = avail
        }
        if total == 0 {
            print("  · 표본에 추천 도구가 있는 종이 없습니다")
        } else {
            print("  적용 가능 \(appliable)/\(total)종")
            if !wanted.isEmpty {
                print("  목록에 없어서 적용 못 하는 도구:")
                for (n, c) in wanted.sorted(by: { $0.value > $1.value }) {
                    print("    · \(n) (\(c)종)")
                }
            }
            ok = show(appliable == total, "추천 도구를 전부 적용할 수 있다",
                      "\(appliable)/\(total)") && ok
        }

        print("\n-- 규칙으로 도구를 추천할 수 있는가 --")
        await ItemCatalog.shared.loadAll()
        var picked = 0, tried = 0
        for id in Set(roster).sorted() {
            guard let sp = try? await PokeAPI.shared.species(id) else { continue }
            tried += 1
            let avail = await ItemCatalog.shared.available(forSpecies: sp)
            let recMoves = Showdown.set(forSpeciesName: sp.name)?.movePool ?? []
            var defs: [MoveDef] = []
            for n in recMoves.prefix(4) {
                if let m = try? await PokeAPI.shared.move(n) { defs.append(m) }
            }
            if let p = ItemAdvice.recommend(species: sp, moves: defs,
                                            available: avail, fullyEvolved: true) {
                picked += 1
                let name = avail.first { $0.name == p.itemName }?.display ?? p.itemName
                print("  · \(sp.display) → \(name) — \(p.reason)")
            } else {
                print("  · \(sp.display) → 추천 없음 (고를 수 있는 도구 \(avail.count)개)")
            }
        }
        ok = show(picked == tried, "모든 종에 도구를 추천할 수 있다", "\(picked)/\(tried)") && ok

        print("\n-- 구현 목록이 실제 기술인가 --")
        var bogus: [String] = []
        for id in implemented where Showdown.move(id) == nil { bogus.append(id) }
        ok = show(bogus.isEmpty, "구현했다고 적은 기술이 모두 존재한다",
                  bogus.isEmpty ? "\(implemented.count)개" : "\(bogus)") && ok

        print(ok ? "\n✓ 통과" : "\n✗ 실패 항목 있음")
        return ok
    }

    private static func show(_ c: Bool, _ label: String, _ detail: String = "") -> Bool {
        print("  \(c ? "✓" : "✗") \(label)\(detail.isEmpty ? "" : "  (\(detail))")")
        return c
    }
}
