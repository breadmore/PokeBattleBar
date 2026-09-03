import Foundation

/// LAN 에서 오가는 메시지. 길이 4바이트(빅엔디안) + JSON 프레이밍.
enum Wire: Codable, Sendable {
    // 게스트 -> 호스트
    case join(playerName: String, team: [Battler])
    case chooseLead(index: Int)
    case action(BattleAction)
    case leave
    /// 채팅 (양방향)
    case chat(from: String, text: String)

    // 호스트 -> 게스트
    case joinAccepted(rules: BattleRules, hostName: String, yourSide: Int)
    case joinRejected(reason: String)
    case battleBegan(state: BattleState)
    case stateChanged(state: BattleState)
    case hostLeft
}

/// 와이어 프로토콜 버전.
///
/// **메시지 구조를 바꾸면 반드시 올린다.** Swift 의 합성 Codable 은 프로퍼티 기본값을
/// 쓰지 않으므로, 신규 필드가 하나만 늘어도 구버전이 보낸 JSON 은 디코딩이 실패한다.
/// 버전을 함께 실어보내야 "그냥 연결이 끊겼다" 가 아니라 "버전이 다르다" 를 보여줄 수 있다.
enum PokeBattleProtocol {
    static let version = 9

    /// 7: 게임 모드 4종 (랜덤기술·자유의지·자동변신·토게피 손가락흔들기),
    ///    다이맥스밴드/다이버섯 역할 분리
    /// 6: 전용 Z크리스탈, 스텔스록·중력·조임·아무것도않기·방어, 교체 기반,
    ///    MoveDef.target 추가 (변화기 타입 면역 판정)
    /// 9: 나무열매 38종, 특성 대폭 확장(96%), 무게, 묶기·유턴, 기술 봉인
    /// 8: 채팅, 기술 직접 선택, 추천 세팅, 묶기·유턴, Showdown 데이터 통합
    /// 5: 날씨·필드, G-Max 전용기, 접촉 기반 특성 추가
    /// 4: 지닌 도구 + 특성 추가 (Battler.heldItem / .ability, 규칙 토글 3개)
    /// 3: 다이맥스 추가 (usedGmax -> usedDynamax, gmaxTurnsLeft -> dynamaxTurnsLeft)
    /// 2: 메가진화/거다이맥스/Z기술 필드 추가 + 프로토콜 버전 도입
    /// 1: 최초 배포 (버전 정보 없음 — v2 이상과는 통신 불가)
    static let changelog = "v9 — 나무열매·특성 96%·무게"
}

/// 버전만 먼저 읽기 위한 최소 구조체.
/// 본문(msg) 구조가 달라도 이건 항상 디코딩되므로, 버전 불일치를 정확히 알려줄 수 있다.
private struct VersionProbe: Decodable { var v: Int }

private struct Envelope: Codable {
    var v: Int
    var msg: Wire
}

enum WireCodec {
    static let maxFrame = 4 * 1024 * 1024   // 팀 6마리 + 기술 정의로도 한참 남는다

    static func encode(_ w: Wire) throws -> Data {
        let body = try JSONEncoder().encode(Envelope(v: PokeBattleProtocol.version, msg: w))
        guard body.count <= maxFrame else { throw WireError.frameTooLarge(body.count) }
        var out = Data()
        var len = UInt32(body.count).bigEndian
        withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
        out.append(body)
        return out
    }

    /// 버퍼에서 완성된 프레임을 최대한 꺼낸다. 남은 바이트는 버퍼에 유지.
    static func drain(_ buffer: inout Data) throws -> [Wire] {
        var msgs: [Wire] = []
        while buffer.count >= 4 {
            let len = buffer.prefix(4).withUnsafeBytes {
                UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self))
            }
            guard len <= UInt32(maxFrame) else { throw WireError.frameTooLarge(Int(len)) }
            let total = 4 + Int(len)
            guard buffer.count >= total else { break }
            let body = buffer.subdata(in: 4..<total)
            buffer.removeSubrange(0..<total)

            // 본문을 해석하기 **전에** 버전을 확인한다.
            // 순서가 반대면 디코딩 실패가 먼저 터져서 원인을 알 수 없다.
            let probe = try JSONDecoder().decode(VersionProbe.self, from: body)
            guard probe.v == PokeBattleProtocol.version else {
                throw WireError.versionMismatch(theirs: probe.v, ours: PokeBattleProtocol.version)
            }
            msgs.append(try JSONDecoder().decode(Envelope.self, from: body).msg)
        }
        return msgs
    }
}

enum WireError: LocalizedError {
    case frameTooLarge(Int)
    case versionMismatch(theirs: Int, ours: Int)

    var errorDescription: String? {
        switch self {
        case .frameTooLarge(let n):
            "메시지가 너무 큽니다 (\(n) 바이트)"
        case .versionMismatch(let theirs, let ours):
            theirs > ours
              ? "상대의 PokeBattleBar 가 더 최신입니다 (상대 v\(theirs) / 내 v\(ours)). 내 앱을 업데이트해주세요."
              : "상대의 PokeBattleBar 가 구버전입니다 (상대 v\(theirs) / 내 v\(ours)). 상대에게 업데이트를 요청해주세요."
        }
    }

    /// 버전 문제인가 (UI 에서 다르게 안내한다)
    var isVersionProblem: Bool {
        if case .versionMismatch = self { return true }
        return false
    }
}
