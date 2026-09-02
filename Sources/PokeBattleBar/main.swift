import Foundation

let args = CommandLine.arguments

if args.contains("--nettest") {
    let sem = DispatchSemaphore(value: 0)
    var passed = false
    Task {
        passed = await NetTest.run()
        sem.signal()
    }
    sem.wait()
    exit(passed ? 0 : 1)
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

    let sem = DispatchSemaphore(value: 0)
    var passed = false
    Task {
        passed = await SelfTest.run(speciesA: a, speciesB: b, level: lvl, verbose: verbose)
        sem.signal()
    }
    sem.wait()
    exit(passed ? 0 : 1)
}

PokeBattleBarApp.main()
