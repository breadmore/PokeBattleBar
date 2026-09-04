import Foundation

let args = CommandLine.arguments

if let i = args.firstIndex(of: "--lanprobe") {
    let role = i + 1 < args.count ? args[i + 1] : ""
    var secs = 8
    if let j = args.firstIndex(of: "--seconds"), j + 1 < args.count, let v = Int(args[j + 1]) { secs = v }
    // 검증은 큰 스택 스레드에서 돌린다 (BigStack 주석 참고)
    BigStack.run { await LanProbe.run(role: role, seconds: secs) }
}

if args.contains("--mechaudit") {
    let verbose = args.contains("--verbose")
    // 검증은 큰 스택 스레드에서 돌린다 (BigStack 주석 참고)
    BigStack.run { await MechanicAudit.run(verbose: verbose) }
}

if args.contains("--formaudit") {
    func intVal(_ flag: String, default def: Int) -> Int {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count, let v = Int(args[i + 1]) else { return def }
        return v
    }
    let upTo = intVal("--upto", default: 649)
    let verbose = args.contains("--verbose")
    // 검증은 큰 스택 스레드에서 돌린다 (BigStack 주석 참고)
    BigStack.run { await FormAudit.run(upTo: upTo, verbose: verbose) }
}

if args.contains("--setsweep") {
    func intVal(_ flag: String, default def: Int) -> Int {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count, let v = Int(args[i + 1]) else { return def }
        return v
    }
    let limit = intVal("--limit", default: 0)
    let verbose = args.contains("--verbose")
    // 검증은 큰 스택 스레드에서 돌린다 (BigStack 주석 참고)
    BigStack.run { await SetSweepTest.run(limitSpecies: limit, verbose: verbose) }
}

if args.contains("--settest") {
    // 검증은 큰 스택 스레드에서 돌린다 (BigStack 주석 참고)
    BigStack.run { await SmogonSetTest.run() }
}

if args.contains("--scriptedtest") {
    let verbose = args.contains("--verbose")
    // 검증은 큰 스택 스레드에서 돌린다 (BigStack 주석 참고)
    BigStack.run { await ScriptedMoveTest.run(verbose: verbose) }
}

if args.contains("--moveaudit") {
    let verbose = args.contains("--verbose")
    // 검증은 큰 스택 스레드에서 돌린다 (BigStack 주석 참고)
    BigStack.run { await MoveAudit.run(verbose: verbose) }
}

if args.contains("--lobbytest") {
    // 검증은 큰 스택 스레드에서 돌린다 (BigStack 주석 참고)
    BigStack.run { await LobbyTest.run() }
}

if args.contains("--playbacktest") {
    // 검증은 큰 스택 스레드에서 돌린다 (BigStack 주석 참고)
    BigStack.run { await PlaybackTest.run() }
}

if args.contains("--profiletest") {
    // 검증은 큰 스택 스레드에서 돌린다 (BigStack 주석 참고)
    BigStack.run { await TestProfileTest.run() }
}

if args.contains("--formchangetest") {
    // 검증은 큰 스택 스레드에서 돌린다 (BigStack 주석 참고)
    BigStack.run { await FormChangeTest.run() }
}

if args.contains("--berrytest") {
    // 검증은 큰 스택 스레드에서 돌린다 (BigStack 주석 참고)
    BigStack.run { await BerryTest.run() }
}

if args.contains("--abilitytest") {
    let full = args.contains("--full")
    // 검증은 큰 스택 스레드에서 돌린다 (BigStack 주석 참고)
    BigStack.run { await AbilityCoverageTest.run(full: full) }
}

if args.contains("--showdowntest") {
    // 검증은 큰 스택 스레드에서 돌린다 (BigStack 주석 참고)
    BigStack.run { await ShowdownTest.run() }
}

if args.contains("--modetest") {
    // 검증은 큰 스택 스레드에서 돌린다 (BigStack 주석 참고)
    BigStack.run { await ModeTest.run() }
}

if args.contains("--testall") {
    func intVal(_ flag: String, default def: Int) -> Int {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count, let v = Int(args[i + 1]) else { return def }
        return v
    }
    let n = intVal("--battles", default: 40)
    let verbose = args.contains("--verbose")
    // 검증은 큰 스택 스레드에서 돌린다 (BigStack 주석 참고)
    BigStack.run { await TestAll.run(battles: n, verbose: verbose) }
}

if args.contains("--roster") {
    // 검증은 큰 스택 스레드에서 돌린다 (BigStack 주석 참고)
    BigStack.run { await RosterDump.run() }
}

if args.contains("--edgetest") {
    let verbose = args.contains("--verbose")
    // 검증은 큰 스택 스레드에서 돌린다 (BigStack 주석 참고)
    BigStack.run { await EdgeCaseTest.run(verbose: verbose) }
}

