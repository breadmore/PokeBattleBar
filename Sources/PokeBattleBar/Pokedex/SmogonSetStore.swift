import Foundation

/// Smogon 분석 세팅.
///
/// Showdown 저장소의 랜덤배틀 세팅에는 **도구가 없다** (팀 생성 알고리즘이
/// 고르기 때문이다). 그래서 도구·기술·특성이 함께 든 Smogon 분석 세팅을
/// 따로 받아둔다. 한 종에 이름 붙은 세팅이 여러 개라 **골라 쓸 수 있다.**
///
/// **성격과 노력치는 가져오지 않는다** — 성격은 PokeTokenBar 를 따르고,
/// 노력치는 전원 0 으로 싸운다.
struct SmogonSet: Sendable, Identifiable, Hashable {
    /// 포맷 (gen71v1 등)
    var format: String
    /// 세팅 이름 ("Sun Sweeper")
    var name: String
    /// 기술 네 칸. 칸마다 대안이 여러 개일 수 있다 (첫 번째가 1순위).
    var moveSlots: [[String]]
    var item: String?
    var ability: String?

    var id: String { "\(format)/\(name)" }

    /// 화면에 보여줄 포맷 라벨 ("7세대 1대1")
    var formatLabel: String { SmogonSets.label(format) }

    /// 1순위 기술 네 개 (PokeAPI 이름으로)
    var primaryMoves: [String] {
        moveSlots.compactMap { $0.first.map(SmogonSets.moveID) }
    }

    /// 대안까지 포함한 전체 후보 (배울 수 있는 것을 고를 때 쓴다)
    var allMoveOptions: [[String]] {
        moveSlots.map { $0.map(SmogonSets.moveID) }
    }

    var itemID: String? { item.map(SmogonSets.itemID) }
    var abilityID: String? { ability.map(SmogonSets.abilityID) }
}

enum SmogonSets {
    private static let store: [String: [SmogonSet]] = {
        guard let data = SmogonSetsData.json.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: [[String: Any]]]
        else { return [:] }

        var out: [String: [SmogonSet]] = [:]
        for (species, sets) in raw {
            var list: [SmogonSet] = []
            for s in sets {
                let slots: [[String]] = (s["m"] as? [Any] ?? []).compactMap { slot in
                    if let one = slot as? String { return [one] }
                    if let many = slot as? [String] { return many }
                    return nil
                }
                list.append(SmogonSet(format: s["f"] as? String ?? "",
                                      name: s["n"] as? String ?? "세팅",
                                      moveSlots: slots,
                                      item: s["i"] as? String,
                                      ability: s["a"] as? String))
            }
            out[id(fromDisplay: species)] = list
        }
        return out
    }()

    private static let labels: [String: String] = {
        guard let data = SmogonSetsData.formatLabels.data(using: .utf8),
              let m = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return [:] }
        return m
    }()

    static func label(_ format: String) -> String { labels[format] ?? format }

    /// 이 종의 세팅들. 1대1 포맷이 앞에 온다 (생성 시 순서를 그렇게 넣었다).
    static func sets(forSpeciesName name: String) -> [SmogonSet] {
        store[id(fromDisplay: name)] ?? []
    }

    /// 종 이름 정규화. Smogon 은 "Rotom-Wash", PokeAPI 는 "rotom-wash" 를 쓴다.
    static func id(fromDisplay name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ":", with: "")
    }

    /// "Giga Drain" -> "giga-drain" (PokeAPI 기술 이름)
    static func moveID(_ display: String) -> String {
        display.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ":", with: "")
    }

    /// "Life Orb" -> "life-orb"
    static func itemID(_ display: String) -> String { moveID(display) }
    /// "Thick Fat" -> "thick-fat"
    static func abilityID(_ display: String) -> String { moveID(display) }

    /// 데이터가 실제로 들어왔는지 (테스트용)
    static var speciesCount: Int { store.count }
    static var setCount: Int { store.values.reduce(0) { $0 + $1.count } }
}
