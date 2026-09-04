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

/// 중계기가 돌려주는 프레임.
///
/// 호스트는 **두 번** 받는다: 방이 등록됐을 때(`registered`), 그리고 상대가
/// 들어왔을 때(`paired`). 게스트는 짝이 맞는 순간 한 번 받는다.
/// 그래서 호스트는 "등록됐다" 와 "상대가 왔다" 를 구분해 화면에 띄울 수 있다.
struct RelayReply: Codable, Sendable {
    var ok: Bool
    /// 실패 이유 (방 없음·암호 불일치·이미 찬 방)
    var reason: String?
    var registered: Bool?
    var paired: Bool?
    /// 짝이 된 상대 이름
    var peer: String?

    var isRegistered: Bool { registered == true }
    var isPaired: Bool { paired == true }
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
    static let defaultPort: UInt16 = 51235

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
