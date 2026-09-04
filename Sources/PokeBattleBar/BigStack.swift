import Foundation

/// **검증(CLI)은 메인 스레드에서 돌린다.**
///
/// 배틀 엔진은 한 턴을 동기로 계산한다. `performMove` 는 케이스가 많아
/// 디버그 빌드에서 스택 프레임이 크고(최적화가 지역변수 슬롯을 합쳐주지
/// 않는다), 모으기 기술은 `performMove → releaseChargedMove → performMove`
/// 로 한 번 더 겹친다.
///
/// 그냥 `Task { }` 로 띄우면 Swift 동시성의 **협조 스레드**에서 도는데
/// 그 스택은 512KB 뿐이다. 그래서 `SIGBUS: Thread stack size exceeded` 로
/// 죽었다 — `--selftest`, `--testall`, `--movelog` 가 전부 여기 걸렸다.
///
/// `Task { @MainActor in }` 은 메인 스레드(8MB)에서 돈다. 실제 앱이
/// 멀쩡했던 이유도 이것이다 — 엔진은 MainActor 에서만 돌아간다.
/// 크래시는 검증 경로가 MainActor 밖으로 나간 것 하나 때문이었다.
///
/// **직접 스레드를 만들어 스택을 키우는 방법은 통하지 않는다** — `Task` 는
/// 만든 스레드를 물려받지 않고 협조 풀로 옮겨간다. 처음에 그렇게 해봤고
/// 여전히 죽었다.
enum BigStack {

    /// 검증 작업을 메인 스레드에서 끝까지 돌리고 결과 코드로 종료한다.
    static func run(_ work: @escaping @MainActor @Sendable () async -> Bool) -> Never {
        Task { @MainActor in
            let ok = await work()
            exit(ok ? 0 : 1)
        }
        RunLoop.main.run()
        // RunLoop.main.run() 은 돌아오지 않는다. 컴파일러를 위한 줄이다.
        fatalError("도달할 수 없습니다")
    }
}
