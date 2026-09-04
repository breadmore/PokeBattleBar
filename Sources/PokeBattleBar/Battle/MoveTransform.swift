import Foundation

/// **다이맥스·거다이맥스·Z 로 기술이 바뀌는 규칙 — 한 곳에서만 정한다.**
///
/// 예전에는 이 규칙이 두 번 적혀 있었다: 엔진 안(실제로 나가는 기술)과
/// UI 안(버튼에 미리 보여주는 기술). 그런데 UI 쪽은 캐시를 **원래 기술
/// 이름**으로 뒤지고 있어서(`zPreview[def.name]`) 한 번도 맞지 않았다 —
/// 캐시 키는 "max-flare" 인데 "flamethrower" 로 찾았다.
/// 그래서 다이맥스를 눌러도 버튼 이름이 그대로였다.
///
/// 두 곳이 같은 함수를 쓰면 다시 갈라질 수 없다.
enum MoveTransform {

    /// 변신 상태에 따라 실제로 나갈 기술.
    ///
    /// - Parameters:
    ///   - declaring: 이번 턴 **선언만 해둔** 변신 (UI 미리보기용).
    ///     엔진은 이미 상태가 반영돼 있으므로 nil 을 넘긴다.
    static func resolve(move: MoveDef,
                        battler b: Battler,
                        declaring: SpecialKind?,
                        maxMoves: [String: MoveDef],
                        zMoves: [String: MoveDef]) -> MoveDef {
        let dynamaxed = b.isDynamaxed
            || declaring == .dynamax || declaring == .gmax
        let giga = b.isGigantamaxed || declaring == .gmax

        if dynamaxed {
            // 변화기는 전부 맥스가드가 된다
            if move.damageClass == .status {
                guard var g = maxMoves[FormTables.maxGuard] else { return move }
                g.pp = move.pp
                return g
            }
            // 거다이맥스 전용기 — 기술 타입이 전용기 타입과 같을 때만
            if giga, let g = b.gmaxMove ?? GMaxMove.forSpecies(b.speciesID),
               g.type == move.type {
                var gm = move
                gm.name = "gmax-" + g.rawValue
                gm.koName = g.ko
                gm.power = FormTables.maxPower(basePower: move.power ?? 0, type: move.type)
                gm.accuracy = nil
                gm.specialDamage = .none
                gm.selfKO = false
                gm.ailment = .none
                gm.statChanges = []
                return gm
            }
            guard let name = FormTables.maxMove[move.type],
                  var mx = maxMoves[name] else { return move }
            mx.power = FormTables.maxPower(basePower: move.power ?? 0, type: move.type)
            mx.damageClass = move.damageClass      // 물리/특수는 원래 기술을 따른다
            mx.accuracy = nil                      // 맥스 기술은 빗나가지 않는다
            mx.specialDamage = .none
            mx.selfKO = false                      // 다이맥스 중 대폭발은 자폭하지 않는다
            return mx
        }

        guard declaring == .zMove else { return move }

        // 전용 Z크리스탈 — 타입 제한 없이 자기 공격기를 Z기술로 만든다.
        // 이름은 Showdown 이 알려준다 ("Genesis Supernova") — 예전에는
        // "전용 Z크리스탈 Z기술" 이라는 자리표시자를 보여줬다.
        if b.hasSignatureZ, move.damageClass != .status, move.isDamaging {
            var sz = move
            sz.koName = signatureZName(item: b.heldItem?.name)
                ?? ((b.heldItem?.display ?? "전용 Z") + " Z기술")
            sz.power = FormTables.zPower(basePower: move.power ?? 0)
            sz.accuracy = nil
            sz.specialDamage = .none
            sz.selfKO = false
            return sz
        }
        guard let zn = FormTables.zMoveName(for: move), var z = zMoves[zn] else { return move }
        z.power = FormTables.zPower(basePower: move.power ?? 0)
        z.damageClass = move.damageClass
        z.accuracy = nil
        z.specialDamage = .none
        z.selfKO = false
        return z
    }

    /// 전용 Z기술의 이름 ("Genesis Supernova").
    /// Showdown 의 도구 데이터에 그대로 들어 있다.
    static func signatureZName(item: String?) -> String? {
        guard let item, let sd = Showdown.item(item) else { return nil }
        // zMove 가 문자열이면 전용 Z기술 이름이다 (타입 Z 는 1 만 들어 있다)
        return sd.signatureZMoveName
    }
}
