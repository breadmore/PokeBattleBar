#!/bin/bash
# 맥에서 중계기를 **밖에서 붙을 수 있게** 띄웁니다.
#
# 공유기를 건드릴 수 없을 때 쓰는 쪽입니다. 중계기와 터널을 같이 켜고,
# 동료에게 그대로 불러줄 주소 한 줄을 보여줍니다.
#
#   bash scripts/mac-relay.sh                암호는 자동 생성
#   bash scripts/mac-relay.sh --secret 1234  암호를 직접 정하고
#
# 끄려면 Ctrl+C — 중계기와 터널이 같이 내려갑니다.
#
# 파이(늘 켜두는 기계)라면 이게 아니라 install-relay.sh 를 쓰세요.
# 서비스로 등록돼서 재부팅해도 살아 있습니다.
set -euo pipefail

PORT=47474
SECRET=""
HERE="$(cd "$(dirname "$0")" && pwd)"
BORE_SERVER=bore.pub

while [ $# -gt 0 ]; do
    case "$1" in
        --secret) SECRET="${2:-}"; shift 2 ;;
        --port)   PORT="${2:-}"; shift 2 ;;
        -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
        *) echo "모르는 옵션: $1" >&2; exit 1 ;;
    esac
done

command -v bore >/dev/null || {
    echo "bore 가 없습니다. 먼저 설치하세요:  brew install bore-cli" >&2
    exit 1
}

# 암호를 여기서 정한다 — 중계기가 만들게 두면 로그를 뒤져야 알 수 있다.
if [ -z "$SECRET" ]; then
    SECRET=$(python3 -c "
import secrets
a='ABCDEFGHJKMNPQRSTUVWXYZ23456789'
print(''.join(secrets.choice(a) for _ in range(4)))
")
fi

LOG=$(mktemp -t pokebattle-relay)
BORELOG=$(mktemp -t pokebattle-bore)
RELAY_PID=""
BORE_PID=""
TAIL_PID=""
CLEANED=""
cleanup() {
    # INT/TERM 트랩이 돈 뒤 EXIT 트랩이 또 돈다 — 한 번만 돌게 막는다
    [ -n "$CLEANED" ] && return
    CLEANED=1
    [ -n "$TAIL_PID" ]  && kill "$TAIL_PID"  2>/dev/null || true
    [ -n "$BORE_PID" ]  && kill "$BORE_PID"  2>/dev/null || true
    [ -n "$RELAY_PID" ] && kill "$RELAY_PID" 2>/dev/null || true
    echo ""
    echo "중계기를 껐습니다."
}
trap cleanup EXIT INT TERM

echo "==> 중계기를 켭니다 (포트 $PORT)"
python3 "$HERE/relay.py" --port "$PORT" --secret "$SECRET" > "$LOG" 2>&1 &
RELAY_PID=$!
sleep 2
kill -0 "$RELAY_PID" 2>/dev/null || { echo "중계기가 뜨지 못했습니다:"; cat "$LOG"; exit 1; }

echo "==> 터널을 엽니다 (공유기를 건드리지 않습니다)"
# 같은 포트를 먼저 달라고 한다 — 받아지면 다음에 켤 때도 주소가 같다
bore local "$PORT" --to "$BORE_SERVER" --port "$PORT" > "$BORELOG" 2>&1 &
BORE_PID=$!
ADDR=""
for _ in $(seq 1 8); do
    sleep 1
    ADDR=$(grep -o 'listening at [^ ]*' "$BORELOG" | tail -1 | awk '{print $3}')
    [ -n "$ADDR" ] && break
    kill -0 "$BORE_PID" 2>/dev/null || break
done

if [ -z "$ADDR" ]; then
    echo "   고정 포트를 못 받았습니다 — 아무 포트나 받습니다"
    kill "$BORE_PID" 2>/dev/null || true
    bore local "$PORT" --to "$BORE_SERVER" > "$BORELOG" 2>&1 &
    BORE_PID=$!
    for _ in $(seq 1 8); do
        sleep 1
        ADDR=$(grep -o 'listening at [^ ]*' "$BORELOG" | tail -1 | awk '{print $3}')
        [ -n "$ADDR" ] && break
    done
fi

if [ -z "$ADDR" ]; then
    echo "터널 주소를 읽지 못했습니다:" >&2
    cat "$BORELOG" >&2
    exit 1
fi

cat <<EOF

════════════════════════════════════════════════
  동료에게 이 두 줄을 그대로 알려주세요

      주소    $ADDR
      암호    $SECRET

  앱에서 [중계 서버로 만나기] 에 적으면 됩니다.
  참가자는 아무것도 설치하지 않아도 됩니다.
════════════════════════════════════════════════

  상태 화면   http://127.0.0.1:47475/
  끄기        Ctrl+C

EOF

# 로그를 흘려보내며 기다린다 — 누가 들어오는지 보인다.
#
# **tail 을 포그라운드로 두면 안 된다.** bash 는 포그라운드 자식을
# 기다리는 동안 트랩을 미루므로, Ctrl+C 를 눌러도 cleanup 이 돌지 않고
# 중계기와 터널이 살아남는다. wait 는 신호에 바로 깨어난다.
tail -f "$LOG" &
TAIL_PID=$!
wait "$TAIL_PID"
