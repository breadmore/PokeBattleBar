import SwiftUI

/// 지닌 도구 고르기.
///
/// 예전에는 작은 메뉴에 이름만 나열해서, 무슨 도구인지 알려면 하나하나
/// 눌러봐야 했다. 여기서는 **아이콘·한글 설명·추천 표시**를 함께 보여주고
/// 검색으로 좁힐 수 있게 한다.
struct ItemPickerSheet: View {
    let model: AppModel
    let slot: RosterSlot
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var showOnlyRelevant = true

    private var all: [ItemDef] { model.itemsForSpecies[slot.speciesID] ?? [] }
    private var recommended: String? { model.recommendedItemName(for: slot) }
    private var equipped: ItemDef? { model.currentItem(for: slot) }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    noneRow

                    ForEach(groups, id: \.title) { g in
                        Text(g.title)
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(GB.hilite)
                            .padding(.top, 10).padding(.horizontal, 12)
                        ForEach(g.items) { it in
                            ItemPickerRow(
                                item: it,
                                equipped: equipped?.name == it.name,
                                recommended: recommended == it.name
                            ) {
                                Task { await model.setItem(it, for: slot); dismiss() }
                            }
                        }
                    }

                    if groups.isEmpty {
                        Text("찾는 도구가 없습니다.")
                            .font(.callout).foregroundStyle(.secondary)
                            .padding(20)
                    }
                }
                .padding(.bottom, 10)
            }
        }
        .frame(width: 520, height: 560)
        .background(GB.plate)
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                PokeBallIcon(size: 17)
                Text("지닌 도구").font(GB.face(17)).foregroundStyle(GB.ink)
                Text(model.displayName(for: slot))
                    .font(GB.face(12, .semibold)).foregroundStyle(GB.inkSoft)
                Spacer()
                Button("닫기") { dismiss() }
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(GB.inkSoft)
                TextField("도구 이름이나 설명으로 검색", text: $query)
                    .textFieldStyle(.plain)
                    .font(GB.face(13, .medium))
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(GB.inkSoft)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(GB.ink.opacity(0.25), lineWidth: 1.5))

            Toggle(isOn: $showOnlyRelevant) {
                Text("이 포켓몬에게 의미 있는 것만")
                    .font(.system(size: 11))
            }
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)
        .foregroundStyle(GB.ink)
    }

    private var noneRow: some View {
        Button {
            Task { await model.setItem(nil, for: slot); dismiss() }
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(GB.ink.opacity(0.08))
                    .frame(width: 30, height: 30)
                    .overlay { Image(systemName: "slash.circle").foregroundStyle(GB.inkSoft) }
                VStack(alignment: .leading, spacing: 1) {
                    Text("도구 없음").font(GB.face(13))
                    Text("아무것도 지니지 않습니다")
                        .font(.system(size: 10)).foregroundStyle(GB.inkSoft)
                }
                Spacer()
                if equipped == nil {
                    Image(systemName: "checkmark").foregroundStyle(GB.hilite).font(.callout.bold())
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(GB.ink)
    }

    private struct Group {
        var title: String
        var items: [ItemDef]
    }

    /// 카테고리별로 묶는다. 변신 도구를 맨 위에 두는 게 실제로 제일 자주 찾는 것이다.
    private var groups: [Group] {
        var pool = all
        if showOnlyRelevant {
            pool = pool.filter { $0.kind != .none }
        }
        if !query.isEmpty {
            let q = query.lowercased()
            pool = pool.filter {
                $0.display.lowercased().contains(q)
                || $0.name.lowercased().contains(q)
                || $0.description.lowercased().contains(q)
            }
        }
        var transform: [ItemDef] = [], berry: [ItemDef] = [], other: [ItemDef] = []
        for it in pool {
            if it.isTransformItem { transform.append(it) }
            else if it.isBerry { berry.append(it) }
            else { other.append(it) }
        }
        func sorted(_ a: [ItemDef]) -> [ItemDef] { a.sorted { $0.display < $1.display } }
        var out: [Group] = []
        if !transform.isEmpty { out.append(Group(title: "변신 도구 — 메가·다이맥스·Z", items: sorted(transform))) }
        if !other.isEmpty { out.append(Group(title: "배틀 도구", items: sorted(other))) }
        if !berry.isEmpty { out.append(Group(title: "나무열매", items: sorted(berry))) }
        return out
    }
}

struct ItemPickerRow: View {
    let item: ItemDef
    let equipped: Bool
    let recommended: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                ItemIcon(item: item, size: 30)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(item.display).font(GB.face(13))
                        if recommended {
                            Text("실전 추천")
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 3).fill(GB.hpGreen))
                        }
                    }
                    Text(item.description.isEmpty ? "설명이 없습니다" : item.description)
                        .font(.system(size: 10))
                        .foregroundStyle(GB.inkSoft)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if equipped {
                    Image(systemName: "checkmark").foregroundStyle(GB.hilite).font(.callout.bold())
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(equipped ? GB.hpAmber.opacity(0.22) : .clear)
                    .padding(.horizontal, 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(GB.ink)
    }
}

