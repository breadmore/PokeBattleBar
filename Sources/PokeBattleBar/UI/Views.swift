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
            if !moves.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(moves.prefix(4)) { m in
                        Text("· \(m.display)").font(.system(size: 9)).lineLimit(1)
                    }
                }
                .frame(width: 92, alignment: .leading)
            }
            Button("기술 다시뽑기") {
                Task {
                    await model.rerollMoves(for: slot)
                    moves = await model.moveset(for: slot)
                }
            }
            .font(.system(size: 9))
            .buttonStyle(.link)
        }
        .padding(8)
        .frame(width: 112)
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

struct HostSection: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("방 만들기").font(.headline)

            TextField("방 이름", text: $model.roomName)
                .textFieldStyle(.roundedBorder)

            Stepper("최대 사용 포켓몬: \(model.rules.maxTeamSize)마리",
                    value: $model.rules.maxTeamSize, in: 1...6)
                .onChange(of: model.rules.maxTeamSize) { _, new in
                    model.selectedSlotIDs = Set(model.roster.prefix(new).map(\.id))
                }

            Picker("레벨", selection: $model.rules.level) {
                Text("50").tag(50)
                Text("100").tag(100)
            }
            .pickerStyle(.segmented)

            Toggle("상태이상 사용", isOn: $model.rules.statusEffects)
            Toggle("능력치 랭크 변화 사용", isOn: $model.rules.statStages)
            Toggle("급소 사용", isOn: $model.rules.criticalHits)

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
                .disabled(model.discovered.allSatisfy(\.occupied) || model.roster.isEmpty)

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
                        }
                        Spacer()
                        if room.occupied {
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

            if let team = model.myState?.team {
                HStack(spacing: 14) {
                    ForEach(Array(team.enumerated()), id: \.element.id) { idx, b in
                        BattlerCard(battler: b, selected: model.chosenLead == idx)
                            .onTapGesture { if !model.waitingForOpponent { model.submitLead(idx) } }
                    }
                }
            } else {
                // 게스트는 호스트가 상태를 보내주기 전이라 내 로컬 팀으로 표시
                HStack(spacing: 14) {
                    ForEach(Array(model.teamSlots.enumerated()), id: \.element.id) { idx, slot in
                        VStack(spacing: 4) {
                            SpriteView(speciesID: slot.speciesID, shiny: slot.isShiny, size: 76)
                            Text(model.rosterSpecies[slot.speciesID]?.display ?? "#\(slot.speciesID)")
                                .font(.caption.bold())
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10)
                            .fill(model.chosenLead == idx ? Color.accentColor.opacity(0.18)
                                                          : Color(nsColor: .controlBackgroundColor)))
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
                ForEach(Array(s.team.enumerated()), id: \.element.id) { _, m in
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
                if model.waitingForOpponent {
                    waiting
                } else {
                    MoveGrid(battler: me.active) { model.submitMove($0) }
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
            let ups = b.stages.filter { $0.value != 0 }
            if !ups.isEmpty {
                Text(ups.map { "\($0.key.ko) \($0.value > 0 ? "+" : "")\($0.value)" }
                        .sorted().joined(separator: " "))
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
    }
}

struct MoveGrid: View {
    let battler: Battler
    let onPick: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("기술 선택").font(.caption.bold()).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(Array(battler.moves.enumerated()), id: \.element.id) { idx, slot in
                    Button { onPick(idx) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(slot.def.display).font(.callout.bold())
                            HStack(spacing: 6) {
                                Text(slot.def.type.ko)
                                    .padding(.horizontal, 4)
                                    .background(Capsule().fill(.tertiary))
                                Text(slot.def.damageClass == .status ? "변화"
                                     : (slot.def.damageClass == .physical ? "물리" : "특수"))
                                if let p = slot.def.power, p > 0 { Text("위력 \(p)") }
                                Text("PP \(slot.ppLeft)/\(slot.def.pp)")
                            }
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!slot.usable)
                }
            }
        }
        .padding(12)
    }
}

struct ReplacementPicker: View {
    let team: [Battler]
    let onPick: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("다음 포켓몬을 고르세요").font(.caption.bold()).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(Array(team.enumerated()), id: \.element.id) { idx, b in
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
