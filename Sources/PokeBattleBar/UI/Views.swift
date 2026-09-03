import SwiftUI

// MARK: - 루트

struct RootView: View {
    @State private var model = AppModel()

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(minWidth: 720, minHeight: 560)
        .task { await model.boot() }
        .alert("문제가 발생했습니다",
               isPresented: Binding(get: { model.errorMessage != nil },
                                    set: { if !$0 { model.errorMessage = nil } })) {
            Button("확인") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder private var content: some View {
        switch model.screen {
        case .loading:      LoadingView(model: model)
        case .lobby:        LobbyView(model: model)
        case .hostingRoom:  WaitingView(model: model, title: "방을 열었습니다")
        case .joiningRoom:  WaitingView(model: model, title: "접속 중")
        case .chooseLead:   LeadView(model: model)
        case .battle:       BattleView(model: model)
        case .result:       ResultView(model: model)
        }
    }
}

// MARK: - 로딩

struct LoadingView: View {
    let model: AppModel
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text(model.status).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 로비

struct LobbyView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                RosterSection(model: model)

                Divider()

                HStack(alignment: .top, spacing: 24) {
                    HostSection(model: model)
                    Divider().frame(height: 220)
                    JoinSection(model: model)
                }
            }
            .padding(22)
        }
        .onAppear { model.startBrowsing() }
        .onDisappear { model.stopBrowsing() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("PokeBattleBar").font(.title2.bold())
                Text("같은 네트워크의 동료와 도감 포켓몬으로 배틀")
                    .font(.caption).foregroundStyle(.secondary)
                Text("v\(model.appVersion) · 프로토콜 v\(model.protocolVersion)")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("내 이름").font(.caption).foregroundStyle(.secondary)
                TextField("트레이너", text: $model.playerName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
            }
        }
    }
}

struct RosterSection: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.rules.metronomeMode {
                Text("토게피 손가락흔들기 모드 — 아래 로스터는 사용되지 않습니다")
                    .font(.caption.bold()).foregroundStyle(.orange)
            }
            HStack {
                Text("내 포켓몬 \(model.roster.count)마리").font(.headline)
                Spacer()
                Text("데려갈 수 있는 최대: \(model.effectiveTeamSize)마리")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.roster.isEmpty {
                Text("PokeTokenBar 에 아직 포켓몬이 없습니다.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(model.roster) { slot in
                            RosterCard(model: model, slot: slot)
                        }
                    }
                }
                if model.roster.count > model.rules.maxTeamSize {
                    Text("방 상한(\(model.rules.maxTeamSize)마리)보다 많이 가지고 있습니다 — 데려갈 포켓몬을 골라주세요.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }
}

struct RosterCard: View {
    @Bindable var model: AppModel
    let slot: RosterSlot
    @State private var moves: [MoveDef] = []

    private var selected: Bool { model.selectedSlotIDs.contains(slot.id) }
    private var species: SpeciesDef? { model.rosterSpecies[slot.speciesID] }

    var body: some View {
        VStack(spacing: 6) {
            SpriteView(speciesID: slot.speciesID, shiny: slot.isShiny, size: 72)
            Text(species?.display ?? "#\(slot.speciesID)")
                .font(.caption.bold()).lineLimit(1)
            if let sp = species {
                HStack(spacing: 3) {
                    ForEach(sp.types, id: \.self) { t in
                        Text(t.ko).font(.system(size: 9))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Capsule().fill(.tertiary))
                    }
                }
                Text("종족값 \(Stat.allCases.reduce(0) { $0 + sp.base($1) })")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Text(Nature.named(slot.nature).ko)
                .font(.system(size: 9)).foregroundStyle(.secondary)
            if slot.origin == .active && !slot.fullyEvolved {
                Text("진화중").font(.system(size: 9)).foregroundStyle(.orange)
            }
            // 특수 변신 자격 — 어떤 포켓몬을 데려갈지 고를 때 필요한 정보다.
            // 다이맥스는 모두 가능하므로 표시하지 않는다.
            EligibilityBadges(e: model.eligibility(for: slot))
            if !moves.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(moves.prefix(4)) { m in
                        Text("· \(m.display)").font(.system(size: 9)).lineLimit(1)
                    }
                }
                .frame(width: 104, alignment: .leading)
            }
            Button("기술 다시뽑기") {
                Task {
                    await model.rerollMoves(for: slot)
                    moves = await model.moveset(for: slot)
                }
            }
            .font(.system(size: 9))
            .buttonStyle(.link)

            Divider().padding(.vertical, 1)
            LoadoutPickers(model: model, slot: slot)
        }
        .padding(8)
        .frame(width: 148)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(selected ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .onTapGesture { model.toggleSelection(slot) }
        .task { moves = await model.moveset(for: slot) }
    }
}

