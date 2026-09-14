import Foundation

/// 중계 서버(라즈베리파이 등)를 거쳐 만나기.
///
/// **왜 필요한가**: Bonjour 는 링크 로컬이라 라우터를 넘지 못하고, 주소로 직접
/// 붙는 방법(`DirectConnect`)은 **방장 쪽에 포트가 열려 있어야** 한다. 양쪽이
/// 각자의 NAT 뒤에 있으면 어느 쪽도 들어갈 수 없다.
///
/// 중계는 이걸 뒤집는다 — **양쪽이 모두 밖으로 나가는 연결**을 걸고, 중계기가
/// 둘을 짝지어 바이트를 흘려준다. 포트를 열어야 하는 곳은 중계기 한 대뿐이다.
///
/// ## 중계기는 게임을 모른다
///
/// 핸드셰이크를 `Wire` 와 **일부러 분리했다.** 짝이 맞은 뒤로 중계기는 바이트를
/// 그대로 흘리기만 하므로:
///  - 버전 협상(`VersionProbe`)은 예전처럼 **두 앱 사이에서** 끝난다.
///    한쪽만 업데이트하면 지금과 똑같이 "상대가 구버전입니다" 가 뜬다.
///  - 앱 프로토콜(v12 …)을 올려도 **중계기를 다시 배포할 필요가 없다.**
///  - 중계기에 게임 규칙이 들어가지 않으므로 권위는 계속 호스트 쪽 엔진에만 있다.
enum RelayRole: String, Codable, Sendable {
    /// 방을 등록하고 기다린다 (엔진을 돌리는 쪽)
    case host
    /// 방 코드로 찾아 들어간다
    case guest
    /// 로비에 상주해서 "누가 있는지 · 어떤 방이 열렸는지" 를 받는다.
    ///
    /// **배틀 연결과 별개의 연결이다.** 배틀 연결은 짝이 맞는 순간 바이트만
    /// 흘리는 파이프가 되므로 그 위에 로비를 얹을 수 없다.
    case lobby
}

/// 접속 직후 중계기에 보내는 첫 프레임
struct RelayHello: Codable, Sendable {
    var role: RelayRole
    /// 방 코드. 호스트가 정하고, 게스트는 같은 값을 적어야 만난다.
    var room: String
    /// 화면에 보여줄 이름
    var name: String
    /// 중계기 접속 암호. 중계기가 요구하지 않으면 nil.
    var secret: String?
}

// (중계기가 보내는 프레임은 아래 RelayServerFrame 하나로 다룬다 —
//  등록 응답·짝 맞춤·로비 스냅샷이 같은 스트림으로 온다)

// MARK: - 중계 로비

/// 중계기가 주기적으로 밀어주는 로비 상황.
///
/// **로컬 네트워크 로비(Bonjour)와 섞지 않는다** — 출처가 다르고, 할 수 있는
/// 것도 다르다(중계 로비에서는 방 코드로 들어가고, 로컬에서는 초대를 보낸다).
struct RelayLobbySnapshot: Codable, Sendable {
    var peers: [Peer] = []
    var rooms: [Room] = []

    struct Peer: Codable, Sendable, Identifiable, Equatable {
        var name: String
        var status: String
        /// 방을 열어둔 사람이면 그 방 코드
        var room: String?

        var id: String { name }
        var state: PeerStatus { PeerStatus(rawValue: status) ?? .free }
    }

    struct Room: Codable, Sendable, Identifiable, Equatable {
        var code: String
        var host: String
        /// 기다린 시간 (초)
        var waiting: Int

        var id: String { code }
    }
}

/// 로비 연결에서 앱이 중계기로 보내는 프레임.
/// 핸드셰이크 뒤에 오가는 것이라 `type` 으로 구분한다.
struct RelayClientFrame: Codable, Sendable {
    var type: String
    var status: String?
    var room: String?
    /// 초대·거절을 받을 상대 이름
    var to: String?

    static func status(_ s: PeerStatus, room: String?) -> RelayClientFrame {
        RelayClientFrame(type: "status", status: s.rawValue, room: room)
    }
    static let ping = RelayClientFrame(type: "ping")
    static func invite(to peer: String, room: String) -> RelayClientFrame {
        RelayClientFrame(type: "invite", room: room, to: peer)
    }
    static func decline(to peer: String) -> RelayClientFrame {
        RelayClientFrame(type: "decline", to: peer)
    }
}

