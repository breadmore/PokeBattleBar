import Foundation

/// 특수 개체 · 특수 폼 감사.
///
/// PokeTokenBar 도감 범위(#649 이하)의 모든 종을 훑어, 원작에 있는 특수 폼 중
/// **우리가 다루는 것과 다루지 않는 것**을 목록으로 낸다. 하나씩 발견하지 않기
/// 위한 것이다 (원시회귀는 이렇게 찾았다).
enum FormAudit {

    /// 우리가 처리하는 방식
    enum Support: String {
        case mega       = "메가진화 (도구 + 선언)"
        case gmax       = "거다이맥스 (도구 + 선언)"
        case primal     = "원시회귀 (구슬 지니면 자동)"
        case autoForm   = "배틀 중 자동 (특성)"
        case selectable = "사전 선택"
        case regional   = "지역폼 (다른 종 취급 — 제외)"
        case none       = "미지원"
    }

    static func run(upTo maxID: Int, verbose: Bool) async -> Bool {
        print("=== 특수 개체 · 폼 감사 ===\n")
        var ok = true
        func show(_ c: Bool, _ l: String, _ d: String = "") -> Bool {
            print("  \(c ? "✓" : "✗") \(l)\(d.isEmpty ? "" : "  (\(d))")")
            return c
        }

        await ItemCatalog.shared.loadAll()

        // 구슬이 카탈로그에 들어왔는지 먼저 확인한다 — 안 들어오면 노출도 안 된다
        for n in ["red-orb", "blue-orb"] {
            if let it = await ItemCatalog.shared.item(n) {
                print("  \(n): \(it.display) / kind=\(it.kind) / 원시=\(it.isPrimalOrb)")
            } else {
                print("  \(n): 카탈로그에 없음")
            }
        }
        print("")

        var rows: [(id: Int, name: String, form: String, support: Support)] = []
        var scanned = 0

        for id in 1...maxID {
            guard let sp = try? await PokeAPI.shared.species(id) else { continue }
            scanned += 1

            let abils = await AbilityCatalog.shared.abilities(for: sp)
            let autoAbility = abils.contains { FormChange.isAutoAbility($0.name) }
            let selectable = Set(FormChange.selectable(for: sp))
            let orbItems = await ItemCatalog.shared.available(forSpecies: sp)
                .filter(\.isPrimalOrb)

            for form in sp.altForms {
                let s: Support
                if sp.megaForms.contains(form)                { s = .mega }
                else if sp.gmaxForm == form                   { s = .gmax }
                else if form.hasSuffix("-primal")             { s = orbItems.isEmpty ? .none : .primal }
                else if selectable.contains(form)             { s = .selectable }
                else if form.contains("-alola") || form.contains("-galar")
                     || form.contains("-hisui") || form.contains("-paldea") { s = .regional }
                else if autoAbility,
                        FormChange.autoRule(ability: abils.first(where: {
                            FormChange.isAutoAbility($0.name) })?.name ?? "",
                                            speciesID: sp.id) != nil { s = .autoForm }
                else                                          { s = .none }
                rows.append((sp.id, sp.display, form, s))
            }
        }

        print("  훑은 종 \(scanned)개 / 특수 폼 \(rows.count)개\n")
        ok = show(scanned > 300, "도감 범위를 충분히 훑었다", "\(scanned)종") && ok

        // 방식별로 묶어 보여준다
        for kind in [Support.mega, .gmax, .primal, .autoForm, .selectable, .regional, .none] {
            let list = rows.filter { $0.support == kind }
            guard !list.isEmpty else { continue }
            print("-- \(kind.rawValue) — \(list.count)개")
            if kind == .none || verbose {
                for r in list { print("   · \(r.name) → \(r.form)") }
            } else {
                let sample = list.prefix(6).map { "\($0.name)/\($0.form)" }
                print("   \(sample.joined(separator: ", "))\(list.count > 6 ? " …" : "")")
            }
            print("")
        }

        let unsupported = rows.filter { $0.support == .none }
        print("-- 요약 --")
        print("  다루는 폼: \(rows.count - unsupported.count)개")
        print("  아직 다루지 않는 폼: \(unsupported.count)개")

        // 원시회귀는 구슬이 노출돼야 쓸 수 있다
        for (sid, ko) in [(383, "그란돈"), (382, "가이오가")] {
            guard let sp = try? await PokeAPI.shared.species(sid) else { continue }
            let orbs = await ItemCatalog.shared.available(forSpecies: sp).filter(\.isPrimalOrb)
            ok = show(!orbs.isEmpty, "\(ko)에게 원시회귀 구슬이 노출된다",
                      orbs.map(\.display).joined(separator: ", ")) && ok
            let hasPrimal = sp.altForms.contains { $0.hasSuffix("-primal") }
            ok = show(hasPrimal, "\(ko)의 원시 폼이 데이터에 있다") && ok
        }
        // 다른 종에게는 구슬이 보이면 안 된다
        if let snorlax = try? await PokeAPI.shared.species(143) {
            let orbs = await ItemCatalog.shared.available(forSpecies: snorlax).filter(\.isPrimalOrb)
            ok = show(orbs.isEmpty, "관계없는 종에게는 구슬이 안 보인다") && ok
        }

        print(ok ? "\n✓ 통과" : "\n✗ 실패 항목 있음")
        return ok
    }
}
