import Foundation

/// 개체별 기술 4개를 **한 번 뽑아 고정 저장**한다.
/// 매 배틀마다 새로 뽑으면 "내 포켓몬의 기술"이라는 감각이 없다.
actor MovesetStore {
    static let shared = MovesetStore()

    private let fileURL: URL
    private var assigned: [String: [String]] = [:]   // slotID#speciesID -> 기술 이름 4개

    /// 공격기 최소 보장 개수 — 변화기만 4개 뽑히면 배틀이 굴러가지 않는다.
    private let minDamaging = 2
    /// 뽑는 동안 PokeAPI 를 두드리는 상한 (첫 실행 지연을 막는다)
    private let maxFetches = 24

    init() {
        let dir = FileManager.default
            .homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/PokeBattleBar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appending(path: "movesets.json")
        if let d = try? Data(contentsOf: fileURL),
           let m = try? JSONDecoder().decode([String: [String]].self, from: d) {
            assigned = m
        }
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(assigned) { try? d.write(to: fileURL) }
    }

    private func key(_ slot: RosterSlot) -> String { "\(slot.id)#\(slot.speciesID)" }

    /// 저장된 기술이 있으면 그것을, 없으면 배울 수 있는 기술에서 랜덤으로 뽑아 고정한다.
    func moveset(for slot: RosterSlot, species: SpeciesDef) async -> [MoveDef] {
        if let names = assigned[key(slot)], !names.isEmpty {
            let resolved = await resolve(names)
            if !resolved.isEmpty { return resolved }
        }
        let picked = await pick(from: species.learnableMoves)
        assigned[key(slot)] = picked.map(\.name)
        persist()
        return picked
    }

    /// 다시 뽑기 (사용자가 원할 때만)
    func reroll(for slot: RosterSlot, species: SpeciesDef) async -> [MoveDef] {
        assigned[key(slot)] = nil
        let picked = await pick(from: species.learnableMoves)
        assigned[key(slot)] = picked.map(\.name)
        persist()
        return picked
    }

    private func resolve(_ names: [String]) async -> [MoveDef] {
        var out: [MoveDef] = []
        for n in names {
            if let m = try? await PokeAPI.shared.move(n) { out.append(m) }
        }
        return out
    }

    /// 배울 수 있는 기술 풀에서 랜덤 4개.
    /// 단 공격기가 `minDamaging` 개 미만이 되지 않도록, 남은 자리가 부족해지면 변화기를 건너뛴다.
    /// 즉 "랜덤"은 유지하면서 아무것도 못 하는 조합만 배제한다.
    private func pick(from pool: [String]) async -> [MoveDef] {
        var candidates = Array(Set(pool)).shuffled()
        guard !candidates.isEmpty else { return await fallback() }

        var chosen: [MoveDef] = []
        var damaging = 0
        var fetches = 0

        while chosen.count < 4, !candidates.isEmpty, fetches < maxFetches {
            let name = candidates.removeLast()
            fetches += 1
            guard let m = try? await PokeAPI.shared.move(name) else { continue }

            let isDamaging = (m.power ?? 0) > 0
            let slotsLeft = 4 - chosen.count
            // 남은 자리를 전부 써도 공격기 최소치를 못 채우게 되면 변화기는 받지 않는다
            if !isDamaging, slotsLeft <= minDamaging - damaging { continue }

            chosen.append(m)
            if isDamaging { damaging += 1 }
        }

        // 공격기 확보 때문에 자리가 남았으면 남은 후보로 채운다
        while chosen.count < 4, !candidates.isEmpty, fetches < maxFetches + 8 {
            let name = candidates.removeLast()
            fetches += 1
            guard let m = try? await PokeAPI.shared.move(name),
                  !chosen.contains(where: { $0.name == m.name }) else { continue }
            chosen.append(m)
            if (m.power ?? 0) > 0 { damaging += 1 }
        }

        if damaging == 0 {
            chosen.append(contentsOf: await fallback())
        }
        return chosen
    }

    /// 풀이 비었거나 공격기를 하나도 못 구한 경우의 최후 수단.
    private func fallback() async -> [MoveDef] {
        for n in ["tackle", "pound", "scratch", "struggle"] {
            if let m = try? await PokeAPI.shared.move(n) { return [m] }
        }
        return []
    }
}
