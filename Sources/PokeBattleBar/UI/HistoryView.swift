import SwiftUI

/// 대전기록.
///
/// 승패 숫자만으로는 그 배틀이 어땠는지 알 수 없다. 무엇으로 싸웠고,
/// 누가 끝까지 남았는지 보여준다.
struct HistoryView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var battles: [RecordStore.Record.Battle] {
        model.record.history.reversed()      // 최근 것이 위
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if battles.isEmpty {
                VStack(spacing: 6) {
                    PokeBallIcon(size: 34)
                    Text("아직 대전 기록이 없습니다")
                        .font(GB.face(14)).foregroundStyle(GB.ink)
                    Text("배틀이 끝나면 여기에 쌓입니다.")
                        .font(.system(size: 11)).foregroundStyle(GB.inkSoft)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(battles) { b in
                            BattleRow(battle: b)
                        }
                    }
                    .padding(12)
                }
            }

            Divider()
            HStack {
                Text("최근 \(battles.count)판 (100판까지 보관)")
                    .font(.system(size: 10)).foregroundStyle(GB.inkSoft)
                Spacer()
                if !battles.isEmpty {
                    GBSheetButton("기록 지우기", kind: .plain) {
                        Task { await model.clearHistory() }
                    }
                }
                GBSheetButton("닫기", kind: .primary) { dismiss() }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .frame(width: 560, height: 460)
        .gbSurface(GB.plate)
    }

    private var header: some View {
        HStack(spacing: 8) {
            PokeBallIcon(size: 18)
            Text("대전기록").font(GB.face(17)).foregroundStyle(GB.ink)
            Spacer()
            let r = model.record
            Text("\(r.wins)승 \(r.losses)패\(r.draws > 0 ? " \(r.draws)무" : "")")
                .font(GB.face(13, .semibold)).foregroundStyle(GB.ink)
            Text("\(r.points)P")
                .font(GB.face(13, .semibold)).foregroundStyle(GB.hilite)
            if r.bestStreak > 1 {
                Text("최고 \(r.bestStreak)연승")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(GB.inkSoft)
            }
        }
        .padding(14)
    }
}

struct BattleRow: View {
    let battle: RecordStore.Record.Battle

    private var resultText: String {
        guard let won = battle.won else { return "무승부" }
        return won ? "승리" : "패배"
    }
    private var resultColor: Color {
        guard let won = battle.won else { return GB.inkSoft }
        return won ? GB.hpGreen : GB.hilite
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text(resultText)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(resultColor))
                Text("vs \(battle.opponent)").font(GB.face(14)).foregroundStyle(GB.ink)
                Spacer()
                if battle.mode != "일반" {
                    Text(battle.mode)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(GB.ink)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(RoundedRectangle(cornerRadius: 3).fill(GB.hpAmber.opacity(0.7)))
                }
                Text("+\(battle.points)P")
                    .font(GB.face(12, .semibold)).foregroundStyle(GB.hilite)
            }

            // 양쪽 팀 — 쓰러진 개체는 흐리게
            HStack(alignment: .top, spacing: 10) {
                TeamStrip(title: "나", mons: battle.myTeam,
                          remaining: battle.myRemaining)
                Text("vs").font(.system(size: 10, weight: .black))
                    .foregroundStyle(GB.inkSoft).padding(.top, 18)
                TeamStrip(title: battle.opponent, mons: battle.foeTeam,
                          remaining: battle.foeRemaining)
            }

            // 마지막까지 남은 포켓몬
            if battle.myLastStanding != nil || battle.foeLastStanding != nil {
                HStack(spacing: 10) {
                    if let m = battle.myLastStanding {
                        LastStanding(label: "끝까지 남은 내 포켓몬", mon: m, mine: true)
                    }
                    if let m = battle.foeLastStanding {
                        LastStanding(label: "상대의 마지막", mon: m, mine: false)
                    }
                    Spacer()
                }
            }

            HStack(spacing: 8) {
                Text("\(battle.turns)턴")
                    .font(.system(size: 10)).foregroundStyle(GB.inkSoft)
                Text(battle.at.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10)).foregroundStyle(GB.inkSoft)
                Spacer()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(GB.plateHi))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(GB.ink.opacity(0.28), lineWidth: 1.5))
    }
}

struct TeamStrip: View {
    let title: String
    let mons: [RecordStore.Record.Battle.Mon]
    let remaining: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 10, weight: .heavy)).foregroundStyle(GB.inkSoft)
                Text("\(remaining)/\(mons.count)")
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
                    .foregroundStyle(remaining > 0 ? GB.hpGreen : GB.hilite)
            }
            HStack(spacing: 3) {
                ForEach(mons) { m in
                    VStack(spacing: 0) {
                        SpriteView(speciesID: m.speciesID, shiny: m.isShiny, size: 34,
                                   form: m.form, scale: 1)
                            .opacity(m.fainted ? 0.28 : 1)
                            .saturation(m.fainted ? 0 : 1)
                        Text(m.name)
                            .font(.system(size: 8))
                            .foregroundStyle(m.fainted ? GB.inkSoft : GB.ink)
                            .lineLimit(1)
                    }
                    .frame(width: 40)
                    .help(m.fainted ? "\(m.name) — 쓰러짐"
                                    : "\(m.name) — HP \(m.hpLeft)/\(m.maxHP)")
                }
            }
        }
    }
}

struct LastStanding: View {
    let label: String
    let mon: RecordStore.Record.Battle.Mon
    let mine: Bool

    var body: some View {
        HStack(spacing: 6) {
            SpriteView(speciesID: mon.speciesID, shiny: mon.isShiny, size: 28,
                       form: mon.form, scale: 1)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.system(size: 8, weight: .bold)).foregroundStyle(GB.inkSoft)
                HStack(spacing: 4) {
                    Text(mon.name).font(.system(size: 11, weight: .bold))
                        .foregroundStyle(GB.ink)
                    Text("\(mon.hpLeft)/\(mon.maxHP)")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(GB.hpColor(Double(mon.hpLeft) / Double(max(1, mon.maxHP))))
                }
            }
        }
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6)
            .fill((mine ? GB.hpGreen : GB.typeColor(.psychic)).opacity(0.14)))
    }
}
