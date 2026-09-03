import Foundation

/// 지닌 도구 추천.
///
/// **왜 규칙으로 정하는가**: gen9 랜덤배틀 세팅 데이터에는 기술과 특성만 있고
/// 도구가 없다. Showdown 은 팀을 만들 때 알고리즘으로 도구를 고르기 때문이다.
/// 그래서 여기서도 종족값·기술 구성으로 정한다. Showdown 의 판단 기준을
/// 그대로 옮긴 것이 아니라, **같은 생각을 단순화한 규칙**이다.
enum ItemAdvice {

    struct Pick {
        var itemName: String
        /// 왜 이걸 골랐는지 — 화면에 그대로 보여준다
        var reason: String
    }

    /// 추천 도구 하나. 고를 수 없으면 nil.
    ///
    /// - Parameters:
    ///   - species: 종족값·타입
    ///   - moves: 지금 이 개체가 든 기술 (없으면 추천 기술)
    ///   - available: 이 개체에게 실제로 끼울 수 있는 도구
    ///   - fullyEvolved: 진화가 끝났는가 (미진화면 진화의휘석)
    /// - Parameter taken: 팀원이 이미 든 도구 이름. 같은 도구를 두 개 주지 않는다.
    /// - Parameter claimedSlots: 팀원이 이미 차지한 변신 슬롯 (메가진화 등).
    ///   같은 슬롯이 겹치면 한쪽은 반드시 낭비되므로 피한다.
    static func recommend(species sp: SpeciesDef,
                          moves: [MoveDef],
                          available: [ItemDef],
                          fullyEvolved: Bool,
                          taken: Set<String> = [],
                          claimedSlots: Set<String> = []) -> Pick? {
        let usable = available.filter { it in
            if taken.contains(it.name) { return false }
            if let slot = it.transformSlot, claimedSlots.contains(slot) { return false }
            return true
        }
        let have = Set(usable.map(\.name))
        func pick(_ name: String, _ reason: String) -> Pick? {
            have.contains(name) ? Pick(itemName: name, reason: reason) : nil
        }

        let hp = sp.baseStats[.hp] ?? 0
        let def = sp.baseStats[.defense] ?? 0
        let spd = sp.baseStats[.spDefense] ?? 0
        let atk = sp.baseStats[.attack] ?? 0
        let spa = sp.baseStats[.spAttack] ?? 0
        let speed = sp.baseStats[.speed] ?? 0
        let bulk = hp + def + spd

        let damaging = moves.filter { ($0.power ?? 0) > 0 }
        let physical = damaging.filter { $0.damageClass == .physical }
        let special = damaging.filter { $0.damageClass == .special }
        let hasRecovery = moves.contains { $0.healingPercent > 0 || $0.name == "rest" }

        // 1) 미진화 — 진화의휘석이 방어·특방을 1.5배로 올린다. 다른 무엇보다 크다.
        if !fullyEvolved, let p = pick("eviolite", "미진화라서 방어·특방이 1.5배가 됩니다") {
            return p
        }

        // 2) 튼튼하고 회복기가 있으면 오래 버티는 쪽이 낫다.
        //    **구애보다 먼저 본다** — 잠자기를 쓰는 잠만보에게 구애머리띠를
        //    끼우면 잠자기를 못 쓰게 되어 오히려 손해다.
        if bulk >= 300, hasRecovery,
           let p = pick("leftovers", "튼튼하고(종족값 \(bulk)) 회복기가 있어 오래 버티는 편이 낫습니다") {
            return p
        }

        // 3) 변화기가 있으면 구애를 끼울 수 없다 (그 기술만 쓰게 된다)
        let hasStatus = moves.contains { $0.damageClass == .status }

        // 4) 공격기가 하나뿐이고 변화기도 없으면 구애로 그 한 방을 키운다
        if damaging.count == 1, !hasStatus, let only = damaging.first {
            if only.damageClass == .physical, atk >= 90,
               let p = pick("choice-band", "공격기가 \(only.display) 하나뿐이라 구애머리띠가 손해가 없습니다") {
                return p
            }
            if only.damageClass == .special, spa >= 90,
               let p = pick("choice-specs", "공격기가 \(only.display) 하나뿐이라 구애안경이 손해가 없습니다") {
                return p
            }
        }

        // 5) 빠르지만 약한 몸 — 기합의띠로 한 번은 버틴다
        if speed >= 95, bulk <= 250,
           let p = pick("focus-sash", "빠르지만 잘 버티지 못해(종족값 \(bulk)) 한 번은 살아남습니다") {
            return p
        }

        // 6) 특수를 잘 받아내는 몸 + 변화기 없음 → 돌격조끼
        if spd >= 90, hp >= 90, !hasStatus, !damaging.isEmpty,
           let p = pick("assault-vest", "특방이 좋고 변화기가 없어 특수 공격을 더 잘 받아냅니다") {
            return p
        }

        // 7) 튼튼하면 먹다남은음식
        if bulk >= 320, let p = pick("leftovers", "튼튼해서(종족값 \(bulk)) 조금씩 회복하는 편이 좋습니다") {
            return p
        }

        // 8) 공격형 — 공격기가 여러 개면 생명의구슬로 전부 키운다
        if damaging.count >= 2, max(atk, spa) >= 95,
           let p = pick("life-orb", "공격기가 여러 개라 구애보다 생명의구슬이 낫습니다") {
            return p
        }
        if physical.count > special.count, atk >= 100, !hasStatus,
           let p = pick("choice-band", "물리 공격이 주력이라 구애머리띠로 위력을 올립니다") {
            return p
        }
        if special.count > physical.count, spa >= 100, !hasStatus,
           let p = pick("choice-specs", "특수 공격이 주력이라 구애안경으로 위력을 올립니다") {
            return p
        }

        // 9) 마지막 — 공격 쪽이 높으면 위력, 아니면 버티기
        let offense = max(atk, spa)
        if offense >= bulk / 3 {
            if let p = pick("life-orb",
                            "공격(\(offense))이 나쁘지 않아 위력을 올리는 쪽을 고릅니다") { return p }
            if let p = pick("expert-belt",
                            "공격(\(offense))이 나쁘지 않아 효과가 굉장할 때를 노립니다") { return p }
        }
        if let p = pick("leftovers",
                        "특별히 맞는 도구가 없어 조금씩 회복하는 쪽을 고릅니다") { return p }
        if let p = pick("life-orb", "고를 수 있는 것 중에 위력을 올리는 편이 낫습니다") { return p }
        return nil
    }
}