/// 지닌 도구 + 특성 선택.
/// 메가진화·Z기술·다이맥스는 해당 도구를 끼워야 쓸 수 있다.
struct LoadoutPickers: View {
    let model: AppModel
    let slot: RosterSlot

    private var items: [ItemDef] { model.itemsForSpecies[slot.speciesID] ?? [] }
    private var abilities: [AbilityDef] { model.abilitiesForSpecies[slot.speciesID] ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // 지닌 도구 — 착용 여부가 한눈에 보이게
            let equipped = model.currentItem(for: slot)
            Menu {
                Button("없음") { Task { await model.setItem(nil, for: slot) } }
                ForEach(groupedItems(), id: \.0) { group, list in
                    Section(group) {
                        ForEach(list) { it in
                            Button(it.display) { Task { await model.setItem(it, for: slot) } }
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(equipped == nil ? "🎒" : "✅").font(.system(size: 8))
                    Text(equipped?.display ?? "도구 없음")
                        .font(.system(size: 9, weight: equipped == nil ? .regular : .bold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 4).padding(.vertical, 2)
                .frame(width: 112, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 4)
                    .fill(equipped == nil ? Color.clear : Color.accentColor.opacity(0.18)))
            }
            .menuStyle(.borderlessButton)
            .help(equipped?.shortEffect ?? "지닌 도구를 고릅니다")

            // 끼운 도구가 이 개체에게 실제로 작동하는지
            if let r = model.itemReadiness(for: slot) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 2) {
                        Text(r.ok ? "✓" : "✗")
                            .font(.system(size: 9, weight: .black))
                        Text(r.headline)
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(r.ok ? Color.green : Color.red)
                    Text(r.detail)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 112, alignment: .leading)

                let shared = model.slotsSharingItem(slot)
                if !shared.isEmpty {
                    Text("중복: \(shared.joined(separator: ", "))")
                        .font(.system(size: 8)).foregroundStyle(.orange)
                        .frame(width: 112, alignment: .leading)
                        .lineLimit(1)
                }
            }

            // 특성
            Menu {
                ForEach(abilities) { a in
                    Button {
                        Task { await model.setAbility(a, for: slot) }
                    } label: {
                        Text(a.display + (a.isHidden ? " (숨겨진)" : "")
                             + (a.isImplemented ? "" : " · 표시만"))
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Text("✨").font(.system(size: 8))
                    Text(model.currentAbility(for: slot)?.display ?? "특성")
                        .font(.system(size: 9)).lineLimit(1)
                    if let a = model.currentAbility(for: slot), !a.isImplemented {
                        Text("표시만").font(.system(size: 7)).foregroundStyle(.secondary)
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .frame(width: 108, alignment: .leading)
            .help(model.currentAbility(for: slot)?.shortEffect ?? "특성을 고릅니다")
        }
    }

    private func groupedItems() -> [(String, [ItemDef])] {
        Dictionary(grouping: items, by: \.group)
            .map { ($0.key, $0.value.sorted { $0.display < $1.display }) }
            .sorted { $0.0 < $1.0 }
    }
}

/// 메가진화 / 거다이맥스 자격 배지
struct EligibilityBadges: View {
    let e: (mega: Bool, gigantamax: Bool, megaFormCount: Int)

    var body: some View {
        if e.mega || e.gigantamax {
            HStack(spacing: 3) {
                if e.mega {
                    Badge(text: e.megaFormCount > 1 ? "✦ 메가 X/Y" : "✦ 메가", color: .purple)
                }
                if e.gigantamax {
                    Badge(text: "◈ 거다이맥스", color: .pink)
                }
            }
        }
    }

    struct Badge: View {
        let text: String
        let color: Color
        var body: some View {
            Text(text)
                .font(.system(size: 8, weight: .bold))
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(Capsule().fill(color.opacity(0.25)))
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }
}

struct HostSection: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("방 만들기").font(.headline)

            TextField("방 이름", text: $model.roomName)
                .textFieldStyle(.roundedBorder)

            Stepper("최대 사용 포켓몬: \(model.rules.maxTeamSize)마리",
                    value: $model.rules.maxTeamSize, in: 1...6)
                .onChange(of: model.rules.maxTeamSize) { _, _ in
                    model.trimSelectionToCap()   // 고른 걸 유지한 채 상한만 맞춘다
                }

            Picker("레벨", selection: $model.rules.level) {
                Text("50").tag(50)
                Text("100").tag(100)
            }
            .pickerStyle(.segmented)

            Toggle("상태이상 사용", isOn: $model.rules.statusEffects)
            Toggle("능력치 랭크 변화 사용", isOn: $model.rules.statStages)
            Toggle("급소 사용", isOn: $model.rules.criticalHits)

            Divider()
            Text("특수 변신 (각각 배틀당 1회)").font(.caption.bold()).foregroundStyle(.secondary)
            Toggle("메가진화 허용", isOn: $model.rules.allowMega)
            Toggle("다이맥스 허용", isOn: $model.rules.allowDynamax)
            Toggle("거다이맥스 허용", isOn: $model.rules.allowGigantamax)
                .disabled(!model.rules.allowDynamax)
                .padding(.leading, 14)
            Toggle("Z기술 허용", isOn: $model.rules.allowZMove)
            Text("다이맥스와 거다이맥스는 같은 슬롯을 씁니다 — 둘 중 하나만 쓸 수 있습니다.")
                .font(.system(size: 9)).foregroundStyle(.secondary)

            Divider()
            Text("도구 · 특성").font(.caption.bold()).foregroundStyle(.secondary)
            Toggle("변신에 도구 필요", isOn: $model.rules.requireItems)
            Toggle("도구 상시 효과 사용", isOn: $model.rules.itemEffects)
            Toggle("특성 사용", isOn: $model.rules.abilities)
            Text("메가스톤·Z크리스탈·다이맥스밴드를 끼워야 변신할 수 있습니다.")
                .font(.system(size: 9)).foregroundStyle(.secondary)

            Divider()
            Text("게임 모드").font(.caption.bold()).foregroundStyle(.secondary)

            Toggle("랜덤 기술", isOn: $model.rules.randomMoveset)
                .disabled(model.rules.metronomeMode)
            Text("배틀마다 배울 수 있는 기술에서 4개를 새로 뽑습니다.")
                .font(.system(size: 9)).foregroundStyle(.secondary)

            Toggle("자유의지", isOn: $model.rules.autoMove)
                .disabled(model.rules.metronomeMode)
            Text("플레이어가 고르지 않고 포켓몬이 4개 중 무작위로 씁니다.")
                .font(.system(size: 9)).foregroundStyle(.secondary)

            Toggle("변신 자동 선언", isOn: $model.rules.autoSpecial)
                .disabled(model.rules.metronomeMode)
            Text("도구를 끼웠다면 메가진화·다이맥스·Z기술이 무작위 시점에 발동합니다.")
                .font(.system(size: 9)).foregroundStyle(.secondary)

            Divider()
            Toggle(isOn: $model.rules.metronomeMode) {
                Text("토게피 손가락흔들기 1:1").fontWeight(.bold)
            }
            Text("양쪽 모두 토게피 1마리(보유 무관), 손가락흔들기 하나, PP 최대치, "
                 + "생명의구슬 장착. 다른 설정은 무시됩니다.")
                .font(.system(size: 9)).foregroundStyle(.orange)

            Divider()
            Button("방 열기") { Task { await model.startHosting() } }
                .buttonStyle(.borderedProminent)
                .disabled(model.roster.isEmpty)
        }
        .frame(width: 280)
    }
}

struct JoinSection: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("방 찾기").font(.headline)
                Spacer()
                ProgressView().controlSize(.small)
            }

