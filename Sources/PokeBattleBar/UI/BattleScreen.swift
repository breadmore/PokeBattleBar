import SwiftUI

/// 배틀 화면 — "게임보이 계승" 방향.
///
/// 원작 배틀 화면의 **문법**을 따른다 (에셋은 쓸 수 없으므로 다시 그린다):
/// 위 3분의 2는 무대, 아래는 텍스트 상자. 모서리가 깎인 HP 판, 타원 무대,
/// ▼ 커서. 그리고 원작의 규칙 하나 — **내 HP 만 숫자로 보이고 상대는
/// 막대만 보인다.**
enum GB {
    // 판·상자 (부드러운 베이지 판 위 남색 선).
    //
    // **완전한 흰색을 쓰지 않는다** — 눈이 피로하고, 원작의 종이 같은 질감과도
    // 멀다. 판은 살짝 따뜻한 베이지, 그 위는 짙은 남색 잉크다.
    static let plate = Color(red: 0.965, green: 0.941, blue: 0.878)
    /// 판보다 한 단 밝은 면 (입력칸·행 강조)
    static let plateHi = Color(red: 0.984, green: 0.969, blue: 0.925)
    /// 판보다 한 단 어두운 면 (창 바탕)
    static let ground = Color(red: 0.925, green: 0.894, blue: 0.816)
    static let ink = Color(red: 0.110, green: 0.169, blue: 0.290)
    static let inkSoft = Color(red: 0.420, green: 0.463, blue: 0.537)
    static let hilite = Color(red: 0.784, green: 0.220, blue: 0.180)

    // 무대
    static let sky = Color(red: 0.749, green: 0.902, blue: 0.949)
    static let far = Color(red: 0.851, green: 0.941, blue: 0.894)
    static let field = Color(red: 0.812, green: 0.890, blue: 0.706)
    static let fieldDeep = Color(red: 0.737, green: 0.843, blue: 0.612)

    static let hpGreen = Color(red: 0.298, green: 0.769, blue: 0.478)
    static let hpAmber = Color(red: 0.910, green: 0.706, blue: 0.271)
    static let hpRed = Color(red: 0.941, green: 0.408, blue: 0.361)

    static func hpColor(_ ratio: Double) -> Color {
        ratio > 0.5 ? hpGreen : (ratio > 0.2 ? hpAmber : hpRed)
    }

    /// 둥근 서체가 원작 느낌에 가깝다. 한글은 시스템 폰트가 받아준다.
    static func face(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// 타입 색 — 취향이 아니라 데이터다
    static func typeColor(_ t: PType) -> Color {
        switch t {
        case .normal:   Color(red: 0.60, green: 0.60, blue: 0.45)
        case .fire:     Color(red: 0.93, green: 0.51, blue: 0.19)
        case .water:    Color(red: 0.39, green: 0.56, blue: 0.94)
        case .electric: Color(red: 0.88, green: 0.74, blue: 0.11)
        case .grass:    Color(red: 0.42, green: 0.72, blue: 0.27)
        case .ice:      Color(red: 0.45, green: 0.78, blue: 0.77)
        case .fighting: Color(red: 0.76, green: 0.18, blue: 0.16)
        case .poison:   Color(red: 0.64, green: 0.24, blue: 0.63)
        case .ground:   Color(red: 0.87, green: 0.75, blue: 0.41)
        case .flying:   Color(red: 0.66, green: 0.56, blue: 0.95)
        case .psychic:  Color(red: 0.98, green: 0.33, blue: 0.53)
        case .bug:      Color(red: 0.65, green: 0.72, blue: 0.10)
        case .rock:     Color(red: 0.71, green: 0.63, blue: 0.21)
        case .ghost:    Color(red: 0.45, green: 0.34, blue: 0.59)
        case .dragon:   Color(red: 0.44, green: 0.21, blue: 0.98)
        case .dark:     Color(red: 0.44, green: 0.34, blue: 0.27)
        case .steel:    Color(red: 0.72, green: 0.72, blue: 0.81)
        case .fairy:    Color(red: 0.85, green: 0.52, blue: 0.68)
        }
    }
}

/// 모서리가 하나 깎인 판 — 원작 HP 판의 실루엣
struct GBPlateShape: Shape {
    /// 깎인 모서리의 위치
    enum Corner { case bottomLeading, topTrailing }
    var corner: Corner
    var cut: CGFloat = 16

    func path(in r: CGRect) -> Path {
        var p = Path()
        switch corner {
        case .bottomLeading:
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX + cut, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY - cut))
        case .topTrailing:
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - cut, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + cut))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        }
        p.closeSubpath()
        return p
    }
}

