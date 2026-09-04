import Foundation

/// **조건에 따라 성패나 위력이 달라지는 기술들.**
///
/// PokeAPI 는 이걸 주지 않는다 — 꿈먹기의 위력은 그냥 100 이고, "상대가 잠들어
/// 있어야 한다"는 조건은 어디에도 없다. Showdown 은 코드(onTryImmunity,
/// basePowerCallback)로 들고 있어서 데이터로 추출할 수 없다. 그래서 표로 만든다.
///
/// 두 종류로 나뉜다:
///  - **실패 조건**: 조건이 안 맞으면 아무 일도 일어나지 않는다 (꿈먹기·속이기)
///  - **위력 조건**: 조건이 맞으면 위력이 배로 뛴다 (마수말·오물웨이브)
enum ConditionalMove {

    /// 실패 조건을 확인한다. 실패하면 화면에 띄울 이유를 돌려준다.
    ///
    /// - Returns: nil 이면 그냥 나간다. 문자열이 오면 그 이유로 실패한다.
    static func failureReason(move: String, attacker: Battler, defender: Battler,
                             attackerSide: SideState) -> String? {
        switch move {
        // 상대가 잠들어 있어야 한다
        case "dream-eater", "nightmare":
            return defender.status == .sleep ? nil : "하지만 실패했다!"

        // 내가 잠들어 있어야 한다
        case "snore", "sleep-talk":
            return attacker.status == .sleep ? nil : "하지만 실패했다!"

        // 나온 턴에만 쓸 수 있다
        case "fake-out", "first-impression":
            return attacker.turnsOnField == 0 ? nil : "하지만 실패했다!"

        // 상대가 도구를 지니고 있어야 한다
        case "poltergeist":
            return defender.hasUsableItem ? nil : "하지만 실패했다!"

        // 다른 기술을 **전부** 한 번씩 쓴 뒤에만 나간다
        case "last-resort":
            let others = attacker.moves.indices.filter { i in
                attacker.moves[i].def.name != "last-resort"
            }
            guard !others.isEmpty else { return "하지만 실패했다!" }
            let allUsed = others.allSatisfy { attacker.usedMoveIndices.contains($0) }
            return allUsed ? nil : "하지만 실패했다!"

        // 자기 타입을 하나 잃는 기술 — 그 타입이 없으면 실패한다
        case "burn-up":
            return attacker.types.contains(.fire) ? nil : "하지만 실패했다!"
        case "double-shock":
            return attacker.types.contains(.electric) ? nil : "하지만 실패했다!"

        // 모르푼 전용
        case "aura-wheel":
            return attacker.speciesID == 877 ? nil : "모르푼만 쓸 수 있다!"

        default:
            return nil
        }
    }

