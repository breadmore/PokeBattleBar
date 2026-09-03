import SwiftUI
import Combine

// MARK: - 루트

struct RootView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            // 테스트로 두 개 띄웠을 때 어느 쪽인지 창이 겹쳐도 보이게
            if let note = TestProfile.describe() {
                HStack(spacing: 6) {
                    Image(systemName: "hammer.fill")
                    Text(note).font(.caption.monospaced())
                    Spacer()
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.orange.opacity(0.22))
                .overlay(alignment: .bottom) { Divider() }
            }
            content
        }
        .frame(minWidth: 720, minHeight: 560)
        // 창 전체를 밝은 판으로 두고 글자색도 함께 지정한다.
        // 배경만 밝게 하면 다크모드 기본 글자색(흰색)이 그대로 나와
        // 흰 판에 흰 글씨가 된다.
        .gbSurface()
        // 새 방·초대 알림은 어느 화면에서든 보여야 한다
        .overlay(alignment: .top) {
            if let t = model.toast {
                NoticeToast(notice: t) { model.dismissToast() }
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.32), value: model.toast?.id)
        .sheet(isPresented: Binding(
            get: { model.incomingInvite != nil },
            set: { if !$0 { model.declineInvite() } }
        )) {
            if let inv = model.incomingInvite {
                InviteSheet(model: model, invite: inv)
            }
        }
        .task { await model.boot() }
        .onAppear { model.applyDockPolicy() }
        .onReceive(NSApplication.willTerminateNotification) { model.stopPresenceOnQuit() }
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

extension View {
    /// AppKit 알림을 SwiftUI 에서 받는 짧은 헬퍼
    func onReceive(_ name: Notification.Name, _ action: @escaping () -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: name)) { _ in action() }
    }
}

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
            VStack(alignment: .leading, spacing: 16) {
                header

                GBPanel("내 포켓몬") { RosterSection(model: model) }

                LoadoutWarningBanner(model: model)

                GBPanel("로비") { LobbyPeopleSection(model: model) }

                HStack(alignment: .top, spacing: 14) {
                    GBPanel("방 만들기") { HostSection(model: model) }
                    GBPanel("방 찾기") { JoinSection(model: model) }
                }
            }
            .padding(18)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            PokeBallIcon(size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("PokeBattleBar")
                    .font(GB.face(24)).foregroundStyle(GB.ink)
                Text("같은 네트워크의 동료와 도감 포켓몬으로 배틀")
                    .font(.caption).foregroundStyle(GB.inkSoft)
                Text("v\(model.appVersion) · 프로토콜 v\(model.protocolVersion)")
                    .font(.system(size: 9)).foregroundStyle(GB.inkSoft.opacity(0.7))
            }
            Spacer()
            UpdateButton(model: model)
            RecordBadge(record: model.record)
            VStack(alignment: .trailing, spacing: 3) {
                Text("내 이름").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(GB.inkSoft)
                TextField("트레이너", text: $model.playerName)
                    .textFieldStyle(.plain)
                    .font(GB.face(13, .semibold))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 150)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.75)))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(GB.ink.opacity(0.3), lineWidth: 1.5))
                    // 로비에 보이는 이름도 같이 바뀌어야 한다
                    .onSubmit { model.presenceNameChanged() }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(GB.plate)
                .shadow(color: GB.ink.opacity(0.18), radius: 0, x: 3, y: 3)
        )
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(GB.ink, lineWidth: 2.5))
    }
}