/// 타입 배지
struct GBTypeBadge: View {
    let type: PType
    var size: CGFloat = 9

    var body: some View {
        Text(type.ko)
            .font(.system(size: size, weight: .heavy))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.3), radius: 0, y: 0.5)
            .padding(.horizontal, size * 0.55).padding(.vertical, size * 0.2)
            .background(RoundedRectangle(cornerRadius: 3).fill(GB.typeColor(type)))
    }
}

/// 원작식 HP 막대 — 남색 테두리 안에 색 막대
struct GBHPBar: View {
    let current: Int
    let max: Int
    var height: CGFloat = 8

    private var ratio: Double { max <= 0 ? 0 : Swift.max(0, Double(current) / Double(max)) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(GB.ink)
                Capsule()
                    .fill(GB.hpColor(ratio))
                    .frame(width: Swift.max(0, (geo.size.width - height * 0.34) * ratio))
                    .padding(height * 0.17)
                    // HP 가 깎이는 걸 눈으로 볼 수 있게
                    .animation(.easeOut(duration: 0.5), value: ratio)
            }
        }
        .frame(height: height)
    }
}

/// HP 판. 원작 규칙대로 **상대는 숫자를 보여주지 않는다.**
struct GBHPPanel: View {
    let b: Battler
    let isFoe: Bool
    /// 남은 포켓몬 표시
    let remaining: Int
    let total: Int

    @State private var shownHP = -1

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(b.name)
                    .font(GB.face(15))
                    .foregroundStyle(GB.ink)
                if b.isShiny { Text("✨").font(.system(size: 10)) }
                Text("Lv.\(b.level)")
                    .font(GB.face(11, .semibold).monospacedDigit())
                    .foregroundStyle(GB.inkSoft)
                Spacer(minLength: 4)
                HStack(spacing: 2) {
                    ForEach(b.types, id: \.self) { GBTypeBadge(type: $0, size: 8) }
                }
            }

            HStack(spacing: 5) {
                Text("HP")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(GB.hilite)
                GBHPBar(current: b.currentHP, max: b.maxHP)
            }

            HStack(spacing: 5) {
                // 내 포켓몬만 숫자를 본다 (원작 규칙)
                if !isFoe {
                    Text("\(shownHP < 0 ? b.currentHP : shownHP) / \(b.maxHP)")
                        .font(GB.face(11, .semibold).monospacedDigit())
                        .foregroundStyle(GB.ink)
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.5), value: shownHP)
                }
                if b.status != .none {
                    Text(b.status.ko)
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 2).fill(GB.hilite))
                }
                Spacer(minLength: 2)
                // 남은 포켓몬 — 볼 점으로
                HStack(spacing: 2) {
                    ForEach(0..<total, id: \.self) { i in
                        Circle()
                            .fill(i < remaining ? GB.ink : GB.ink.opacity(0.22))
                            .frame(width: 5, height: 5)
                    }
                }
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .frame(width: 232)
        .background(
            GBPlateShape(corner: isFoe ? .bottomLeading : .topTrailing)
                .fill(GB.plate)
                .shadow(color: GB.ink.opacity(0.22), radius: 0, x: 3, y: 3)
        )
        .overlay(
            GBPlateShape(corner: isFoe ? .bottomLeading : .topTrailing)
                .stroke(GB.ink, lineWidth: 2.5)
        )
        .onAppear { shownHP = b.currentHP }
        .onChange(of: b.currentHP) { _, new in shownHP = new }
    }
}

/// 무대 위의 포켓몬 — 타원 그림자를 밟고 선다
struct GBStageMon: View {
    let b: Battler
    let isFoe: Bool
    var spriteSize: CGFloat = 112

    var body: some View {
        VStack(spacing: -spriteSize * 0.12) {
            SpriteView(speciesID: b.speciesID, shiny: b.isShiny, size: spriteSize,
                       form: b.spriteForm, scale: b.spriteScale)
                // PokéAPI 프론트 스프라이트는 기본이 **왼쪽을 보는** 방향이다.
                // 상대(오른쪽 위)는 그대로 두면 나를 보고, 내 포켓몬(왼쪽 아래)은
                // 뒤집어야 상대를 본다. 뒤집는 쪽이 반대면 서로 등을 돌린다.
                .scaleEffect(x: isFoe ? 1 : -1, y: 1)
                .opacity(b.isFainted ? 0.2 : 1)
                .modifier(HitEffect(hp: b.currentHP, fainted: b.isFainted))
                .overlay {
                    if b.isDynamaxed {
                        Circle().stroke(Color.pink.opacity(0.55), lineWidth: 3)
                            .blur(radius: 5).scaleEffect(1.12)
                    } else if b.isMega {
                        Circle().stroke(Color.purple.opacity(0.5), lineWidth: 3)
                            .blur(radius: 5).scaleEffect(1.06)
                    }
                }
                // 등장할 때 아래에서 올라온다
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(b.id)

            Ellipse()
                .fill(GB.ink.opacity(0.14))
                .frame(width: spriteSize * 0.86, height: spriteSize * 0.2)
        }
    }
}

