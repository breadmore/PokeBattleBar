import Foundation

/// 공격 타입 → 방어 타입 배율. PokeAPI 에서 받아 캐시된다.
struct TypeChart: Codable, Sendable {
    var table: [PType: [PType: Double]]

    /// 방어측 타입이 둘이면 배율을 곱한다 (원작과 동일).
    func multiplier(attack: PType, defenders: [PType]) -> Double {
        defenders.reduce(1.0) { acc, d in
            acc * (table[attack]?[d] ?? 1.0)
        }
    }

    static func effectivenessText(_ m: Double) -> String? {
        if m == 0 { return "효과가 없는 것 같다…" }
        if m >= 2 { return "효과가 굉장했다!" }
        if m > 0, m < 1 { return "효과가 별로인 듯하다…" }
        return nil
    }
}