/// 로비에 누가 있는지 — 방을 열지 않은 사람도 보인다.
///
/// 방(`_pokebattle._tcp`)은 배틀을 열었을 때만 광고되므로, 이것 없이는
/// "지금 누가 앱을 켜놨는지" 를 알 방법이 없었다.
struct LobbyPeopleSection: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(model.lobbyPeers.count)명")
                    .font(GB.face(13, .semibold).monospacedDigit())
                    .foregroundStyle(GB.inkSoft)
                Spacer()
                if !model.notices.isEmpty {
                    Text("알림 \(model.notices.count)")
                        .font(.caption2).foregroundStyle(.secondary)
                    Button("지우기") { model.clearNotices() }
                        .font(.caption2).buttonStyle(.borderless)
                }
            }

            if model.lobbyPeers.isEmpty {
                Text("같은 네트워크에 켜져 있는 다른 PokeBattleBar 가 없습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(model.lobbyPeers) { p in
                            PeerChip(model: model, peer: p)
                        }
                    }
                    .padding(.bottom, 2)
                }
                .scrollIndicators(.visible)

                if !model.canInvite {
                    Text("방을 열면 여기서 바로 초대할 수 있습니다.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct PeerChip: View {
    let model: AppModel
    let peer: LobbyPeer

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(dot).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(peer.displayName).font(.callout.bold())
                Text(note).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if peer.status.invitable, peer.compatible {
                if model.invitesSent.contains(peer.displayName) {
                    Text("보냄").font(.caption2).foregroundStyle(.orange)
                } else if model.canInvite {
                    Button("초대") { Task { await model.invite(peer) } }
                        .font(.caption)
                        .help("이 사람을 내 방으로 부릅니다")
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
    }

    private var dot: Color {
        guard peer.compatible else { return .red }
        switch peer.status {
        case .free:     return .green
        case .hosting:  return .blue
        case .battling: return .orange
        }
    }

    private var note: String {
        guard peer.compatible else { return "버전 다름 v\(peer.protocolVersion)" }
        if model.invitesSent.contains(peer.displayName) { return "초대 보냄 — 수락 대기" }
        return peer.status.ko
    }
}

struct RosterSection: View {
    @Bindable var model: AppModel
    @State private var teamRecommended: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.rules.metronomeMode {
                Text("토게피 손가락흔들기 모드 — 아래 로스터는 사용되지 않습니다")
                    .font(.caption.bold()).foregroundStyle(.orange)
            }
            HStack {
                Text("\(model.roster.count)마리")
                    .font(GB.face(13, .semibold)).foregroundStyle(GB.inkSoft)
                Spacer()
                Text("데려갈 수 있는 최대: \(model.effectiveTeamSize)마리")
                    .font(.caption).foregroundStyle(.secondary)
                Button("팀 전체 실전 추천") {
                    Task { teamRecommended = await model.applyRecommendationToTeam() }
                }
                .font(.caption)
                .help("실전에서 많이 쓰이는 기술·도구·특성을 팀 전체에 적용합니다")
                if let c = teamRecommended {
                    Text("\(c)마리 적용됨").font(.caption2).foregroundStyle(.green)
                }
            }
            if model.roster.isEmpty {
                Text("PokeTokenBar 에 아직 포켓몬이 없습니다.")
                    .foregroundStyle(.secondary)
            } else {
                RosterStrip(model: model)
                if model.roster.count > model.rules.maxTeamSize {
                    Text("방 상한(\(model.rules.maxTeamSize)마리)보다 많이 가지고 있습니다 — 데려갈 포켓몬을 골라주세요.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }
}

/// 로스터를 좌우로 넘겨보는 띠.
///
/// 트랙패드 스와이프만으로는 마우스 사용자가 넘길 방법이 없고, 스크롤바를
/// 숨겨두면 더 있다는 것도 알 수 없다. 그래서 세 가지를 다 준다:
/// 항상 보이는 스크롤바, 좌우 버튼, 그리고 끌어서 넘기기.
struct RosterStrip: View {
    let model: AppModel

    /// 카드 148 + 간격 12 — 한 칸 폭
    private let stride: CGFloat = 160

    @State private var firstVisible = 0
    /// 드래그를 시작한 시점의 위치. 드래그 중에는 이 값을 기준으로 계산해야
    /// 손을 떼지 않고 앞뒤로 움직일 때 위치가 튀지 않는다.
    @State private var dragOrigin: Int?

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 4) {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(Array(model.roster.enumerated()), id: \.element.id) { i, slot in
                            RosterCard(model: model, slot: slot).id(i)
                        }
                    }
                    .padding(.bottom, 2)
                }
                .scrollIndicators(.visible)     // 하단 스크롤바를 항상 보여준다
                .simultaneousGesture(
                    // minimumDistance 를 두어 카드 안의 버튼 클릭을 삼키지 않게 한다
                    DragGesture(minimumDistance: 10)
                        .onChanged { v in
                            if dragOrigin == nil { dragOrigin = firstVisible }
                            guard let origin = dragOrigin else { return }
                            let steps = Int((-v.translation.width / stride).rounded())
                            go(to: origin + steps, proxy: proxy, animated: false)
                        }
                        .onEnded { _ in dragOrigin = nil }
                )

                if model.roster.count > 1 {
                    HStack(spacing: 6) {
                        Button {
                            go(to: firstVisible - 2, proxy: proxy, animated: true)
                        } label: { Image(systemName: "chevron.left") }
                            .disabled(firstVisible <= 0)
                            .help("왼쪽으로")
                        Button {
                            go(to: firstVisible + 2, proxy: proxy, animated: true)
                        } label: { Image(systemName: "chevron.right") }
                            .disabled(firstVisible >= lastIndex)
                            .help("오른쪽으로")
                        Text("끌어서 넘기거나 좌우로 스크롤할 수 있습니다")
                            .font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(firstVisible + 1) / \(model.roster.count)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
        }
    }

    private var lastIndex: Int { max(0, model.roster.count - 1) }

    private func go(to index: Int, proxy: ScrollViewProxy, animated: Bool) {
        let target = min(max(0, index), lastIndex)
        guard target != firstVisible else { return }
        firstVisible = target
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(target, anchor: .leading) }
        } else {
            proxy.scrollTo(target, anchor: .leading)
        }
    }
}

struct RosterCard: View {
    /// 실전 세팅 고르기 창
    @State private var showSets = false

    @Bindable var model: AppModel
    let slot: RosterSlot
    @State private var moves: [MoveDef] = []

    @State private var showPicker = false
    @State private var recommendation: String?

    private var selected: Bool { model.selectedSlotIDs.contains(slot.id) }
    private var species: SpeciesDef? { model.rosterSpecies[slot.speciesID] }

    var body: some View {
        VStack(spacing: 6) {
            SpriteView(speciesID: slot.speciesID, shiny: slot.isShiny, size: 72,
                       form: model.currentForm(for: slot))
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
            NatureLabel(nature: Nature.named(slot.nature))
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
            HStack(spacing: 6) {
                Button("기술 고르기") { showPicker = true }
                Button("다시뽑기") {
                    Task {
                        await model.rerollMoves(for: slot)
                        moves = await model.moveset(for: slot)
                    }
                }
            }
            .font(.system(size: 9))
            .buttonStyle(.link)

            if let why = model.recommendationUnavailableReason(for: slot) {
                Text("실전 추천 없음 — \(why)")
                    .font(.system(size: 8)).foregroundStyle(.tertiary)
                    .frame(width: 112, alignment: .leading)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            // 실전 세팅 — 여러 개 중에서 고르는 쪽을 먼저 보여준다.
            // (카드 맨 아래에 묻혀 있어서 있는 줄도 몰랐다)
            let setCount = model.smogonSets(for: slot).count
            if setCount > 0 {
                Button {
                    showSets = true
                    Task { await model.preloadSetMoveNames(for: slot) }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "list.star").font(.system(size: 8))
                        Text("실전 세팅 \(setCount)종 고르기")
                            .font(.system(size: 9, weight: .heavy))
                    }
                    .foregroundStyle(GB.plate)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .frame(width: 112, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 5).fill(GB.hpGreen))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Smogon 분석 세팅 \(setCount)개 중에서 골라 적용합니다")
            }
            if model.hasRecommendation(for: slot) {
                Button("한 번에 추천 적용") {
                    Task {
                        recommendation = await model.applyRecommendation(for: slot)
                        moves = await model.moveset(for: slot)
                    }
                }
                .font(.system(size: 9, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(GB.hpGreen)
                .frame(width: 112, alignment: .leading)
            }
            if let r = recommendation {
                Text("적용: \(r)").font(.system(size: 8)).foregroundStyle(.green)
                    .frame(width: 112, alignment: .leading).lineLimit(2)
            }

            // 폼 선택 (로토무 히트 등) — PokeTokenBar 는 건드리지 않는다
            let forms = model.selectableForms(for: slot)
            if !forms.isEmpty {
                Menu {
                    Button("기본") { Task { await model.setForm(nil, for: slot) } }
                    ForEach(forms, id: \.self) { f in
                        Button(FormChange.label(f)) { Task { await model.setForm(f, for: slot) } }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text("🔀").font(.system(size: 8))
                        Text(model.currentForm(for: slot).map(FormChange.label) ?? "기본 폼")
                            .font(.system(size: 9, weight: model.currentForm(for: slot) == nil
                                          ? .regular : .bold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .frame(width: 112, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 4)
                        .fill(model.currentForm(for: slot) == nil
                              ? Color.clear : Color.teal.opacity(0.18)))
                }
                .menuStyle(.borderlessButton)
                .help("폼을 고르면 타입과 종족값이 바뀝니다")
            }
            // 배틀 중 자동으로 변신하는 종은 알려준다
            if let ab = model.currentAbility(for: slot), FormChange.isAutoAbility(ab.name) {
                Text("\(ab.display) — 배틀 중 자동 폼 변화")
                    .font(.system(size: 8)).foregroundStyle(.teal)
                    .frame(width: 112, alignment: .leading).lineLimit(2)
            }

            Divider().padding(.vertical, 1)
            LoadoutPickers(model: model, slot: slot)
        }
        .padding(8)
        .frame(width: 148)
        .sheet(isPresented: $showSets) {
            SmogonSetSheet(model: model, slot: slot)
        }
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
        .sheet(isPresented: $showPicker) {
            MovePickerSheet(model: model, slot: slot, current: moves) { picked in
                Task {
                    await model.setMoves(picked, for: slot)
                    moves = await model.moveset(for: slot)
                }
            }
        }
    }
}

/// 장비 낭비 경고.
/// 변신은 종류별로 배틀당 1회뿐이라, 같은 슬롯을 노리는 도구가 겹치면 미리 알려준다.
struct LoadoutWarningBanner: View {
    let model: AppModel

    var body: some View {
        let warnings = model.loadoutWarnings
        if !warnings.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(warnings) { w in
                    HStack(alignment: .top, spacing: 6) {
                        Text(w.severity == .waste ? "✗" : "⚠️")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(w.severity == .waste ? Color.red : Color.orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(w.title)
                                .font(.caption.bold())
                                .foregroundStyle(w.severity == .waste ? Color.red : Color.orange)
                            Text(w.detail.replacingOccurrences(of: "**", with: ""))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1))
        }
    }
}

/// 피격 효과.
///
/// 실제 기술 애니메이션은 없다 — 원작 이펙트 리소스가 없기 때문이다.
/// 대신 **HP 가 줄어든 순간을 감지해** 흔들림과 붉은 섬광을 준다.
/// 쓰러지면 회색으로 가라앉는다.
struct HitEffect: ViewModifier, Animatable {
    let hp: Int
    let fainted: Bool

    @State private var lastHP: Int?
    @State private var shake: CGFloat = 0
    @State private var flash: Double = 0

    func body(content: Content) -> some View {
        content
            .offset(x: shake)
            .overlay {
                Color.red.opacity(flash * 0.45)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            }
            .saturation(fainted ? 0 : 1)
            .onChange(of: hp) { old, new in
                guard new < old else { return }
                // 맞은 만큼 세게 흔든다 (최대 HP 를 모르므로 절대량으로 대략)
                let magnitude = min(10.0, max(3.0, Double(old - new) / 8.0))
                withAnimation(.easeOut(duration: 0.06)) {
                    shake = CGFloat(magnitude); flash = 1
                }
                withAnimation(.easeIn(duration: 0.06).delay(0.06)) { shake = -CGFloat(magnitude) }
                withAnimation(.easeOut(duration: 0.10).delay(0.12)) { shake = 0 }
                withAnimation(.easeOut(duration: 0.30).delay(0.06)) { flash = 0 }
            }
    }
}

/// 전적과 포인트 (3번)
struct RecordBadge: View {
    let record: RecordStore.Record

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            HStack(spacing: 4) {
                Text("\(record.points)P").font(.callout.bold()).foregroundStyle(.orange)
                if record.currentStreak > 1 {
                    Text("\(record.currentStreak)연승")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(.red.opacity(0.25)))
                }
            }
            if record.total > 0 {
                Text("\(record.wins)승 \(record.losses)패"
                     + (record.draws > 0 ? " \(record.draws)무" : "")
                     + " · \(Int(record.winRate * 100))%")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                if record.bestStreak > 1 {
                    Text("최고 \(record.bestStreak)연승")
                        .font(.system(size: 8)).foregroundStyle(.tertiary)
                }
            } else {
                Text("아직 전적 없음").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }
}

/// 채팅창 (4번)
struct ChatPanel: View {
    @Bindable var model: AppModel
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !compact {
                Text("채팅").font(.caption.bold()).foregroundStyle(.secondary)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(model.chatLines) { line in
                            HStack(alignment: .top, spacing: 4) {
                                Text(line.from)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(line.mine ? Color.accentColor : .orange)
                                Text(line.text)
                                    .font(.system(size: 11))
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .id(line.id)
                        }
                        if model.chatLines.isEmpty {
                            Text("아직 대화가 없습니다")
                                .font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(6)
                }
                .frame(height: compact ? 70 : 110)
                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.4)))
                .onChange(of: model.chatLines.count) { _, _ in
                    if let last = model.chatLines.last { withAnimation { proxy.scrollTo(last.id) } }
                }
            }
            HStack(spacing: 4) {
                TextField("메시지", text: $model.chatDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onSubmit { model.sendChat() }
                Button("전송") { model.sendChat() }
                    .font(.caption)
                    .disabled(model.chatDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

/// 구현된 특성이 실제로 무슨 일을 하는지 한 줄로
func abilitySummary(_ a: AbilityDef) -> String {
    switch a.kind {
    case .none:                        "배틀에 반영되지 않음"
    case .pinchBoost(let t, _):        "HP 1/3 이하에서 \(t.ko) 기술 강화"
    case .intimidate:                  "등장 시 상대 공격 하락"
    case .typeImmunity(let t):         "\(t.ko) 기술 무효"
    case .sturdy:                      "풀피에서 일격을 버틴다"
    case .damageTaken(let ts, _):      "\(ts.map(\.ko).joined(separator: "·")) 피해 감소"
    case .superEffectiveResist:        "효과가 굉장한 피해 감소"
    case .statusImmunity(let s):       "\(s.ko) 상태가 되지 않음"
    case .technician:                  "저위력 기술 강화"
    case .clearBody:                   "능력치 하락 무효"
    case .noGuard:                     "반드시 명중"
    case .sheerForce:                  "위력 상승, 부가효과 없음"
    case .tintedLens:                  "효과가 별로인 기술 강화"
    case .adaptability:                "자기 타입 일치 보너스 증가"
    case .sniper:                      "급소 배율 증가"
    case .attackMultiplier:            "공격 2배"
    case .statusDefBoost:              "상태이상일 때 방어 상승"
    case .statusAtkBoost:              "상태이상일 때 공격 상승"
    case .magicGuard:                  "간접 피해를 받지 않음"
    case .rockHead:                    "반동을 받지 않음"
    case .reckless:                    "반동기 강화"
    case .scrappy:                     "노말·격투가 고스트에 통함"
    case .unaware:                     "상대 능력치 변화 무시"
    case .sereneGrace:                 "부가효과 확률 2배"
    case .shieldDust:                  "부가효과를 받지 않음"
    case .weatherOnEntry(let w):       "등장 시 \(w.ko)"
    case .weatherSpeedBoost(let w, _): "\(w.ko)에서 스피드 2배"
    case .weatherStatBoost(let w, let s, _): "\(w.ko)에서 \(s.ko) 상승"
    case .weatherHeal(let w, _):       "\(w.ko)에서 회복"
    case .weatherEvasion(let w):       "\(w.ko)에서 회피율 상승"
    case .weatherImmuneChip:           "날씨 피해 무효"
    case .dryskin:                     "물 흡수, 불꽃에 약해짐"
    case .contactStatus(let s, let p): "접촉 시 \(p)% 확률로 \(s.ko)"
    case .contactDamage:               "접촉한 상대에게 반사 피해"
    case .moveFlagBoost(let f, _):     "\(f.rawValue) 기술 강화"
    case .soundImmunity:               "소리 기술 무효"
    case .powderImmunity:              "가루 기술 무효"
    case .ignoreAbility:               "상대 특성 무시"
    case .criticalImmunity:            "급소를 맞지 않음"
    case .multiscale:                  "풀피에서 받는 피해 감소"
    case .levitateLike(let t, let m):  m == 0 ? "\(t.ko) 무효" : "\(t.ko) 피해 감소"
    case .statMultiplier(let s, let m): "\(s.ko) \(m)배"
    case .statusSpeedBoost:            "상태이상일 때 스피드 상승"
    case .accuracyMultiplier:          "명중률 상승"
    case .hustle:                      "공격 상승, 물리 명중률 하락"
    case .defeatist:                   "HP 절반 이하에서 공격 반감"
    case .speedBoostEachTurn:          "턴마다 스피드 상승"
    case .boostOnKO(let s, _):         "쓰러뜨리면 \(s.ko) 상승"
    case .boostWhenHit(let t, let s, _):
        t == nil ? "공격받으면 \(s.ko) 상승" : "\(t!.ko) 기술을 맞으면 \(s.ko) 상승"
    case .boostOnFlinch(let s, _):     "풀죽으면 \(s.ko) 상승"
    case .contrary:                    "능력치 변화가 반대로"
    case .simple:                      "능력치 변화가 2배"
    case .analytic:                    "나중에 움직이면 위력 상승"
    case .download:                    "등장 시 상대 약한 쪽을 노려 상승"
    case .poisonHeal:                  "독 피해 대신 회복"
    case .shedSkin(let p):             "턴마다 \(p)% 확률로 상태이상 회복"
    case .healInWeather(let w):        "\(w.ko)에서 상태이상 회복"
    case .noStatusInWeather(let w):    "\(w.ko)에서 상태이상에 걸리지 않음"
    case .earlyBird:                   "잠듦이 빨리 풀린다"
    case .statDropImmunity(let ss):
        ss.isEmpty ? "명중률이 떨어지지 않음" : "\(ss.map(\.ko).joined(separator: "·")) 하락 무효"
    case .flinchImmunity:              "풀죽지 않음"
    case .wonderGuard:                 "효과가 굉장한 기술만 통함"
    case .truant:                      "한 턴 걸러 행동"
    case .priorityBoost(let c, let n):
        c == .status ? "변화기 우선도 +\(n)" : "기술 우선도 \(n > 0 ? "+" : "")\(n)"
    case .pressure:                    "상대 PP 를 더 소모시킨다"
    case .damp:                        "자폭 기술을 막는다"
    case .aftermath:                   "쓰러질 때 접촉한 상대에게 피해"
    case .contactStatDrop(let s, _):   "접촉한 상대의 \(s.ko) 하락"
    case .poisonTouch(let p):          "접촉 공격 시 \(p)% 확률로 독"
    case .synchronize:                 "받은 상태이상을 상대에게도"
    case .absorbAndBoost(let t, let s, _): "\(t.ko) 무효 + \(s.ko) 상승"
    case .magicBounce:                 "변화기를 되돌린다"
    case .unburden:                    "도구를 쓰면 스피드 2배"
    case .quickDraw(let p):            "\(p)% 확률로 선공"
    case .moveTypeBoost:               "특정 기술군 강화"
    case .healOnEntry:                 "물러날 때 체력 회복"
    case .cureOnSwitch:                "물러나면 상태이상 회복"
    case .gluttony:                    "나무열매를 HP 절반에서 먹는다"
    case .unnerve:                     "상대가 나무열매를 먹지 못한다"
    case .liquidOoze:                  "흡수 기술이 오히려 피해를 준다"
    case .cursedBody(let p):           "맞은 기술을 \(p)% 확률로 봉인"
    case .trace:                       "등장 시 상대 특성을 복사"
    case .stickyHold:                  "도구를 빼앗기지 않는다"
    case .pickup:                      "소비된 도구를 주워온다"
    case .weightMultiplier(let m):     m > 1 ? "무게 2배" : "무게 절반"
    case .autoFormChange:              "배틀 중 조건에 따라 폼이 자동으로 바뀐다"
    case .doublesOnly:                 "더블배틀 전용 (1대1 에서는 발동 불가)"
    }
}

/// 성격이 어떤 스탯을 올리고 내리는지 보여준다 (2번)
struct NatureLabel: View {
    let nature: Nature

    var body: some View {
        HStack(spacing: 3) {
            Text(nature.ko).font(.system(size: 9)).foregroundStyle(.secondary)
            if let up = nature.up, let down = nature.down, up != down {
                Text("\(up.ko)↑").font(.system(size: 8, weight: .bold)).foregroundStyle(.red)
                Text("\(down.ko)↓").font(.system(size: 8, weight: .bold)).foregroundStyle(.blue)
            } else {
                Text("보정 없음").font(.system(size: 8)).foregroundStyle(.tertiary)
            }
        }
    }
}

/// 배울 수 있는 기술 중에서 4개를 직접 고른다 (1번)
struct MovePickerSheet: View {
    let model: AppModel
    let slot: RosterSlot
    let current: [MoveDef]
    let onDone: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picked: [String] = []
    @State private var search = ""
    @State private var details: [String: MoveDef] = [:]

    private var recommended: Set<String> { Set(model.recommendedMoveNames(for: slot)) }

    /// 추천 기술을 맨 위로 올린다 — 포켓몬을 잘 모르면 목록에서 뭘 골라야 할지 알 수 없다
    private var all: [String] {
        let list = model.learnableMoves(for: slot)
        let rec = recommended
        return list.sorted { a, b in
            let ra = rec.contains(a), rb = rec.contains(b)
            if ra != rb { return ra }
            return a < b
        }
    }
    private var filtered: [String] {
        guard !search.isEmpty else { return all }
        let q = search.lowercased()
        return all.filter { name in
            name.contains(q) || (details[name]?.display.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(model.rosterSpecies[slot.speciesID]?.display ?? "") 기술 고르기")
                    .font(.headline)
                Spacer()
                Text("\(picked.count)/4").font(.callout.bold())
                    .foregroundStyle(picked.count == 4 ? .green : .secondary)
            }
            HStack(spacing: 6) {
                Text("배울 수 있는 기술 \(all.count)개 — 4개까지")
                    .font(.caption).foregroundStyle(.secondary)
                if !recommended.isEmpty {
                    Text("⭐ 실전 추천 \(recommended.count)개 (맨 위)")
                        .font(.caption).foregroundStyle(.orange)
                    Button("추천으로 채우기") {
                        picked = Array(model.recommendedMoveNames(for: slot).prefix(4))
                    }
                    .font(.caption)
                }
            }

            TextField("기술 이름 검색", text: $search).textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filtered, id: \.self) { name in
                        MoveRow(name: name,
                                def: details[name],
                                isPicked: picked.contains(name),
                                isRecommended: recommended.contains(name)) {
                            if let i = picked.firstIndex(of: name) { picked.remove(at: i) }
                            else if picked.count < 4 { picked.append(name) }
                        }
                        .task {
                            if details[name] == nil {
                                details[name] = try? await PokeAPI.shared.move(name)
                            }
                        }
                    }
                }
            }
            .frame(height: 340)

            HStack {
                Button("전부 지우기") { picked = [] }
                Spacer()
                Button("취소") { dismiss() }
                Button("적용") { onDone(picked); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .disabled(picked.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 460)
        .onAppear { picked = current.map(\.name) }
    }

    struct MoveRow: View {
        let name: String
        let def: MoveDef?
        let isPicked: Bool
        var isRecommended = false
        let onTap: () -> Void

        var body: some View {
            HStack(spacing: 6) {
                Image(systemName: isPicked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isPicked ? Color.accentColor : .secondary)
                if isRecommended {
                    Text("⭐").font(.system(size: 9))
                }
                Text(def?.display ?? name)
                    .font(.callout)
                    .fontWeight(isRecommended ? .semibold : .regular)
                if let d = def {
                    Text(d.type.ko).font(.system(size: 9))
                        .padding(.horizontal, 4)
                        .background(Capsule().fill(.tertiary))
                    Text(d.damageClass == .status ? "변화"
                         : (d.damageClass == .physical ? "물리" : "특수"))
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                    if let p = d.power, p > 0 {
                        Text("위력 \(p)").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    Text("PP \(d.pp)").font(.system(size: 9)).foregroundStyle(.tertiary)
                } else {
                    ProgressView().controlSize(.mini)
                }
                Spacer()
            }
            .padding(.vertical, 2).padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 4)
                .fill(isPicked ? Color.accentColor.opacity(0.12) : .clear))
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
        }
    }
}

/// 지닌 도구 + 특성 선택.
/// 메가진화·Z기술·다이맥스는 해당 도구를 끼워야 쓸 수 있다.
struct LoadoutPickers: View {
    let model: AppModel
    let slot: RosterSlot

    /// 열려 있는 창. **`.sheet` 를 여러 개 달면 마지막 것만 동작한다** —
    /// 그래서 도구 창이 아예 열리지 않았다. 하나로 합쳐서 무엇을 열지 값으로 정한다.
    private enum Which: String, Identifiable {
        case items, abilities
        var id: String { rawValue }
    }
    @State private var open: Which?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            let equipped = model.currentItem(for: slot)
            let recItem = model.recommendedItemName(for: slot)
            let curAbil = model.currentAbility(for: slot)
            let recAbils = model.recommendedAbilityNames(for: slot)

            // 도구 — 아이콘과 이름을 함께. 누르면 설명이 있는 목록이 열린다.
            Button { open = .items } label: {
                HStack(spacing: 5) {
                    if let e = equipped {
                        ItemIcon(item: e, size: 16)
                    } else {
                        Image(systemName: "bag").font(.system(size: 10))
                            .foregroundStyle(.secondary).frame(width: 16)
                    }
                    Text(equipped?.display ?? "도구 없음")
                        .font(.system(size: 9, weight: equipped == nil ? .regular : .bold))
                        .lineLimit(1)
                    if let e = equipped, recItem == e.name {
                        Text("⭐").font(.system(size: 7))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.system(size: 7))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4).padding(.vertical, 2)
                .frame(width: 112, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 4)
                    .fill(equipped == nil ? Color.clear : Color.accentColor.opacity(0.18)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(equipped?.description ?? "지닌 도구를 고릅니다")

            // 끼운 도구가 이 개체에게 실제로 작동하는지
            if let r = model.itemReadiness(for: slot) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 2) {
                        Text(r.ok ? "✓" : "✗").font(.system(size: 9, weight: .black))
                        Text(r.headline).font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(r.ok ? Color.green : Color.red)
                    Text(r.detail)
                        .font(.system(size: 8)).foregroundStyle(.secondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 112, alignment: .leading)

                let shared = model.slotsSharingItem(slot)
                if !shared.isEmpty {
                    Text("중복: \(shared.joined(separator: ", "))")
                        .font(.system(size: 8)).foregroundStyle(.orange)
                        .frame(width: 112, alignment: .leading).lineLimit(1)
                }
            }

            // 특성
            Button { open = .abilities } label: {
                HStack(spacing: 3) {
                    Text("✨").font(.system(size: 8))
                    Text(curAbil?.display ?? "특성 없음")
                        .font(.system(size: 9, weight: curAbil == nil ? .regular : .bold))
                        .lineLimit(1)
                    if let a = curAbil, recAbils.contains(a.name) {
                        Text("⭐").font(.system(size: 7))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.system(size: 7))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4).padding(.vertical, 2)
                .frame(width: 112, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 4)
                    .fill(curAbil == nil ? Color.clear : Color.purple.opacity(0.16)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(curAbil?.description ?? "특성을 고릅니다")

            if let a = curAbil, let tag = a.statusTag {
                Text(tag)
                    .font(.system(size: 8)).foregroundStyle(.secondary)
                    .frame(width: 112, alignment: .leading)
            }

        }
        .sheet(item: $open) { which in
            switch which {
            case .items:     ItemPickerSheet(model: model, slot: slot)
            case .abilities: AbilityPickerSheet(model: model, slot: slot)
            }
        }
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
    @Bindable var model: AppModel
    let title: String

    var body: some View {
        VStack(spacing: 14) {
            Text(title).font(.title3.bold())
            ProgressView()
            Text(model.status).foregroundStyle(.secondary)

            // 방을 연 뒤에 초대한다 — 여기가 초대를 보내는 자리다
            if model.canInvite {
                VStack(alignment: .leading, spacing: 8) {
                    LobbyPeopleSection(model: model)
                }
                .frame(maxWidth: 520)
                .padding(.top, 4)
            }

            if model.role != .none {
                ChatPanel(model: model).frame(width: 340)
            }
            Button("취소") { model.leaveEverything() }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gbSurface()
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
            SpriteView(speciesID: battler.speciesID, shiny: battler.isShiny, size: 76,
                       form: battler.spriteForm)
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
    var tall = false

    private var ratio: Double { max <= 0 ? 0 : Double(current) / Double(max) }
    private var color: Color { ratio > 0.5 ? .green : (ratio > 0.2 ? .yellow : .red) }

    /// 숫자도 부드럽게 올라가고 내려가게
    @State private var shownHP: Int = -1

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(color)
                        .frame(width: geo.size.width * ratio)
                        // HP 가 깎이는 것을 눈으로 볼 수 있게
                        .animation(.easeOut(duration: 0.55), value: ratio)
                }
            }
            .frame(height: tall ? 9 : 6)
            Text("\(shownHP < 0 ? current : shownHP)/\(max)")
                .font(.system(size: tall ? 10 : 8, weight: tall ? .semibold : .regular))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.55), value: shownHP)
        }
        .onAppear { shownHP = current }
        .onChange(of: current) { _, new in shownHP = new }
    }
}

// MARK: - 배틀

struct BattleView: View {
    @Bindable var model: AppModel

    /// 로그·채팅은 원작 화면에 없는 것이라 접어둔다 — 필요할 때만 펼친다
    @State private var showLog = false
    @State private var showChat = false

    var body: some View {
        VStack(spacing: 0) {
            if let me = model.myState, let foe = model.foeState, let b = model.battle {
                let shown = displayed(me: me, foe: foe)

                ZStack(alignment: .top) {
                    GBStage(model: model, me: shown.me, foe: shown.foe)
                    topStrip(turn: b.turn)
                }
                .frame(maxHeight: .infinity)

                GBTextBox { controls(me: me) }

                utilityBar
                if showLog {
                    LogView(lines: model.displayLog)
                        .frame(height: 132)
                        .background(GB.plate.opacity(0.5))
                }
                if showChat {
                    ChatPanel(model: model, compact: true)
                        .frame(height: 150)
                        .background(GB.plate.opacity(0.5))
                }
            } else {
                ProgressView().frame(maxHeight: .infinity)
            }
        }
        .background(GB.plate)
    }

    /// 재생 중이면 그 시점의 팀·활성 개체를 그린다
    private func displayed(me: SideState, foe: SideState) -> (me: SideState, foe: SideState) {
        var myShown = me, foeShown = foe
        let myTeam = model.displayTeam(model.mySide)
        let foeTeam = model.displayTeam(model.mySide.other)
        if !myTeam.isEmpty {
            myShown.team = myTeam
            myShown.activeIndex = model.displayActiveIndex(model.mySide)
        }
        if !foeTeam.isEmpty {
            foeShown.team = foeTeam
            foeShown.activeIndex = model.displayActiveIndex(model.mySide.other)
        }
        return (myShown, foeShown)
    }

    private func topStrip(turn: Int) -> some View {
        HStack(spacing: 6) {
            Text("턴 \(turn)")
                .font(GB.face(11, .heavy).monospacedDigit())
                .foregroundStyle(GB.plate)
                .padding(.horizontal, 7).padding(.vertical, 2.5)
                .background(Capsule().fill(GB.ink.opacity(0.82)))
            if model.modeSummary != "일반" {
                Text(model.modeSummary)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(GB.ink)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(GB.hpAmber.opacity(0.9)))
            }
            Spacer()
            Button("나가기") { model.leaveEverything() }
                .controlSize(.small)
        }
        .padding(.horizontal, 10).padding(.top, 8)
    }

    private var utilityBar: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $showLog) { Text("로그").font(.caption) }
                .toggleStyle(.button).controlSize(.small)
            Toggle(isOn: $showChat) { Text("채팅").font(.caption) }
                .toggleStyle(.button).controlSize(.small)
            if let last = model.displayLog.last, !showLog {
                Text(last)
                    .font(.caption).foregroundStyle(GB.inkSoft)
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(GB.plate)
        .overlay(alignment: .top) { Rectangle().fill(GB.ink.opacity(0.18)).frame(height: 1) }
    }

    @ViewBuilder private func controls(me: SideState) -> some View {
        if let b = model.battle {
            switch b.phase {
            case .awaitingMoves:
                if model.isPlayingBack {
                    playingBack
                } else if model.rules.autoMove {
                    autoRunning
                } else if model.waitingForOpponent {
                    waiting
                } else {
                    GBChoicePanel(model: model, me: me)
                }
            case .awaitingReplacement:
                if model.needsMyReplacement {
                    ReplacementPicker(team: me.team, activeIndex: nil) { model.submitReplacement($0) }
                } else {
                    waiting
                }
            case .awaitingPivot:
                if model.needsMyPivot {
                    ReplacementPicker(team: me.team, activeIndex: me.activeIndex,
                                      title: "물러났습니다 — 다음에 낼 포켓몬을 고르세요") {
                        model.submitReplacement($0)
                    }
                } else {
                    waiting
                }
            default:
                waiting
            }
        }
    }

    /// 턴 재생 중 표시
    private var playingBack: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("배틀 진행 중…").font(.callout.bold())
            }
            Text("순서대로 재생하고 있습니다")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(height: 120)
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

