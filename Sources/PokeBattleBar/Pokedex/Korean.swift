import Foundation

/// 한국어 조사 선택. 받침(종성) 유무로 은/는, 이/가, 을/를 을 고른다.
enum KO {
    static func hasFinalConsonant(_ s: String) -> Bool {
        guard let last = s.unicodeScalars.last else { return false }
        let v = last.value
        // 한글 완성형 음절: (코드 - 0xAC00) % 28 == 0 이면 받침 없음
        if v >= 0xAC00, v <= 0xD7A3 { return (v - 0xAC00) % 28 != 0 }
        // 숫자는 읽는 소리로 판단 (1·7·8·0 은 받침 있음)
        if let d = last.properties.numericValue, v < 128 {
            return [1, 7, 8, 0].contains(Int(d))
        }
        // 그 밖(영문 등)은 받침 없는 것으로 본다: "HP가", "PP는"
        return false
    }

    /// 이름 + 은/는
    static func t(_ s: String) -> String { s + (hasFinalConsonant(s) ? "은" : "는") }
    /// 이름 + 이/가
    static func s(_ s: String) -> String { s + (hasFinalConsonant(s) ? "이" : "가") }
    /// 이름 + 을/를
    static func o(_ s: String) -> String { s + (hasFinalConsonant(s) ? "을" : "를") }
}