            Button("자동 매칭") { Task { await model.autoMatch() } }
                .buttonStyle(.borderedProminent)
                .disabled(!model.discovered.contains { !$0.occupied && $0.compatible }
                          || model.roster.isEmpty)

            if model.discovered.isEmpty {
                Text("같은 네트워크에서 열린 방이 없습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(model.discovered) { room in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(room.name).font(.callout.bold())
                            Text("\(room.hostName) · 최대 \(room.teamCap)마리 · Lv.\(room.level)")
                                .font(.caption2).foregroundStyle(.secondary)
                            if room.mode != "일반" {
                                Text(room.mode)
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                    .background(Capsule().fill(.orange.opacity(0.25)))
                            }
                        }
                        Spacer()
                        if let note = room.versionNote {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("버전 불일치").font(.caption2.bold()).foregroundStyle(.red)
                                Text(note).font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                        } else if room.occupied {
                            Text("대전중").font(.caption2).foregroundStyle(.orange)
                        } else {
                            Button("참가") { Task { await model.join(room) } }
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                }
            }
        }
        .frame(minWidth: 300)
    }
}

// MARK: - 대기

struct WaitingView: View {
    let model: AppModel
    let title: String

    var body: some View {
        VStack(spacing: 14) {
            Text(title).font(.title3.bold())
            ProgressView()
            Text(model.status).foregroundStyle(.secondary)
            Button("취소") { model.leaveEverything() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 선봉 선택

struct LeadView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            Text("선봉을 고르세요").font(.title3.bold())
            Text("교체는 없습니다 — 쓰러지면 다음 포켓몬을 그때 고릅니다.")
                .font(.caption).foregroundStyle(.secondary)

            // 호스트는 배틀 상태의 내 팀, 게스트는 **실제로 보낸 팀**을 보여준다.
            // 둘 다 상대가 가진 배열과 순서가 같으므로 탭한 인덱스가 그대로 통한다.
            let team = model.myState?.team ?? model.sentTeam
            if team.isEmpty {
                ProgressView()
            } else {
                HStack(spacing: 14) {
                    ForEach(Array(team.enumerated()), id: \.offset) { idx, b in
                        BattlerCard(battler: b, selected: model.chosenLead == idx)
                            .onTapGesture { if !model.waitingForOpponent { model.submitLead(idx) } }
                    }
                }
            }

            if model.waitingForOpponent {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(model.status) }
                    .foregroundStyle(.secondary)
            }
            Button("나가기") { model.leaveEverything() }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct BattlerCard: View {
    let battler: Battler
    var selected = false

    var body: some View {
        VStack(spacing: 4) {
            SpriteView(speciesID: battler.speciesID, shiny: battler.isShiny, size: 76)
                .opacity(battler.isFainted ? 0.3 : 1)
            Text(battler.name).font(.caption.bold())
            Text("Lv.\(battler.level) · \(battler.natureName)")
                .font(.system(size: 9)).foregroundStyle(.secondary)
            HPBar(current: battler.currentHP, max: battler.maxHP).frame(width: 78)
            if battler.status != .none {
                Text(battler.status.ko).font(.system(size: 9))
                    .padding(.horizontal, 4)
                    .background(Capsule().fill(.orange.opacity(0.3)))
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(selected ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
    }
}

struct HPBar: View {
    let current: Int
    let max: Int

    private var ratio: Double { max <= 0 ? 0 : Double(current) / Double(max) }
    private var color: Color { ratio > 0.5 ? .green : (ratio > 0.2 ? .yellow : .red) }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(color).frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 6)
            Text("\(current)/\(max)").font(.system(size: 8)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 배틀

struct BattleView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if let me = model.myState, let foe = model.foeState, let b = model.battle {
                field(me: me, foe: foe, turn: b.turn)
                Divider()
                LogView(lines: b.log)
                Divider()
                controls(me: me)
            } else {
                ProgressView().frame(maxHeight: .infinity)
            }
        }
    }

    private func field(me: SideState, foe: SideState, turn: Int) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text("턴 \(turn)").font(.caption.bold()).foregroundStyle(.secondary)
                Text(model.modeSummary)
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(.orange.opacity(0.25)))
                Spacer()
                Button("나가기") { model.leaveEverything() }.controlSize(.small)
            }
            HStack(alignment: .top) {
                sideColumn(foe, isFoe: true)
                Spacer()
                sideColumn(me, isFoe: false)
            }
        }
        .padding(16)
    }