struct SpecialBar: View {
    let model: AppModel

    var body: some View {
        let anyRelevant = SpecialKind.allCases.contains {
            model.canUse($0) || model.alreadyUsed($0) || model.missingItem($0) != nil
        }
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
        let lacking = model.missingItem(kind)
        let selected = model.pendingSpecial.map { model.kindOf($0) == kind } ?? false

        Button {
            model.toggleSpecial(kind)
        } label: {
            HStack(spacing: 3) {
                Text(kind.icon)
                Text(kind.ko).font(.caption.bold())
                if used { Text("사용함").font(.system(size: 9)) }
                // 자격은 있는데 도구가 없으면 그 이유를 버튼에 적는다
                else if lacking != nil { Text("도구 없음").font(.system(size: 9)) }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .tint(selected ? .orange : .secondary)
        .disabled(!usable)
        .opacity(usable ? 1 : 0.45)
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

struct MoveGrid: View {
    let battler: Battler
    let foeTypes: [PType]
    let chart: TypeChart?
    var pendingSpecial: SpecialAction? = nil
    var zMoveCache: [String: MoveDef] = [:]
    var megaForms: [String: FormStats] = [:]
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
                            eff: Effectiveness.compute(move: preview(slot).def,
                                                       attacker: previewAttacker,
                                                       defenderTypes: foeTypes, chart: chart),
                            transformNote: transformNote(slot),
                            originalName: originalName(slot)
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(!slot.usable)
                }
            }
        }
        .padding(12)
    }