/// 특성 고르기 — 숨겨진 특성과 "배틀에 반영되는지" 를 분명히 보여준다.
struct AbilityPickerSheet: View {
    let model: AppModel
    let slot: RosterSlot
    @Environment(\.dismiss) private var dismiss

    private var abilities: [AbilityDef] { model.abilitiesForSpecies[slot.speciesID] ?? [] }
    private var recommended: Set<String> { Set(model.recommendedAbilityNames(for: slot)) }
    private var current: AbilityDef? { model.currentAbility(for: slot) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("✨").font(.system(size: 15))
                Text("특성").font(GB.face(17)).foregroundStyle(GB.ink)
                Text(model.displayName(for: slot))
                    .font(GB.face(12, .semibold)).foregroundStyle(GB.inkSoft)
                Spacer()
                Button("닫기") { dismiss() }
            }
            .padding(14)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(abilities) { a in
                        AbilityPickerRow(
                            ability: a,
                            selected: current?.name == a.name,
                            recommended: recommended.contains(a.name)
                        ) {
                            Task { await model.setAbility(a, for: slot); dismiss() }
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Divider()
            Text("숨겨진 특성은 기본으로 잡히지 않습니다 — 쓰려면 직접 골라주세요.")
                .font(.system(size: 10)).foregroundStyle(GB.inkSoft)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 480, height: 420)
        .background(GB.plate)
    }
}

struct AbilityPickerRow: View {
    let ability: AbilityDef
    let selected: Bool
    let recommended: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(ability.display).font(GB.face(14))
                    if ability.isHidden {
                        tag("숨겨진", GB.typeColor(.psychic))
                    }
                    if recommended {
                        tag("실전 추천", GB.hpGreen)
                    }
                    if let t = ability.statusTag {
                        tag(t, GB.inkSoft)
                    } else {
                        tag("배틀 반영", GB.typeColor(.water))
                    }
                    Spacer(minLength: 4)
                    if selected {
                        Image(systemName: "checkmark").foregroundStyle(GB.hilite).font(.callout.bold())
                    }
                }
                Text(ability.description.isEmpty ? "설명이 없습니다" : ability.description)
                    .font(.system(size: 10.5))
                    .foregroundStyle(GB.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? GB.hpAmber.opacity(0.22) : .clear)
                    .padding(.horizontal, 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(GB.ink)
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 3).fill(color))
    }
}

/// 실전 세팅 골라 쓰기.
///
/// Smogon 분석 세팅을 종마다 여러 개 보여준다. 1대1 포맷이 앞에 온다
/// (우리 배틀이 1대1 이다). **성격과 노력치는 적용하지 않는다** —
/// 성격은 PokeTokenBar 를 따르고 노력치는 전원 0 이다.
struct SmogonSetSheet: View {
    let model: AppModel
    let slot: RosterSlot
    @Environment(\.dismiss) private var dismiss

    @State private var applied: String?

    private var sets: [SmogonSet] { model.smogonSets(for: slot) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                PokeBallIcon(size: 17)
                Text("실전 세팅").font(GB.face(17)).foregroundStyle(GB.ink)
                Text(model.displayName(for: slot))
                    .font(GB.face(12, .semibold)).foregroundStyle(GB.inkSoft)
                Spacer()
                Button("닫기") { dismiss() }
            }
            .padding(14)