    private func sideColumn(_ s: SideState, isFoe: Bool) -> some View {
        VStack(alignment: isFoe ? .leading : .trailing, spacing: 6) {
            Text(isFoe ? "상대 · \(s.playerName)" : "나 · \(s.playerName)")
                .font(.caption.bold()).foregroundStyle(.secondary)
            ActiveBattlerView(b: s.active, mirrored: isFoe)
            HStack(spacing: 3) {
                ForEach(Array(s.team.enumerated()), id: \.offset) { _, m in
                    Circle()
                        .fill(m.isFainted ? Color.gray.opacity(0.35) : Color.green)
                        .frame(width: 8, height: 8)
                }
            }
            Text("남은 \(s.remaining)/\(s.team.count)마리")
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func controls(me: SideState) -> some View {
        if let b = model.battle {
            switch b.phase {
            case .awaitingMoves:
                if model.rules.autoMove {
                    autoRunning
                } else if model.waitingForOpponent {
                    waiting
                } else {
                    VStack(spacing: 0) {
                        SpecialBar(model: model)
                        MoveGrid(battler: me.active,
                                 foeTypes: model.foeState?.active.types ?? [],
                                 chart: model.typeChart,
                                 pendingSpecial: model.pendingSpecial,
                                 zMoveCache: model.zPreview) { model.submitMove($0) }
                    }
                }
            case .awaitingReplacement:
                if model.needsMyReplacement {
                    ReplacementPicker(team: me.team) { model.submitReplacement($0) }
                } else {
                    waiting
                }
            default:
                waiting
            }
        }
    }

    /// 자유의지 모드 진행 표시
    private var autoRunning: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("자유의지 — 포켓몬이 스스로 싸웁니다")
                    .font(.callout.bold()).foregroundStyle(.orange)
            }
            Text("기술은 보유한 4개 중 무작위로 선택됩니다"
                 + (model.rules.autoSpecial ? " · 변신도 자동 발동" : ""))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(height: 120)
    }

