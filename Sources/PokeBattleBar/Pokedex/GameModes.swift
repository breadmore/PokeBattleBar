import Foundation

/// 특별 게임 모드에 필요한 데이터.
enum GameModes {

    /// 토게피 손가락흔들기 모드의 고정 설정
    enum Metronome {
        static let speciesID = 175          // 토게피
        static let move = "metronome"       // 손가락흔들기
        static let item = "life-orb"        // 생명의구슬
        static let nature = "serious"       // 중립 성격 — 순수하게 손가락흔들기 운으로만
    }

    /// PP Up 3회를 다 쓴 최대 PP (원작: 기본 PP + 기본PP/5 × 3)
    static func maxPP(base: Int) -> Int {
        base + (base / 5) * 3
    }

    /// 손가락흔들기가 부를 수 있는 기술 풀.
    ///
    /// 원작은 거의 모든 기술을 부르지만, 배틀 중엔 네트워크를 쓸 수 없어 미리 받아둬야 한다.
    /// 그래서 **이 엔진이 실제로 재현할 수 있는 기술**을 골라 고정 목록으로 둔다.
    /// (Z기술·맥스기술·손가락흔들기 자신은 원작에서도 제외된다)
    static let metronomePool: [String] = [
        // 물리 공격기
        "tackle", "body-slam", "double-edge", "take-down", "quick-attack", "extreme-speed",
        "slam", "strength", "headbutt", "zen-headbutt", "iron-head", "giga-impact",
        "bite", "crunch", "fire-fang", "thunder-fang", "ice-fang", "psychic-fangs",
        "mega-punch", "fire-punch", "ice-punch", "thunder-punch", "drain-punch",
        "mach-punch", "bullet-punch", "dynamic-punch", "close-combat", "brick-break",
        "cross-chop", "hammer-arm", "superpower", "low-kick", "high-jump-kick",
        "blaze-kick", "mega-kick", "aerial-ace", "wing-attack", "brave-bird", "drill-peck",
        "megahorn", "wild-charge", "flare-blitz", "u-turn", "waterfall", "aqua-tail",
        "dragon-claw", "outrage", "play-rough", "poison-jab", "leaf-blade", "wood-hammer",
        "shadow-claw", "sucker-punch", "knock-off", "steel-wing", "metal-claw", "iron-tail",
        "avalanche", "liquidation", "crabhammer", "earthquake", "rock-slide", "stone-edge",
        "bulldoze", "x-scissor", "night-slash", "slash", "double-slap", "fury-swipes",
        "rock-tomb", "smart-strike", "lunge", "first-impression", "facade", "return",

        // 특수 공격기
        "flamethrower", "fire-blast", "heat-wave", "ember", "lava-plume",
        "surf", "hydro-pump", "water-pulse", "scald", "bubble-beam",
        "thunderbolt", "thunder", "discharge", "volt-switch", "shock-wave",
        "energy-ball", "giga-drain", "leaf-storm", "solar-beam", "petal-dance",
        "ice-beam", "blizzard", "icy-wind", "aurora-beam", "frost-breath",
        "psychic", "psyshock", "confusion", "extrasensory", "future-sight",
        "sludge-bomb", "sludge-wave", "acid-spray", "venoshock",
        "dark-pulse", "night-daze", "snarl", "shadow-ball", "hex", "night-shade",
        "dragon-pulse", "draco-meteor", "dragon-breath", "dragon-rage",
        "flash-cannon", "moonblast", "dazzling-gleam", "air-slash", "hurricane",
        "bug-buzz", "power-gem", "ancient-power", "earth-power", "mud-shot",
        "hyper-voice", "swift", "tri-attack", "hyper-beam", "boomburst",
        "aura-sphere", "focus-blast", "vacuum-wave", "seismic-toss", "sonic-boom",

        // 변화기 — 상태이상
        "thunder-wave", "will-o-wisp", "toxic", "poison-powder", "stun-spore",
        "sleep-powder", "spore", "hypnosis", "confuse-ray", "sweet-kiss",
        "glare", "yawn", "dark-void",

        // 변화기 — 능력치
        "swords-dance", "nasty-plot", "calm-mind", "bulk-up", "iron-defense",
        "agility", "rock-polish", "amnesia", "barrier", "growth", "work-up",
        "growl", "leer", "tail-whip", "screech", "charm", "feather-dance",
        "string-shot", "scary-face", "sand-attack", "smokescreen", "flash",
        "double-team", "minimize", "cotton-spore", "metal-sound",

        // 변화기 — 회복 / 방어 / 필드
        "recover", "soft-boiled", "roost", "slack-off", "milk-drink", "heal-order",
        "protect", "detect",
        "sunny-day", "rain-dance", "sandstorm", "hail",
        "electric-terrain", "grassy-terrain", "misty-terrain", "psychic-terrain",

        // 다단히트 / 특수 규칙
        "double-slap", "fury-attack", "pin-missile", "bullet-seed", "rock-blast",
        "icicle-spear", "arm-thrust", "double-kick", "explosion", "self-destruct",
        "fake-out", "counter", "final-gambit", "memento"
    ]

    /// 실제로 받아온 풀. 중복을 제거하고 정렬해 결정적으로 만든다.
    static var uniquePool: [String] {
        Array(Set(metronomePool)).sorted()
    }
}