    /// 선언한 변신을 **누르기 전에** 반영해 보여준다.
    /// 다이맥스를 누르면 기술 이름·위력이 맥스 기술로 바뀌고,
    /// 메가진화를 누르면 바뀐 타입 기준으로 상성 배지와 실질 위력이 갱신된다.
    private func preview(_ slot: Battler.MoveSlot) -> Battler.MoveSlot {
        guard let t = transformedDef(slot.def) else { return slot }
        return Battler.MoveSlot(def: t, ppLeft: slot.ppLeft)
    }

    /// 메가진화를 선언하면 바뀐 타입으로 상성을 계산해야 한다
    private var previewAttacker: Battler {
        guard case .mega(let form)? = pendingSpecial,
              let stats = megaForms[form] else { return battler }
        var b = battler
        b.types = stats.types
        return b
    }

    /// 변신으로 이름이 바뀌면 원래 기술 이름을 함께 보여준다
    private func originalName(_ slot: Battler.MoveSlot) -> String? {
        guard let t = transformedDef(slot.def), t.display != slot.def.display else { return nil }
        return slot.def.display
    }

    private var isDeclaringDynamax: Bool {
        switch pendingSpecial {
        case .dynamax, .gmax: return true
        default: return false
        }
    }

    private func transformNote(_ slot: Battler.MoveSlot) -> String? {
        if battler.isDynamaxed || isDeclaringDynamax { return "맥스" }
        if case .zMove = pendingSpecial { return "Z" }
        if case .mega = pendingSpecial { return "메가" }
        return nil
    }