if args.contains("--bugsweep") {
    func intVal(_ flag: String, default def: Int) -> Int {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count, let v = Int(args[i + 1]) else { return def }
        return v
    }
    let n = intVal("--battles", default: 40)
    let verbose = args.contains("--verbose")
    // 검증은 큰 스택 스레드에서 돌린다 (BigStack 주석 참고)
    BigStack.run { await BugSweep.run(battles: n, verbose: verbose) }
}

if args.contains("--extendedtest") {
    // 검증은 큰 스택 스레드에서 돌린다 (BigStack 주석 참고)
    BigStack.run { await ExtendedTest.run() }
}

if args.contains("--loadouttest") {
    let verbose = args.contains("--verbose")
    // 검증은 큰 스택 스레드에서 돌린다 (BigStack 주석 참고)
    BigStack.run { await LoadoutTest.run(verbose: verbose) }
}

if args.contains("--itemtest") {
    // 검증은 큰 스택 스레드에서 돌린다 (BigStack 주석 참고)
    BigStack.run { await ItemTest.run() }
}

if args.contains("--formtest") {
    let verbose = args.contains("--verbose")
    // 검증은 큰 스택 스레드에서 돌린다 (BigStack 주석 참고)
    BigStack.run { await FormTest.run(verbose: verbose) }
}

if args.contains("--movetest") {
    let verbose = args.contains("--verbose")
    // 검증은 큰 스택 스레드에서 돌린다 (BigStack 주석 참고)
    BigStack.run { await MoveEffectTest.run(verbose: verbose) }
}

if args.contains("--pickertest") {
    // @MainActor 테스트는 세마포어로 기다리면 안 된다 —
    // 메인 스레드가 잠기면 MainActor 작업이 실행될 수 없어 데드락이다.
    // 런루프를 돌려주고 작업 안에서 종료한다.
    // 검증은 큰 스택 스레드에서 돌린다 (BigStack 주석 참고)
    BigStack.run { await SelectionTest.run() }
}

// 기술 하나의 턴 로그를 그대로 본다 (구현 확인용)
if let i = args.firstIndex(of: "--movelog"), args.count > i + 1 {
    let move = args[i + 1]
    func opt(_ name: String, _ fallback: String) -> String {
        guard let j = args.firstIndex(of: name), args.count > j + 1 else { return fallback }
        return args[j + 1]
    }
    let turns = Int(opt("--turns", "3")) ?? 3
    let foeMove = opt("--foe-move", "splash")
    let speed = Int(opt("--speed", "999")) ?? 999
    let extra = args.firstIndex(of: "--move2").flatMap { j in
        args.count > j + 1 ? args[j + 1] : nil
    }
    // 검증은 큰 스택 스레드에서 돌린다 (BigStack 주석 참고)
    BigStack.run {
        await MoveLog.run(move: move, turns: turns,
                          foeMove: foeMove, userSpeed: speed, extraMove: extra)
    }
}

// Showdown 데이터와 우리 구현을 대조한다 — 뭘 빼먹었는지 데이터가 말해준다
// 내 로스터 기술이 실제로 작동하는지 하나하나 센다
if args.contains("--usability") {
    // 검증은 큰 스택 스레드에서 돌린다 (BigStack 주석 참고)
    BigStack.run { await MoveUsabilityAudit.run(verbose: args.contains("--all")) }
}

if args.contains("--datagap") {
    // 검증은 큰 스택 스레드에서 돌린다 (BigStack 주석 참고)
    BigStack.run { await DataGapAudit.run(verbose: args.contains("--all")) }
}

if args.contains("--nettest") {
    // 검증은 큰 스택 스레드에서 돌린다 (BigStack 주석 참고)
    BigStack.run { await NetTest.run() }
}

if args.contains("--selftest") {
    // 헤드리스 검증 — UI 를 띄우지 않는다.
    func intList(_ flag: String, default def: [Int]) -> [Int] {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return def }
        let parsed = args[i + 1].split(separator: ",").compactMap { Int($0) }
        return parsed.isEmpty ? def : parsed
    }
    func intVal(_ flag: String, default def: Int) -> Int {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count, let v = Int(args[i + 1]) else { return def }
        return v
    }

    let a = intList("--a", default: [87, 317, 6, 9, 3, 65])
    let b = intList("--b", default: [143, 130, 149, 94, 68, 131])
    let lvl = intVal("--level", default: 50)
    let verbose = args.contains("--verbose")

    // 검증은 큰 스택 스레드에서 돌린다 (BigStack 주석 참고)
    BigStack.run { await SelfTest.run(speciesA: a, speciesB: b, level: lvl, verbose: verbose) }
}

PokeBattleBarApp.main()
