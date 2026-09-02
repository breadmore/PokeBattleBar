import Foundation

/// LAN 에서 오가는 메시지. 길이 4바이트(빅엔디안) + JSON 프레이밍.
enum Wire: Codable, Sendable {
    // 게스트 -> 호스트
    case join(playerName: String, team: [Battler])
    case chooseLead(index: Int)
    case action(BattleAction)
    case leave

    // 호스트 -> 게스트
    case joinAccepted(rules: BattleRules, hostName: String, yourSide: Int)
    case joinRejected(reason: String)
    case battleBegan(state: BattleState)
    case stateChanged(state: BattleState)
    case hostLeft
}

enum WireCodec {
    static let maxFrame = 4 * 1024 * 1024   // 팀 6마리 + 기술 정의로도 한참 남는다

    static func encode(_ w: Wire) throws -> Data {
        let body = try JSONEncoder().encode(w)
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
            msgs.append(try JSONDecoder().decode(Wire.self, from: body))
        }
        return msgs
    }
}

enum WireError: LocalizedError {
    case frameTooLarge(Int)
    var errorDescription: String? {
        switch self {
        case .frameTooLarge(let n): "메시지가 너무 큽니다 (\(n) 바이트)"
        }
    }
}