    /// 실제로 나갈 기술 정의. 이미 변신 중이거나 이번 턴 선언한 경우 모두 반영한다.
    private func transformedDef(_ move: MoveDef) -> MoveDef? {
        if battler.isDynamaxed || isDeclaringDynamax {
            // 거다이맥스 전용기 — 선언이 gmax 이거나 이미 거다이맥스 상태일 때
            let giga: Bool = {
                if case .gmax? = pendingSpecial { return true }
                return battler.isGigantamaxed
            }()
            if giga, move.damageClass != .status,
               let g = GMaxMove.forSpecies(battler.speciesID), g.type == move.type {
                var gm = move
                gm.koName = g.ko
                gm.power = FormTables.maxPower(basePower: move.power ?? 0, type: move.type)
                gm.accuracy = nil
                return gm
            }
            if move.damageClass == .status {
                guard var guardMove = zMoveCache[FormTables.maxGuard] else { return nil }
                guardMove.pp = move.pp
                return guardMove
            }
            guard let n = FormTables.maxMove[move.type], var mx = zMoveCache[n] else { return nil }
            mx.power = FormTables.maxPower(basePower: move.power ?? 0, type: move.type)
            mx.damageClass = move.damageClass
            mx.accuracy = nil
            return mx
        }

        if case .zMove = pendingSpecial {
            // 전용 Z크리스탈은 타입 제한 없이 자기 공격기를 Z기술로 만든다
            if battler.hasSignatureZ, move.damageClass != .status, move.isDamaging {
                var sz = move
                sz.koName = (battler.heldItem?.display ?? "전용 Z") + " Z기술"
                sz.power = FormTables.zPower(basePower: move.power ?? 0)
                sz.accuracy = nil
                return sz
            }
            guard let zn = FormTables.zMoveName(for: move), var z = zMoveCache[zn] else { return nil }
            z.power = FormTables.zPower(basePower: move.power ?? 0)
            z.damageClass = move.damageClass
            z.accuracy = nil
            return z
        }
        return nil
    }
}

struct MoveButtonLabel: View {
    let slot: Battler.MoveSlot
    let eff: Effectiveness
    var transformNote: String? = nil
    /// 변신으로 이름이 바뀐 경우 원래 기술 이름
    var originalName: String? = nil

    private var isStatus: Bool { slot.def.damageClass == .status || !slot.def.isDamaging }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(slot.def.display).font(.callout.bold())
                    if let o = originalName {
                        Text(o).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
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
    /// 유턴으로 물러날 때는 지금 나와 있는 개체를 다시 낼 수 없다
    var activeIndex: Int? = nil
    var title: String = "다음 포켓몬을 고르세요"
    let onPick: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(Array(team.enumerated()), id: \.offset) { idx, b in
                    Button { onPick(idx) } label: {
                        BattlerCard(battler: b, selected: idx == activeIndex)
                    }
                    .buttonStyle(.plain)
                    .disabled(b.isFainted || idx == activeIndex)
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
            if let p = model.lastPointsGained {
                Text("+\(p) 포인트").font(.title3.bold()).foregroundStyle(.orange)
                RecordBadge(record: model.record)
            }
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
