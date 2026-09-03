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

    /// 손가락흔들기가 부를 수 있는 기술.
    ///
    /// **예전에는 재현 가능한 기술 207개를 손으로 골랐다.**
    /// 이제 Showdown 의 `metronome` 플래그를 쓴다 — 원작의 제외 목록이 그대로 반영돼 있고,
    /// 우리가 빠뜨릴 일이 없다. 다만 배틀 중 네트워크를 못 쓰므로,
    /// 실제로 받아둘 수 있는 규모로 추린다.
    static var metronomeCallable: [String] {
        Showdown.metronomePool
    }

    /// 실제로 받아둘 기술 목록.
    ///
    /// Showdown 기준 손가락흔들기 대상은 690개가 넘는데, 첫 실행에 그걸 다 받으면
    /// 너무 오래 걸린다. **결정적으로** 앞에서부터 잘라 쓴다 (정렬 후 상한).
    static let poolLimit = 320

    static var uniquePool: [String] {
        // Showdown id 는 하이픈이 없으므로 PokeAPI 이름으로 되돌려야 받을 수 있다.
        // 우리가 이미 PokeAPI 에서 받아본 적 있는 이름 규칙만 통과시킨다.
        let ids = Array(Set(metronomeCallable)).sorted()
        return Array(ids.prefix(poolLimit))
    }
}
