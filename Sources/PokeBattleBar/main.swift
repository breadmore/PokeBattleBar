import Foundation

let args = CommandLine.arguments

if args.contains("--showdowntest") {
    Task {
        let passed = await ShowdownTest.run()
        exit(passed ? 0 : 1)
    }
    RunLoop.main.run()
}

if args.contains("--modetest") {
    Task {
        let passed = await ModeTest.run()
        exit(passed ? 0 : 1)
    }
    RunLoop.main.run()
}

if args.contains("--testall") {
    func intVal(_ flag: String, default def: Int) -> Int {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count, let v = Int(args[i + 1]) else { return def }
        return v
    }
    let n = intVal("--battles", default: 40)
    let verbose = args.contains("--verbose")
    Task {
        let passed = await TestAll.run(battles: n, verbose: verbose)
        exit(passed ? 0 : 1)
    }
    RunLoop.main.run()
}

if args.contains("--roster") {
    Task {
        let ok = await RosterDump.run()
        exit(ok ? 0 : 1)
    }
    RunLoop.main.run()
}

if args.contains("--edgetest") {
    let verbose = args.contains("--verbose")
    Task {
        let passed = await EdgeCaseTest.run(verbose: verbose)
        exit(passed ? 0 : 1)
    }
    RunLoop.main.run()
}

if args.contains("--bugsweep") {
    func intVal(_ flag: String, default def: Int) -> Int {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count, let v = Int(args[i + 1]) else { return def }
        return v
    }
    let n = intVal("--battles", default: 40)
    let verbose = args.contains("--verbose")
    Task {
        let passed = await BugSweep.run(battles: n, verbose: verbose)
        exit(passed ? 0 : 1)
    }
    RunLoop.main.run()
}

if args.contains("--extendedtest") {
    Task {
        let passed = await ExtendedTest.run()
        exit(passed ? 0 : 1)
    }
    RunLoop.main.run()
}

if args.contains("--loadouttest") {
    let verbose = args.contains("--verbose")
    Task {
        let passed = await LoadoutTest.run(verbose: verbose)
        exit(passed ? 0 : 1)
    }
    RunLoop.main.run()
}

if args.contains("--itemtest") {
    Task {
        let passed = await ItemTest.run()
        exit(passed ? 0 : 1)
    }
    RunLoop.main.run()
}

if args.contains("--formtest") {
    let verbose = args.contains("--verbose")
    Task {
        let passed = await FormTest.run(verbose: verbose)
        exit(passed ? 0 : 1)
    }
    RunLoop.main.run()
}

if args.contains("--movetest") {
    let verbose = args.contains("--verbose")
    Task {
        let passed = await MoveEffectTest.run(verbose: verbose)
        exit(passed ? 0 : 1)
    }
    RunLoop.main.run()
}

if args.contains("--pickertest") {
    // @MainActor 테스트는 세마포어로 기다리면 안 된다 —
    // 메인 스레드가 잠기면 MainActor 작업이 실행될 수 없어 데드락이다.
    // 런루프를 돌려주고 작업 안에서 종료한다.
    Task { @MainActor in
        let passed = await SelectionTest.run()
        exit(passed ? 0 : 1)
    }
    RunLoop.main.run()
}

if args.contains("--nettest") {
    Task {
        let passed = await NetTest.run()
        exit(passed ? 0 : 1)
    }
    RunLoop.main.run()
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

    Task {
        let passed = await SelfTest.run(speciesA: a, speciesB: b, level: lvl, verbose: verbose)
        exit(passed ? 0 : 1)
    }
    RunLoop.main.run()
}

PokeBattleBarApp.main()