    private var waiting: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(model.status).foregroundStyle(.secondary)
        }
        .frame(height: 120)
    }
}

struct ActiveBattlerView: View {
    let b: Battler
    let mirrored: Bool

    var body: some View {
        VStack(alignment: mirrored ? .leading : .trailing, spacing: 4) {
            SpriteView(speciesID: b.speciesID, shiny: b.isShiny, size: 110)
                .scaleEffect(x: mirrored ? -1 : 1, y: 1)
                .opacity(b.isFainted ? 0.25 : 1)
            Text("\(b.name)\(b.isShiny ? " ✨" : "")").font(.callout.bold())
            Text("Lv.\(b.level)").font(.caption2).foregroundStyle(.secondary)
            HPBar(current: b.currentHP, max: b.maxHP).frame(width: 130)
            HStack(spacing: 4) {
                ForEach(b.types, id: \.self) { t in
                    Text(t.ko).font(.system(size: 9))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(.tertiary))
                }
                if b.status != .none {
                    Text(b.status.ko).font(.system(size: 9))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(.orange.opacity(0.35)))
                }
            }
            HStack(spacing: 4) {
                if let it = b.heldItem {
                    Text("\(b.itemConsumed ? "🎒" : "✅") \(it.display)")
                        .font(.system(size: 9, weight: b.itemConsumed ? .regular : .semibold))
                        .strikethrough(b.itemConsumed)
                        .foregroundStyle(b.itemConsumed ? .secondary : .primary)
                }
                if let ab = b.ability {
                    Text("✨ \(ab.display)").font(.system(size: 9))
                        .foregroundStyle(ab.isImplemented ? .primary : .secondary)
                }
            }
            if let locked = b.lockedMoveIndex, b.moves.indices.contains(locked) {
                Text("고정: \(b.moves[locked].def.display)")
                    .font(.system(size: 9)).foregroundStyle(.orange)
            }
            if let label = b.formLabel {
                Text(label + (b.isDynamaxed ? " \(b.dynamaxTurnsLeft)턴" : ""))
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(.orange.opacity(0.4)))
            }
            let ups = b.stages.filter { $0.value != 0 }
            if !ups.isEmpty {
                Text(ups.map { "\($0.key.ko) \($0.value > 0 ? "+" : "")\($0.value)" }
                        .sorted().joined(separator: " "))
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
    }
}