/// 무대 — 하늘과 들판, 그 위에 판과 포켓몬
struct GBStage: View {
    let model: AppModel
    let me: SideState
    let foe: SideState

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: GB.sky, location: 0),
                    .init(color: GB.far, location: 0.55),
                    .init(color: GB.field, location: 0.5501),
                    .init(color: GB.fieldDeep, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            // 지평선
            .overlay(alignment: .top) {
                GeometryReader { g in
                    Rectangle().fill(GB.ink.opacity(0.13))
                        .frame(height: 1)
                        .offset(y: g.size.height * 0.55)
                }
            }

            GeometryReader { g in
                let w = g.size.width, h = g.size.height

                // 상대: 판은 왼쪽 위, 포켓몬은 오른쪽 위
                GBHPPanel(b: foe.active, isFoe: true,
                          remaining: foe.remaining, total: foe.team.count)
                    .position(x: 132, y: 46)

                GBStageMon(b: foe.active, isFoe: true, spriteSize: min(112, h * 0.34))
                    .position(x: w - min(150, w * 0.24), y: h * 0.31)

                // 나: 포켓몬은 왼쪽 아래, 판은 오른쪽 아래
                GBStageMon(b: me.active, isFoe: false, spriteSize: min(126, h * 0.38))
                    .position(x: min(158, w * 0.25), y: h * 0.68)

                GBHPPanel(b: me.active, isFoe: false,
                          remaining: me.remaining, total: me.team.count)
                    .position(x: w - 132, y: h - 46)
            }

            // 진행 배너 — 지금 무슨 일이 벌어지는지
            if !model.playbackBannerLines.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.playbackBannerLines.enumerated()), id: \.offset) { i, line in
                        Text(line)
                            // 첫 줄은 누가 무엇을 했는지, 나머지는 그 결과
                            .font(GB.face(i == 0 ? 14 : 12, i == 0 ? .bold : .semibold))
                            .foregroundStyle(i == 0 ? GB.plate : GB.plate.opacity(0.82))
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12).fill(GB.ink.opacity(0.88))
                )
                .transition(.scale(scale: 0.94).combined(with: .opacity))
                .id(model.playbackBanner ?? "")
            }
        }
        .animation(.easeOut(duration: 0.25), value: model.playbackBanner)
        .clipped()
    }
}

/// 아래쪽 텍스트 상자 — 원작처럼 화면의 3분의 1을 차지한다
struct GBTextBox<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .foregroundStyle(GB.ink)
            .padding(.horizontal, 18).padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GB.plate)
            .overlay(alignment: .top) {
                Rectangle().fill(GB.ink).frame(height: 2.5)
            }
    }
}

/// 기술 하나 — 타입 점, 이름, PP, 상성
struct GBMoveRow: View {
    let slot: Battler.MoveSlot
    let eff: Effectiveness?
    let selected: Bool
    let transformNote: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle()
                    .fill(GB.typeColor(slot.def.type))
                    .frame(width: 8, height: 8)
                Text(slot.def.display)
                    .font(GB.face(13))
                    .lineLimit(1)
                if let transformNote {
                    Text(transformNote)
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3).padding(.vertical, 0.5)
                        .background(RoundedRectangle(cornerRadius: 2).fill(GB.hilite))
                }
                Spacer(minLength: 4)
                if let eff, let effLabel = eff.label {
                    Text(effLabel)
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(effColor(eff))
                }
                Text("\(slot.ppLeft)/\(slot.def.pp)")
                    .font(GB.face(10, .semibold).monospacedDigit())
                    .foregroundStyle(selected ? GB.plate.opacity(0.8) : GB.inkSoft)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(selected ? GB.ink : Color.clear)
            )
            .foregroundStyle(selected ? GB.plate : GB.ink)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!slot.usable)
        .opacity(slot.usable ? 1 : 0.4)
    }

    private func effColor(_ e: Effectiveness) -> Color {
        if e.multiplier == 0 { return GB.inkSoft }
        return e.multiplier > 1 ? GB.hpGreen : GB.hilite
    }
}

