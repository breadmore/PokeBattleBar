import Foundation

enum Stat: String, Codable, CaseIterable, Sendable {
    case hp, attack, defense, spAttack, spDefense, speed

    /// PokeAPI 의 스탯 이름 매핑
    init?(apiName: String) {
        switch apiName {
        case "hp": self = .hp
        case "attack": self = .attack
        case "defense": self = .defense
        case "special-attack": self = .spAttack
        case "special-defense": self = .spDefense
        case "speed": self = .speed
        default: return nil
        }
    }

    var ko: String {
        switch self {
        case .hp: "HP"; case .attack: "공격"; case .defense: "방어"
        case .spAttack: "특공"; case .spDefense: "특방"; case .speed: "스피드"
        }
    }
}

/// 성격 보정: 한 스탯 +10%, 다른 하나 -10%. 중립 성격은 보정 없음.
struct Nature: Sendable {
    let name: String
    let up: Stat?
    let down: Stat?
    var ko: String { Nature.koNames[name] ?? name }

    func multiplier(for s: Stat) -> Double {
        if s == .hp { return 1.0 }
        if s == up, s != down { return 1.1 }
        if s == down, s != up { return 0.9 }
        return 1.0
    }

    static func named(_ raw: String) -> Nature {
        let key = raw.lowercased()
        if let n = table[key] { return n }
        return Nature(name: key, up: nil, down: nil)   // 모르는 성격은 중립 처리
    }

    private static let table: [String: Nature] = {
        // (성격, 상승, 하락) — 중립 5종은 up/down 동일하게 두어 보정 0
        let defs: [(String, Stat, Stat)] = [
            ("hardy", .attack, .attack),     ("lonely", .attack, .defense),
            ("brave", .attack, .speed),      ("adamant", .attack, .spAttack),
            ("naughty", .attack, .spDefense),("bold", .defense, .attack),
            ("docile", .defense, .defense),  ("relaxed", .defense, .speed),
            ("impish", .defense, .spAttack), ("lax", .defense, .spDefense),
            ("timid", .speed, .attack),      ("hasty", .speed, .defense),
            ("serious", .speed, .speed),     ("jolly", .speed, .spAttack),
            ("naive", .speed, .spDefense),   ("modest", .spAttack, .attack),
            ("mild", .spAttack, .defense),   ("quiet", .spAttack, .speed),
            ("bashful", .spAttack, .spAttack),("rash", .spAttack, .spDefense),
            ("calm", .spDefense, .attack),   ("gentle", .spDefense, .defense),
            ("sassy", .spDefense, .speed),   ("careful", .spDefense, .spAttack),
            ("quirky", .spDefense, .spDefense)
        ]
        var m: [String: Nature] = [:]
        for (n, u, d) in defs { m[n] = Nature(name: n, up: u, down: d) }
        return m
    }()

    static let koNames: [String: String] = [
        "hardy": "노력", "lonely": "외로움", "brave": "용감", "adamant": "고집",
        "naughty": "개구쟁이", "bold": "대담", "docile": "온순", "relaxed": "무사태평",
        "impish": "장난꾸러기", "lax": "촐랑", "timid": "겁쟁이", "hasty": "성급",
        "serious": "성실", "jolly": "명랑", "naive": "천진", "modest": "조심",
        "mild": "의젓", "quiet": "냉정", "bashful": "수줍음", "rash": "덜렁",
        "calm": "차분", "gentle": "얌전", "sassy": "건방", "careful": "신중",
        "quirky": "변덕"
    ]
}

/// `[Stat: Int]` 을 JSON **객체**로 직렬화하기 위한 conformance.
/// 없으면 Swift 는 [키,값,키,값,…] 평평한 배열로 인코딩하고 순서가 딕셔너리마다 달라진다
/// (내용은 보존되지만 와이어 포맷이 커지고 비결정적이라 진단이 어렵다).
struct StatCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

extension Stat: CodingKeyRepresentable {
    var codingKey: CodingKey { StatCodingKey(stringValue: rawValue) }
    init?<T: CodingKey>(codingKey: T) { self.init(rawValue: codingKey.stringValue) }
}
