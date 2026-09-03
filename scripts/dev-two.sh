#!/bin/bash
# 한 대의 맥에서 PokeBattleBar 를 두 개 띄운다 — 혼자 배틀을 테스트하기 위한 것.
# 배포용이 아니다.
#
#   ./scripts/dev-two.sh                    두 인스턴스 모두 내 도감으로
#   ./scripts/dev-two.sh 94,555 6,479       왼쪽/오른쪽 팀을 직접 지정
#
# 팀을 지정하면 그 인스턴스는 PokeTokenBar 를 읽지 않는다 (도감을 만질 필요 없음).
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM_A="${1:-}"
TEAM_B="${2:-}"

APP="build.noindex/PokeBattleBar.app"
if [ ! -d "$APP" ]; then
    echo "==> 앱 번들이 없어 빌드합니다"
    VERSION="dev" ./scripts/bundle.sh >/dev/null
fi
BIN="$APP/Contents/MacOS/PokeBattleBar"
[ -x "$BIN" ] || { echo "실행 파일이 없습니다: $BIN" >&2; exit 1; }

# 이미 떠 있는 테스트 인스턴스를 정리한다 (배포 설치본은 건드리지 않는다)
pkill -f "$PWD/$BIN" 2>/dev/null || true
sleep 1

launch() {
    local tag="$1" team="$2"
    # 번들 안의 실행 파일을 직접 실행한다 — open(1) 은 두 번째 실행에서
    # 새 프로세스를 띄우지 않고 기존 창만 활성화한다.
    # POKEBATTLE_NETLOG=1 로 실행하면 로비 광고·검색 로그를 파일로 남긴다
    local log=/dev/null
    if [ "${POKEBATTLE_NETLOG:-}" = "1" ]; then log="/tmp/pokenet-$tag.log"; fi
    if [ -n "$team" ]; then
        POKEBATTLE_NETLOG="${POKEBATTLE_NETLOG:-}" POKEBATTLE_PROFILE="$tag" \
            POKEBATTLE_TEAM="$team" "$BIN" >"$log" 2>&1 &
    else
        POKEBATTLE_NETLOG="${POKEBATTLE_NETLOG:-}" POKEBATTLE_PROFILE="$tag" \
            "$BIN" >"$log" 2>&1 &
    fi
    echo "   [$tag] pid $!${team:+   팀 $team}"
}

echo "==> 두 인스턴스 실행"
launch A "$TEAM_A"
sleep 2                     # 창이 겹치지 않게 조금 띄운다
launch B "$TEAM_B"

cat <<'EOF'

==> 테스트 방법
   1. 〔테스트 A〕 창에서  방 만들기
   2. 〔테스트 B〕 창에서  같은 네트워크 목록에 뜬 "…-A의 방" 에 접속
      (자기 맥에 뜬 방도 Bonjour 로 그대로 보입니다)
   3. 양쪽에서 선두 포켓몬을 고르면 배틀 시작

   · 창 위쪽 주황색 띠에 어느 인스턴스인지 표시됩니다
   · 승패 기록은 record-test-A.json / record-test-B.json 으로 따로 쌓입니다
     (실제 기록 record.json 은 건드리지 않습니다)
   · 종료:  pkill -f build.noindex/PokeBattleBar.app

==> 특정 포켓몬끼리 붙여보기
   ./scripts/dev-two.sh 555,479,351 94,386,137
   POKEBATTLE_NATURE=hardy 를 붙이면 성격도 지정됩니다
EOF