/// 텍스트 상자 안의 선택 화면.
///
/// 원작 구성: 왼쪽에 "무엇을 할까?" 와 고른 기술의 설명, 오른쪽에 기술 2×2.
/// 변신 선언(메가·다이맥스·Z)은 원작에 없는 것이라 왼쪽 아래에 붙인다 —
/// 기술을 고르는 순간 함께 발동하므로 기술 옆에 있는 게 맞다.
struct GBChoicePanel: View {
    let model: AppModel
    let me: SideState

    /// 마우스를 올린 기술 — 왼쪽 설명이 그걸 따라간다
    @State private var hovered: Int?

    private var foeTypes: [PType] { model.foeState?.active.types ?? [] }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 4) {
                    Text(me.active.name).font(GB.face(17)).foregroundStyle(GB.hilite)
                    Text("은 무엇을 할까?").font(GB.face(17)).foregroundStyle(GB.ink)
                    BlinkingCursor()
                }

                if let detail = detailLine {
                    Text(detail)
                        .font(GB.face(11, .semibold))
                        .foregroundStyle(GB.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
                GBSpecialRow(model: model)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 3) {
                let moves = Array(me.active.moves.enumerated())
                ForEach(Array(stride(from: 0, to: moves.count, by: 2)), id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(moves[row..<min(row + 2, moves.count)], id: \.offset) { idx, slot in
                            let shown = preview(slot)
                            GBMoveRow(
                                slot: shown,
                                eff: Effectiveness.compute(move: shown.def,
                                                           attacker: previewAttacker,
                                                           defenderTypes: foeTypes,
                                                           chart: model.typeChart),
                                selected: hovered == idx,
                                transformNote: note(for: slot)
                            ) {
                                model.submitMove(idx)
                            }
                            .onHover { inside in hovered = inside ? idx : (hovered == idx ? nil : hovered) }
                        }
                        if moves[row..<min(row + 2, moves.count)].count == 1 {
                            Spacer().frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .frame(width: 340)
        }
        .frame(minHeight: 108)
    }

    /// 고른(또는 올려둔) 기술의 설명 한 줄
    private var detailLine: String? {
        guard let i = hovered, me.active.moves.indices.contains(i) else {
            if let p = model.pendingSpecial {
                return "\(p.ko) 선언됨 — 기술을 고르면 함께 발동합니다"
            }
            return "기술을 고르세요. 위에 마우스를 올리면 상성이 보입니다."
        }
        let shown = preview(me.active.moves[i])
        let d = shown.def
        var parts: [String] = [d.type.ko]
        parts.append(d.power.map { "위력 \($0)" } ?? "변화기")
        if let acc = d.accuracy { parts.append("명중 \(acc)") }
        parts.append("PP \(me.active.moves[i].ppLeft)/\(d.pp)")

        var line = parts.joined(separator: " · ")
        let eff = Effectiveness.compute(move: d, attacker: previewAttacker,
                                        defenderTypes: foeTypes, chart: model.typeChart)
        if let word = eff.sentence { line += "\n" + word }
        if eff.stab { line += eff.sentence == nil ? "\n자기 타입 일치 (1.5배)" : "  자기 타입 일치" }
        return line
    }

    /// 변신을 선언했으면 그 상태의 나로 상성을 계산해야 한다 (타입이 바뀐다)
    private var previewAttacker: Battler {
        var b = me.active
        if case .mega(let form) = model.pendingSpecial,
           let stats = model.megaFormPreview[form] {
            b.types = stats.types
        }
        return b
    }

    /// 다이맥스/Z 를 선언하면 기술 이름과 위력이 바뀐다 — 미리 보여준다
    private func preview(_ slot: Battler.MoveSlot) -> Battler.MoveSlot {
        guard let t = transformed(slot.def) else { return slot }
        return Battler.MoveSlot(def: t, ppLeft: slot.ppLeft)
    }

    private func transformed(_ def: MoveDef) -> MoveDef? {
        guard let p = model.pendingSpecial else { return nil }
        switch p {
        case .dynamax, .gmax, .zMove:
            return model.zPreview[def.name]
        case .mega:
            return nil
        }
    }

    private func note(for slot: Battler.MoveSlot) -> String? {
        guard let p = model.pendingSpecial, transformed(slot.def) != nil else { return nil }
        switch p {
        case .dynamax: return "다이맥스"
        case .gmax:    return "거다이맥스"
        case .zMove:   return "Z"
        case .mega:    return nil
        }
    }
}

/// ▼ 커서 — 원작에서 다음을 기다릴 때 깜빡이는 그것
struct BlinkingCursor: View {
    @State private var on = true

    var body: some View {
        Text("▼")
            .font(.system(size: 11, weight: .black))
            .foregroundStyle(GB.hilite)
            .opacity(on ? 1 : 0)
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(560))
                    on.toggle()
                }
            }
    }
}