/// 중계기가 보내는 프레임 — 세 가지가 같은 스트림으로 온다.
///
///  - 등록됐다 (`registered`). 방을 연 호스트, 그리고 로비 상주자가 받는다.
///  - 짝이 맞았다 (`paired` + `peer`). 배틀 연결에서 이 뒤로는 게임 스트림이다.
///  - 로비 상황 (`type: "lobby"`). 로비 연결에 주기적으로 온다.
///
/// 하나의 타입으로 받는 이유는 프레임을 미리 구분할 수 없기 때문이다 —
/// 호스트는 등록 응답 뒤에 짝 맞춤을 기다리고, 로비는 등록 응답 뒤에
/// 스냅샷을 계속 받는다.
struct RelayServerFrame: Codable, Sendable {
    var type: String?
    var ok: Bool?
    /// 실패 이유 (방 없음·암호 불일치·이미 찬 방)
    var reason: String?
    var registered: Bool?
    var paired: Bool?
    /// 짝이 된 상대 이름, 또는 초대를 보낸/거절한 사람
    var peer: String?
    /// 초대에 실린 방 코드
    var room: String?
    var peers: [RelayLobbySnapshot.Peer]?
    var rooms: [RelayLobbySnapshot.Room]?

    var isLobbyUpdate: Bool { type == "lobby" }
    var isRejection: Bool { ok == false }
    var isRegistered: Bool { registered == true }
    var isPaired: Bool { paired == true }
    /// 로비 연결에서 오는 것인가 (스냅샷·초대·거절·전달 실패)
    var isLobbyEvent: Bool { type != nil }

    var snapshot: RelayLobbySnapshot {
        RelayLobbySnapshot(peers: peers ?? [], rooms: rooms ?? [])
    }
}

/// 핸드셰이크 프레이밍. `WireCodec` 과 같은 형식(길이 4바이트 빅엔디안 + JSON)
/// 이지만 **버전 봉투가 없다** — 중계기가 앱 버전을 알 필요가 없기 때문이다.
enum RelayCodec {
    /// 핸드셰이크는 작다. 게임 프레임(4MB)과 달리 넉넉하게 잡을 이유가 없고,
    /// 상한이 작아야 중계기 앞에서 쓰레기 데이터를 일찍 끊을 수 있다.
    static let maxFrame = 64 * 1024

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let body = try JSONEncoder().encode(value)
        guard body.count <= maxFrame else { throw RelayError.frameTooLarge(body.count) }
        var out = Data()
        var len = UInt32(body.count).bigEndian
        withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
        out.append(body)
        return out
    }

    /// 버퍼에서 프레임 **하나**를 꺼낸다. 아직 다 안 왔으면 nil (버퍼는 그대로).
    ///
    /// 하나씩 꺼내는 것이 중요하다 — 핸드셰이크가 끝나는 순간 남은 바이트는
    /// 이미 게임 스트림이므로, 그건 `WireCodec` 이 읽어야 한다.
    static func decode<T: Decodable>(_ type: T.Type, from buffer: inout Data) throws -> T? {
        guard buffer.count >= 4 else { return nil }
        let len = buffer.prefix(4).withUnsafeBytes {
            UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self))
        }
        guard len <= UInt32(maxFrame) else { throw RelayError.frameTooLarge(Int(len)) }
        let total = 4 + Int(len)
        guard buffer.count >= total else { return nil }
        let body = buffer.subdata(in: 4..<total)
        buffer.removeSubrange(0..<total)
        return try JSONDecoder().decode(T.self, from: body)
    }
}

enum RelayError: LocalizedError {
    case frameTooLarge(Int)
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .frameTooLarge(let n): "중계 핸드셰이크가 너무 큽니다 (\(n) 바이트)"
        case .rejected(let why):    "중계 서버가 거절했습니다: \(why)"
        }
    }
}

/// 중계 서버 접속 설정. 방 코드는 사람이 받아 적을 수 있어야 한다.
enum RelayConfig {
    /// 중계기 기본 포트. 방 포트(51234)와 겹치지 않게 다른 번호를 쓴다 —
    /// 한 대에서 중계기와 앱을 같이 돌릴 수 있어야 진단이 편하다.
    static let defaultPort: UInt16 = 47474

    /// 사람이 받아 적기 쉬운 방 코드를 만든다.
    /// 헷갈리는 글자(0/O, 1/I/L)를 뺀다 — 전화로 알려줄 수도 있다.
    static func makeRoomCode(length: Int = 5) -> String {
        let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        return String((0..<length).compactMap { _ in alphabet.randomElement() })
    }

    /// 입력한 방 코드를 정규화한다 (대소문자·공백 무시).
    static func normalize(room: String) -> String {
        room.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
