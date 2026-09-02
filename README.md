# PokeBattleBar

같은 네트워크(LAN)에 있는 동료와 **PokeTokenBar 도감 포켓몬으로 1:1 배틀**하는 macOS 앱.

PokeTokenBar 를 수정하지 않는 **별도 컴패니언 앱**이다.
`companion-state.json` 을 **읽기 전용**으로만 참조하므로, PokeTokenBar 가 자동 업데이트돼도 깨지지 않는다.

## 동료에게 배포하기

```sh
./scripts/bundle.sh          # build/PokeBattleBar.zip 생성 (유니버설, 약 900KB)
```

**`build/PokeBattleBar.zip` 이 파일 하나만** Slack/AirDrop 등으로 보내면 된다.
안에 앱, `Install.command`, `READ-ME-FIRST.txt` 가 들어 있다.

받는 쪽 요구사항:
- macOS 14 이상 (Apple Silicon / 인텔 둘 다 됨 — 유니버설 바이너리)
- **PokeTokenBar 설치 + 포켓몬 최소 1마리** (`brew install --cask poke-token-bar`)
  포켓몬 정보는 각자 맥의 상태 파일에만 있으므로 전원이 두 앱을 다 깔아야 한다.

### Gatekeeper

Apple 유료 개발자 서명이 없는 ad-hoc 서명이라, 전송된 앱은 격리(quarantine) 속성이 붙어
더블클릭이 막힌다. `Install.command` 자체도 같이 격리되므로 더블클릭이 안 될 수 있다.
그래서 `READ-ME-FIRST.txt` 는 **터미널 한 줄 붙여넣기**를 1순위로 안내한다:

```sh
xattr -dr com.apple.quarantine PokeBattleBar.app && cp -R PokeBattleBar.app /Applications/ && open /Applications/PokeBattleBar.app
```

마찰 없이 배포하려면 Apple Developer 계정(연 $99)으로 서명 + 공증(notarize)해야 한다.
사내 배포라면 위 한 줄이 현실적이다.

### 소스에서 직접 빌드 (격리 문제 없음)

로컬 빌드한 앱에는 격리 속성이 붙지 않는다. Command Line Tools 만 있으면 된다 (Xcode 전체 불필요).

```sh
xcode-select --install
git clone <이 저장소> && cd PokeBattleBar
NATIVE=1 ./scripts/bundle.sh     # 내 맥 아키텍처만 — 더 빠르다
open build/PokeBattleBar.app
```

### 첫 실행

**"로컬 네트워크 접근 허용"을 반드시 눌러야** 방 검색이 된다. 거부하면 조용히 실패한다.
되돌리려면 시스템 설정 → 개인정보 보호 및 보안 → 로컬 네트워크.

## 규칙

| 항목 | 내용 |
|---|---|
| 팀 구성 | 도감 완성본 + 진행중 동반 포켓몬. **방 상한까지 보유한 만큼** |
| 비대칭 | 허용된다. 2마리 가진 사람은 6마리 상대에게 불리하다 (의도된 것) |
| 방 설정 | 최대 사용 포켓몬 수(1~6), 레벨(50/100), 상태이상·랭크변화·급소 on/off |
| 기술 | 배울 수 있는 기술 중 **랜덤 4개**를 개체별로 한 번 뽑아 고정. 배틀 중 매 턴 골라서 쓴다 |
| 교체 | 없다. 쓰러지면 그때 다음 포켓몬을 고른다 |
| 스탯 | 종족값 + 성격 보정. 개체값 31 / 노력치 0 전원 동일 |
| 누적 토큰 | **반영하지 않는다.** 승패를 가르는 건 포켓몬 종류·타입·성격·뽑힌 기술뿐 |

진행중(진화 미완성) 동반 포켓몬도 팀에 넣을 수 있지만 현재 단계의 종족값으로 싸운다 — 약하다.

## 구현된 전투 요소

원작 데미지 계산식, 18타입 상성표, 자기 타입 일치(STAB), 급소(1.5배), 명중/회피 랭크,
PP, 스피드 선공, 우선도, 난수 폭(85~100%), 다단히트, 흡수/반동, 회복기,
상태이상(마비·화상·독·맹독·잠듦·얼음·혼란)과 타입 면역, 능력치 랭크 ±6.

**미구현**: 특성, 날씨, 필드, 지배기, 발버둥. 이 효과만 가진 기술(트집·원더룸 등)은
"아무 일도 일어나지 않았다"로 처리된다. 기술 뽑기가 공격기를 최소 2개 보장하므로 배틀은 항상 진행된다.

## 검증

```sh
# 배틀 엔진 — 스탯 공식·상성표·전투 종료·HP 불변식·한국어 조사
./build/PokeBattleBar.app/Contents/MacOS/PokeBattleBar --selftest
./build/PokeBattleBar.app/Contents/MacOS/PokeBattleBar --selftest --a 87,317 --b 143,130,149 --verbose

# 네트워크 — Bonjour 광고/발견, TXT 레코드, TCP 프레이밍, 직렬화 왕복, 정원 초과 거절
./build/PokeBattleBar.app/Contents/MacOS/PokeBattleBar --nettest
```

## 데이터

| 위치 | 용도 |
|---|---|
| `~/Library/Application Support/PokeTokenBar/companion-state.json` | **읽기 전용.** 도감·동반 포켓몬 |
| `~/Library/Application Support/PokeTokenBar/sprites/` | 읽기 전용. 스프라이트 재활용 |
| `~/Library/Application Support/PokeBattleBar/pokeapi/` | PokeAPI 캐시 (종족값·기술·상성표) |
| `~/Library/Application Support/PokeBattleBar/movesets.json` | 개체별 고정 기술 4개 |
| `~/Library/Application Support/PokeBattleBar/sprites/` | 상대 포켓몬 스프라이트 캐시 |

첫 실행은 PokeAPI 에서 데이터를 받으므로 느리다. 이후는 전부 캐시에서 읽는다.

## 알려진 한계

- **부정 방지가 없다.** `companion-state.json` 은 평문이고, 게스트는 자기 팀을 스스로 신고해서 보낸다.
  상태 파일을 고쳐 전설 포켓몬 6마리를 주장할 수 있다. 사내 LAN 전제라 막지 않았다.
- 배틀 계산은 **호스트(방 만든 쪽)** 가 전담한다. 호스트가 앱을 닫으면 배틀이 끝난다.
- 한 방에 1:1 만 들어간다. 두 번째 접속은 거절된다.
- UI 는 자동 검증되지 않는다 (엔진·네트워크만 테스트 범위).

## 구조

```
Sources/PokeBattleBar/
  Companion/CompanionState.swift   PokeTokenBar 상태 파일 읽기
  Pokedex/PokeAPI.swift            종족값·기술·상성표 (디스크 캐시)
  Pokedex/MovesetStore.swift       랜덤 기술 4개 뽑아 고정
  Pokedex/TypeChart.swift          타입 상성 배율
  Pokedex/Nature.swift             성격 보정 25종
  Pokedex/Korean.swift             조사(은/는, 이/가) 처리
  Battle/Battler.swift             원작 스탯 공식
  Battle/BattleEngine.swift        턴 해석·데미지·상태이상·랭크
  Net/Wire.swift                   메시지 정의 + 길이 프레이밍
  Net/PeerLink.swift               TCP 연결 한 개
  Net/LanService.swift             Bonjour 방 광고 / 검색
  UI/AppModel.swift                호스트·게스트 상태 기계
  UI/Views.swift                   로비·방·선봉·배틀·결과 화면
  SelfTest.swift / NetTest.swift   헤드리스 검증
```