/// 변신 선언 줄 — 각 배틀당 1회라는 규칙을 그대로 보여준다
struct GBSpecialRow: View {
    let model: AppModel

    var body: some View {
        let relevant = SpecialKind.allCases.filter {
            model.canUse($0) || model.alreadyUsed($0) || model.missingItem($0) != nil
        }
        if !relevant.isEmpty {
            HStack(spacing: 5) {
                ForEach(relevant, id: \.self) { kind in
                    GBSpecialChip(model: model, kind: kind)
                }
                // 메가 폼이 둘인 포켓몬은 어느 쪽인지 고른다
                if model.canUse(.mega), let forms = model.myState?.active.megaForms,
                   forms.count > 1 {
                    ForEach(forms, id: \.self) { f in
                        Button(model.megaFormLabel(f)) { model.selectMegaForm(f) }
                            .font(.system(size: 9, weight: .bold))
                            .buttonStyle(.bordered).controlSize(.mini)
                    }
                }
            }
        }
    }
}

struct GBSpecialChip: View {
    let model: AppModel
    let kind: SpecialKind

    var body: some View {
        let usable = model.canUse(kind)
        let used = model.alreadyUsed(kind)
        let lacking = model.missingItem(kind)
        let selected = model.pendingSpecial.map { model.kindOf($0) == kind } ?? false

        Button {
            model.toggleSpecial(kind)
        } label: {
            HStack(spacing: 3) {
                Text(kind.icon).font(.system(size: 9))
                Text(kind.ko).font(.system(size: 10, weight: .heavy))
                if used {
                    Text("사용함").font(.system(size: 8, weight: .bold))
                } else if lacking != nil {
                    Text("도구 없음").font(.system(size: 8, weight: .bold))
                }
            }
            .padding(.horizontal, 7).padding(.vertical, 3.5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(selected ? GB.hilite : (usable ? GB.hpAmber.opacity(0.28) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(selected ? GB.hilite : GB.ink.opacity(usable ? 0.5 : 0.22),
                            lineWidth: 1.2)
            )
            .foregroundStyle(selected ? GB.plate : (usable ? GB.ink : GB.inkSoft))
        }
        .buttonStyle(.plain)
        .disabled(!usable)
        .help(helpText(used: used, usable: usable, lacking: lacking))
    }

    private func helpText(used: Bool, usable: Bool, lacking: String?) -> String {
        if used { return "이번 배틀에서 이미 사용했습니다" }
        if usable { return "이번 턴에 \(kind.ko)을 선언합니다" }
        if let lacking {
            return "\(lacking)을 지니고 있지 않아 \(kind.ko)을 쓸 수 없습니다 — 로비에서 도구를 끼워주세요"
        }
        return "이 포켓몬은 \(kind.ko)을 쓸 수 없습니다"
    }
}

/// 밝은 판 위에 올리는 화면에 붙인다.
///
/// **글자색을 반드시 함께 지정해야 한다.** 배경만 밝게 하면 다크모드에서
/// 시스템 기본 글자색(흰색)이 그대로 나와 흰 판에 흰 글씨가 된다 —
/// 실제로 그렇게 만들어서 아무것도 안 보였다.
struct GBSurface: ViewModifier {
    var ground: Color = GB.ground

    func body(content: Content) -> some View {
        content
            .foregroundStyle(GB.ink)        // ← 이것이 빠지면 흰 글씨가 된다
            .tint(GB.hilite)
            .background(ground)
            .environment(\.colorScheme, .light)   // 컨트롤(체크박스·버튼)도 밝은 판에 맞춘다
    }
}

extension View {
    /// 밝은 베이지 판 위의 화면
    func gbSurface(_ ground: Color = GB.ground) -> some View {
        modifier(GBSurface(ground: ground))
    }
}

/// 로비의 판. 배틀 화면과 같은 문법 — 베이지 판, 남색 선, 그림자 없는 오프셋.
struct GBPanel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                // 제목 앞의 표식 — 원작 메뉴의 ▶ 커서 자리
                Text("▶")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(GB.hilite)
                Text(title)
                    .font(GB.face(15))
                    .foregroundStyle(GB.ink)
                Spacer(minLength: 0)
            }
            content
        }
        .foregroundStyle(GB.ink)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(GB.plate)
                .shadow(color: GB.ink.opacity(0.16), radius: 0, x: 3, y: 3)
        )
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(GB.ink.opacity(0.85), lineWidth: 2))
    }
}