            Divider()

            if sets.isEmpty {
                VStack(spacing: 6) {
                    Text("이 포켓몬의 실전 세팅이 없습니다")
                        .font(GB.face(14)).foregroundStyle(GB.ink)
                    Text("Smogon 분석에 올라온 종만 세팅이 있습니다.\n"
                         + "미진화이거나 실전에서 거의 쓰이지 않는 종은 자료가 없습니다.")
                        .font(.system(size: 11)).foregroundStyle(GB.inkSoft)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(sets) { set in
                            SmogonSetCard(model: model, slot: slot, set: set) {
                                Task {
                                    applied = await model.applySmogonSet(set, to: slot)
                                }
                            }
                        }
                    }
                    .padding(12)
                }
            }

            Divider()
            HStack(spacing: 6) {
                if let applied {
                    Text("적용됨 — \(applied)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(GB.hpGreen)
                } else {
                    Text("성격·노력치는 적용하지 않습니다 (성격은 PokeTokenBar 를 따릅니다)")
                        .font(.system(size: 10)).foregroundStyle(GB.inkSoft)
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
        }
        .frame(width: 560, height: 620)
        .background(GB.plate)
    }
}

struct SmogonSetCard: View {
    let model: AppModel
    let slot: RosterSlot
    let set: SmogonSet
    let onApply: () -> Void

    private var learnable: Set<String> {
        Set(model.rosterSpecies[slot.speciesID]?.learnableMoves ?? [])
    }
    private var itemDef: ItemDef? {
        guard let want = set.itemID else { return nil }
        return (model.itemsForSpecies[slot.speciesID] ?? []).first { $0.name == want }
    }
    /// 이 도구가 팀에서 겹치는가 — 겹치면 적용할 때 다른 것으로 바뀐다
    private var itemClashes: Bool {
        guard let it = itemDef else { return false }
        if model.itemsTakenByTeam(excluding: slot).contains(it.name) { return true }
        if let s = it.transformSlot,
           model.transformSlotsClaimedByTeam(excluding: slot).contains(s) { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(set.name).font(GB.face(15)).foregroundStyle(GB.ink)
                Text(set.formatLabel)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(RoundedRectangle(cornerRadius: 3).fill(GB.typeColor(.water)))
                Spacer()
                Button("적용") { onApply() }
                    .font(.system(size: 11, weight: .bold))
            }

            // 기술 — 배울 수 없는 것은 흐리게 (적용하면 건너뛴다)
            HStack(alignment: .top, spacing: 6) {
                Text("기술").font(.system(size: 10, weight: .heavy)).foregroundStyle(GB.hilite)
                    .frame(width: 26, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(set.moveSlots.enumerated()), id: \.offset) { _, opts in
                        HStack(spacing: 4) {
                            ForEach(Array(opts.enumerated()), id: \.offset) { i, display in
                                let id = SmogonSets.moveID(display)
                                let ok = learnable.contains(id)
                                if i > 0 {
                                    Text("/").font(.system(size: 9)).foregroundStyle(GB.inkSoft)
                                }
                                Text(model.moveKoName(id) ?? display)
                                    .font(.system(size: 11, weight: ok ? .semibold : .regular))
                                    .foregroundStyle(ok ? GB.ink : GB.inkSoft.opacity(0.55))
                                    .strikethrough(!ok)
                            }
                        }
                    }
                }
            }

            HStack(spacing: 14) {
                if let it = itemDef {
                    HStack(spacing: 4) {
                        ItemIcon(item: it, size: 18)
                        Text(it.display).font(.system(size: 11, weight: .semibold))
                        if itemClashes {
                            Text("팀에서 겹침")
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 3).fill(GB.hilite))
                        }
                    }
                } else if let want = set.item {
                    Text("도구 \(want) — 이 포켓몬에게 없음")
                        .font(.system(size: 10)).foregroundStyle(GB.inkSoft)
                }
                if let ab = set.ability {
                    Text("특성 \(model.abilityKoName(SmogonSets.abilityID(ab)) ?? ab)")
                        .font(.system(size: 11))
                        .foregroundStyle(GB.inkSoft)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(GB.ink.opacity(0.3), lineWidth: 1.5))
    }
}