    /// 조건이 맞으면 위력이 곱해진다.
    ///
    /// - Parameter movedFirst: 이번 턴에 내가 먼저 움직였는가 (역돌기 판정)
    static func powerMultiplier(move: String, attacker: Battler, defender: Battler,
                                attackerSide: SideState, movedFirst: Bool,
                                field: FieldState) -> Double {
        switch move {
        // 상대가 상태이상이면 두 배
        case "hex", "infernal-parade":
            return defender.status != .none ? 2.0 : 1.0
        // 상대가 독이면 두 배
        case "venoshock", "barb-barrage":
            return (defender.status == .poison || defender.status == .toxic) ? 2.0 : 1.0
        // 상대가 잠들어 있으면 두 배 (그리고 깨운다 — 호출부에서 처리)
        case "wake-up-slap":
            return defender.status == .sleep ? 2.0 : 1.0
        // 상대가 마비면 두 배 (그리고 풀어준다)
        case "smelling-salts":
            return defender.status == .paralysis ? 2.0 : 1.0
        // 상대 HP 가 절반 이하면 두 배
        case "brine":
            return Double(defender.currentHP) * 2 <= Double(defender.maxHP) ? 2.0 : 1.0
        // 내가 상태이상이면 두 배 (화상의 공격 반감은 별도로 무시된다)
        case "facade":
            return attacker.status != .none ? 2.0 : 1.0
        // 도구를 안 지녔으면 두 배
        case "acrobatics":
            return attacker.hasUsableItem ? 1.0 : 2.0
        // 내가 나중에 움직이면 두 배
        case "payback":
            return movedFirst ? 1.0 : 2.0
        // 상대가 이번 턴에 이미 데미지를 입었으면 두 배
        case "assurance":
            return defender.damagedThisTurn ? 2.0 : 1.0
        // 이번 턴에 내가 맞았으면 두 배
        case "avalanche", "revenge":
            return attacker.wasHitThisTurn ? 2.0 : 1.0
        // 지난 턴에 아군이 쓰러졌으면 두 배
        case "retaliate":
            return attackerSide.allyFaintedLastTurn ? 2.0 : 1.0
        // 직전 기술이 실패했으면 두 배
        case "stomping-tantrum":
            return attacker.lastMoveFailed ? 2.0 : 1.0
        // 일렉트릭필드에 서 있으면 두 배
        case "rising-voltage":
            return (field.terrain == .electric && attacker.grounded) ? 2.0 : 1.0
        // 사이코필드에서는 1.5 배 (싱글에서는 이게 전부다)
        case "expanding-force":
            return field.terrain == .psychic ? 1.5 : 1.0
        // 미스트필드에서 1.5 배
        case "misty-explosion":
            return field.terrain == .misty ? 1.5 : 1.0
        // 쾌청에서는 모으지 않고 나가는 대신 비·모래·눈에서 위력이 반이다
        case "solar-beam", "solar-blade":
            switch field.weather {
            case .rain, .sandstorm, .snow: return 0.5
            default: return 1.0
            }
        default:
            return 1.0
        }
    }

    /// 날씨·필드에 따라 **타입까지 바뀌는** 기술.
    /// 웨더볼은 쾌청이면 불꽃, 비면 물… 이 되고 위력도 두 배가 된다.
    static func typeAndPower(move: String, field: FieldState,
                             grounded: Bool) -> (type: PType, multiplier: Double)? {
        switch move {
        case "weather-ball":
            switch field.weather {
            case .sun:       return (.fire, 2.0)
            case .rain:      return (.water, 2.0)
            case .sandstorm: return (.rock, 2.0)
            case .snow:      return (.ice, 2.0)
            default:         return (.normal, 1.0)
            }
        case "terrain-pulse":
            guard grounded else { return (.normal, 1.0) }
            switch field.terrain {
            case .electric: return (.electric, 2.0)
            case .grassy:   return (.grass, 2.0)
            case .misty:    return (.fairy, 2.0)
            case .psychic:  return (.psychic, 2.0)
            case .none:     return (.normal, 1.0)
            }
        default:
            return nil
        }
    }

    /// 맞히면서 상대의 상태이상을 풀어주는 기술 (뺨치기·소금뿌리기)
    static func curesTargetStatus(move: String) -> Ailment? {
        switch move {
        case "wake-up-slap":    return .sleep
        case "smelling-salts":  return .paralysis
        default:                return nil
        }
    }

    /// 여기서 다루는 기술 전체 — 감사(audit)가 목록을 훑는 데 쓴다.
    static let all: Set<String> = [
        "dream-eater", "nightmare", "snore", "sleep-talk",
        "fake-out", "first-impression", "poltergeist", "last-resort",
        "burn-up", "double-shock", "aura-wheel",
        "hex", "infernal-parade", "venoshock", "barb-barrage",
        "wake-up-slap", "smelling-salts", "brine", "facade", "acrobatics",
        "payback", "assurance", "avalanche", "revenge", "retaliate",
        "stomping-tantrum", "rising-voltage", "expanding-force",
        "misty-explosion", "solar-beam", "solar-blade",
        "weather-ball", "terrain-pulse",
    ]
}