/// 메가진화 / 거다이맥스 / Z기술 선언 바.
/// **각각 배틀당 1회** — 6마리가 다 거다이맥스할 수는 없다.
struct SpecialBar: View {
    let model: AppModel

    var body: some View {
        let anyRelevant = SpecialKind.allCases.contains { model.canUse($0) || model.alreadyUsed($0) }
        if anyRelevant {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    ForEach(SpecialKind.allCases, id: \.self) { kind in
                        SpecialButton(model: model, kind: kind)
                    }
                    Spacer()
                    if let p = model.pendingSpecial {
                        Text("\(p.ko) 선언됨 — 기술을 고르면 발동")
                            .font(.caption2.bold()).foregroundStyle(.orange)
                    }
                }
                // 메가 폼이 둘인 포켓몬(리자몽 등)은 어느 쪽인지 고른다
                if model.canUse(.mega), let forms = model.myState?.active.megaForms, forms.count > 1 {
                    HStack(spacing: 6) {
                        Text("메가 폼:").font(.caption2).foregroundStyle(.secondary)
                        ForEach(forms, id: \.self) { f in
                            Button(model.megaFormLabel(f)) { model.selectMegaForm(f) }
                                .font(.caption2)
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
    }
}

struct SpecialButton: View {
    let model: AppModel
    let kind: SpecialKind

    var body: some View {
        let usable = model.canUse(kind)
        let used = model.alreadyUsed(kind)
        let selected = model.pendingSpecial.map { model.kindOf($0) == kind } ?? false

        Button {
            model.toggleSpecial(kind)
        } label: {
            HStack(spacing: 3) {
                Text(kind.icon)
                Text(kind.ko).font(.caption.bold())
                if used { Text("사용함").font(.system(size: 9)) }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .tint(selected ? .orange : .secondary)
        .disabled(!usable)
        .opacity(usable ? 1 : 0.45)
        .help(used ? "이번 배틀에서 이미 사용했습니다"
                   : (usable ? "이번 턴에 \(kind.ko)을 선언합니다" : "이 포켓몬은 \(kind.ko)을 쓸 수 없습니다"))
    }
}

struct MoveGrid: View {
    let battler: Battler
    let foeTypes: [PType]
    let chart: TypeChart?
    var pendingSpecial: SpecialAction? = nil
    var zMoveCache: [String: MoveDef] = [:]
    let onPick: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("기술 선택").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Text("상대 타입: \(foeTypes.map(\.ko).joined(separator: "/"))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(Array(battler.moves.enumerated()), id: \.offset) { idx, slot in
                    Button { onPick(idx) } label: {
                        MoveButtonLabel(
                            slot: preview(slot),
                            eff: Effectiveness.compute(move: preview(slot).def, attacker: battler,
                                                       defenderTypes: foeTypes, chart: chart),
                            transformNote: transformNote(slot)
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(!slot.usable)
                }
            }
        }
        .padding(12)
    }

    /// Z기술을 선언했거나 거다이맥스 중이면, 실제로 나갈 기술로 미리 바꿔 보여준다.
    /// 그래서 상성 배지와 실질 위력도 변환 후 기준으로 계산된다.
    private func preview(_ slot: Battler.MoveSlot) -> Battler.MoveSlot {
        guard let t = transformedDef(slot.def) else { return slot }
        return Battler.MoveSlot(def: t, ppLeft: slot.ppLeft)
    }

    private func transformNote(_ slot: Battler.MoveSlot) -> String? {
        guard transformedDef(slot.def) != nil else { return nil }
        if battler.isDynamaxed { return "맥스" }
        if case .zMove = pendingSpecial { return "Z" }
        return nil
    }

    private func transformedDef(_ move: MoveDef) -> MoveDef? {
        if battler.isDynamaxed {
            guard let n = FormTables.maxMove[move.type], var mx = zMoveCache[n] else { return nil }
            mx.power = FormTables.maxPower(basePower: move.power ?? 0, type: move.type)
            mx.damageClass = move.damageClass
            return mx
        }
        guard case .zMove = pendingSpecial,
              let zn = FormTables.zMoveName(for: move),
              var z = zMoveCache[zn] else { return nil }
        z.power = FormTables.zPower(basePower: move.power ?? 0)
        z.damageClass = move.damageClass
        return z
    }
}

struct MoveButtonLabel: View {
    let slot: Battler.MoveSlot
    let eff: Effectiveness
    var transformNote: String? = nil

    private var isStatus: Bool { slot.def.damageClass == .status || !slot.def.isDamaging }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(slot.def.display).font(.callout.bold())
                if let t = transformNote {
                    Text(t).font(.system(size: 9, weight: .black))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(.orange.opacity(0.35)))
                }
                if slot.def.selfKO {
                    Text("자폭").font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(.red.opacity(0.28)))
                }
                Spacer(minLength: 0)
                // 상성 배지 — 등배면 표시하지 않는다
                if !isStatus, let l = eff.label {
                    Text(l).font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(eff.color)
                }
            }

            HStack(spacing: 6) {
                Text(slot.def.type.ko)
                    .padding(.horizontal, 4)
                    .background(Capsule().fill(.tertiary))
                Text(isStatus ? "변화" : (slot.def.damageClass == .physical ? "물리" : "특수"))
                if let p = slot.def.power, p > 0 { Text("위력 \(p)") }
                Text("PP \(slot.ppLeft)/\(slot.def.pp)")
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)

            // 실질 위력 / 판정 — 여기가 "몇 배인지" 실제로 읽히는 줄
            if !isStatus {
                HStack(spacing: 5) {
                    if let ep = eff.effectivePower {
                        Text("실질 \(ep)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(eff.color)
                        if eff.stab { Text("일치+50%").font(.system(size: 9)).foregroundStyle(.secondary) }
                    } else if let note = eff.specialNote {
                        Text(note).font(.system(size: 10, weight: .semibold)).foregroundStyle(.purple)
                    }
                    if let v = eff.verdict {
                        Text(v).font(.system(size: 9)).foregroundStyle(eff.color)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
    }
}

struct ReplacementPicker: View {
    let team: [Battler]
    let onPick: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("다음 포켓몬을 고르세요").font(.caption.bold()).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(Array(team.enumerated()), id: \.offset) { idx, b in
                    Button { onPick(idx) } label: {
                        BattlerCard(battler: b)
                    }
                    .buttonStyle(.plain)
                    .disabled(b.isFainted)
                }
            }
        }
        .padding(12)
    }
}

struct LogView: View {
    let lines: [String]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { i, l in
                        Text(l).font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(i)
                    }
                }
                .padding(10)
            }
            .frame(height: 140)
            .onChange(of: lines.count) { _, n in
                withAnimation { proxy.scrollTo(n - 1, anchor: .bottom) }
            }
        }
    }
}

// MARK: - 결과

struct ResultView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            Text(model.resultText).font(.largeTitle.bold())
            if let b = model.battle {
                Text("\(b.turn)턴 만에 끝났습니다").foregroundStyle(.secondary)
                LogView(lines: b.log).frame(width: 520)
            }
            Button("로비로") { model.leaveEverything() }
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
