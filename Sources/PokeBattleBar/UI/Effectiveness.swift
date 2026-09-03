import SwiftUI

/// 기술 하나를 지금 상대에게 썼을 때의 상성 정보.
/// **상대나 내 타입이 바뀌면(메가진화 등) 자동으로 다시 계산된다** —
/// BattleState 를 읽어서 만들기 때문에 관찰 대상이 갱신되면 뷰가 다시 그려진다.
struct Effectiveness {
    var multiplier: Double        // 타입 상성 배율 (0, 0.25, 0.5, 1, 2, 4)
    var stab: Bool                // 자기 타입 일치 보너스
    var effectivePower: Int?      // 위력 × 상성 × STAB (고정 데미지 기술은 nil)
    var special: SpecialDamage

    static func compute(move: MoveDef, attacker: Battler, defenderTypes: [PType], chart: TypeChart?) -> Effectiveness {
        let mult = chart?.multiplier(attack: move.type, defenders: defenderTypes) ?? 1.0
        let stab = attacker.types.contains(move.type)
        var eff: Int?
        if let p = move.power, p > 0 {
            eff = Int((Double(p) * mult * (stab ? 1.5 : 1.0)).rounded())
        }
        return Effectiveness(multiplier: mult, stab: stab, effectivePower: eff, special: move.specialDamage)
    }

    /// 배율 라벨. nil 이면 표시할 게 없다 (등배).
    var label: String? {
        switch multiplier {
        case 0:            return "무효"
        case 0.25:         return "×¼"
        case 0.5:          return "×½"
        case 2:            return "×2"
        case 4:            return "×4"
        default:           return nil
        }
    }

    var color: Color {
        switch multiplier {
        case 0:                 return .secondary
        case ..<1:              return .blue
        case 1:                 return .secondary
        case 2:                 return .orange
        default:                return .red
        }
    }

    var verdict: String? {
        switch multiplier {
        case 0:      return "효과 없음"
        case ..<1:   return "효과 별로"
        case 1:      return nil
        default:     return "효과 굉장"
        }
    }

    /// 원작 문구. "게임보이 계승" 화면은 배수 대신 이 말로 알려준다.
    var sentence: String? {
        switch multiplier {
        case 0:      return "효과가 없는 것 같다…"
        case ..<1:   return "효과가 별로인 듯하다…"
        case 1:      return nil
        case 2:      return "효과가 굉장하다!"
        default:     return "효과가 굉장하다! (4배)"
        }
    }

    /// 고정 데미지 기술 설명
    var specialNote: String? {
        switch special {
        case .none:           return nil
        case .userCurrentHP:  return "내 남은 HP만큼"
        case .userLevel:      return "레벨만큼"
        case .fixed(let n):   return "고정 \(n)"
        }
    }
}
