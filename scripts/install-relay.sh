#!/bin/bash
# PokeBattleBar 중계기 설치 — 라즈베리파이(또는 아무 리눅스)에서 실행합니다.
#
# 이 기계는 배틀을 하지 않습니다. 서로 다른 네트워크에 있는 두 사람을
# **이어주기만** 합니다. 그래서 포켓몬 앱을 깔 필요가 없고(맥 전용입니다),
# 파이썬 3 만 있으면 됩니다.
#
#   bash install-relay.sh                      이거 하나면 끝납니다
#   bash install-relay.sh --secret 우리팀암호   암호를 직접 정하고
#   bash install-relay.sh --no-secret          암호 없이 (같은 집 안에서만)
#   bash install-relay.sh --port 47474 --web-port 47475
#   bash install-relay.sh --no-auto-open       길 트는 것을 직접 하겠다
#
# **밖에서 붙을 수 있게 하는 것까지 알아서 합니다.**
#   1) 방화벽(ufw)이 켜져 있으면 포트를 엽니다
#   2) 공유기에 UPnP 로 포트포워딩을 요청합니다
#   3) 그래도 안 되면(통신사 CGNAT 등) Tailscale 을 깔아 우회합니다
# 끝나면 **실제로 통하는 주소**와 암호를 출력합니다.
set -euo pipefail

PORT=47474
WEB_PORT=47475
SECRET=""
NO_SECRET=""
AUTO_OPEN=1
SERVICE=pokebattle-relay

while [ $# -gt 0 ]; do
    case "$1" in
        --secret)   SECRET="${2:-}"; shift 2 ;;
        --no-secret) NO_SECRET=1; shift ;;
        --no-auto-open) AUTO_OPEN=""; shift ;;
        --port)     PORT="${2:-}"; shift 2 ;;
        --web-port) WEB_PORT="${2:-}"; shift 2 ;;
        -h|--help)  sed -n '2,14p' "$0"; exit 0 ;;
        *) echo "모르는 옵션: $1" >&2; exit 1 ;;
    esac
done

SRC="$(cd "$(dirname "$0")" && pwd)/relay.py"
[ -f "$SRC" ] || { echo "relay.py 를 찾을 수 없습니다: $SRC" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 가 필요합니다: sudo apt install python3" >&2; exit 1; }

echo "==> 중계기 설치"
sudo install -m 0755 "$SRC" /usr/local/bin/pokebattle-relay

# 설정값이 채워진 설명서를 아무 때나 볼 수 있게 한다.
# 포트를 래퍼에 박아두는 이유는 **암호를 인자로 넘기지 않기 위해서**다 —
# 인자로 넘기면 ps 목록에 암호가 그대로 보인다.
echo "==> 설명서 명령 설치 (pokebattle-relay help)"
sudo tee /usr/local/bin/pokebattle-relay-help >/dev/null <<EOF
#!/bin/bash
# PokeBattleBar 중계기 설명서 — 설치할 때 정한 포트가 박혀 있습니다.
exec /usr/bin/python3 /usr/local/bin/pokebattle-relay --guide \\
    --port $PORT --web-port $WEB_PORT
EOF
sudo chmod 0755 /usr/local/bin/pokebattle-relay-help

# **암호를 안 주면 여기서 만든다.**
#
# 서비스로 등록하면 화면이 안 보이므로, 중계기가 켜질 때 자동 생성하게
# 두면 동료에게 알려줄 값을 알 수가 없다. 설치 시점에 정해서 아래
# 안내문에 찍어준다. 정말 열어두려면 --no-secret 을 준다.
GENERATED=""
if [ -z "$SECRET" ] && [ "$NO_SECRET" != "1" ]; then
    SECRET=$(python3 -c "
import secrets
a='ABCDEFGHJKMNPQRSTUVWXYZ23456789'
r=''.join(secrets.choice(a) for _ in range(12))
print('-'.join(r[i:i+4] for i in range(0,12,4)))
")
    GENERATED="1"
fi

ARGS="--port $PORT --web-port $WEB_PORT"
if [ -n "$SECRET" ]; then
    ARGS="$ARGS --secret $SECRET"
else
    ARGS="$ARGS --no-secret"
fi

if command -v systemctl >/dev/null; then
    echo "==> 부팅할 때 자동으로 뜨도록 등록 (systemd)"
    # 암호가 들어가므로 서비스 파일은 root 만 읽게 둔다
    sudo tee /etc/systemd/system/$SERVICE.service >/dev/null <<EOF
[Unit]
Description=PokeBattleBar relay
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/pokebattle-relay $ARGS
Restart=always
RestartSec=3
User=nobody
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF
    sudo chmod 600 /etc/systemd/system/$SERVICE.service
    sudo systemctl daemon-reload
    sudo systemctl enable --now $SERVICE
    sleep 1
    sudo systemctl --no-pager --lines=5 status $SERVICE || true
else
    echo "systemd 가 없습니다 — 직접 실행하세요:"
    echo "    python3 /usr/local/bin/pokebattle-relay $ARGS"
fi

# 알려줄 주소를 찾고, **밖에서 닿을 수 있는 상태인지 판정한다.**
#
# 사설 주소(10.x·172.16~31.x·192.168.x)는 그 네트워크 안에서만 쓸 수 있다.
# 밖에서 붙으려면 공유기에서 포트를 넘겨주거나, 공인 주소가 있어야 한다.
# 그런데 통신사 CGNAT(100.64~127.x) 뒤에 있으면 포트포워딩도 못 한다 —
# 그 주소를 소유한 것이 사용자가 아니라 통신사이기 때문이다.
#
# 이 판정을 사람이 하게 두면 "왜 안 되지" 로 한참 헤맨다.
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
[ -n "$IP" ] || IP="<이 기계의 주소>"

# 인터넷에서 보이는 주소 (없으면 빈 값)
PUBLIC_IP=$(curl -s --max-time 6 https://api.ipify.org 2>/dev/null || true)

case "$IP" in
    10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*) PRIVATE=1 ;;
    *) PRIVATE="" ;;
esac

REACH="unknown"
if [ -n "$PUBLIC_IP" ]; then
    if [ "$PUBLIC_IP" = "$IP" ]; then
        REACH="public"          # 공인 주소가 직접 붙어 있다 — 가장 쉬운 경우
    else
        case "$PUBLIC_IP" in
            100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*)
                REACH="cgnat" ;;   # 통신사 CGNAT — 포트포워딩 불가
            *) REACH="nat" ;;      # 보통 공유기 — 포트포워딩 가능
        esac
    fi
fi

# Tailscale 주소가 있으면 그게 제일 쉽다 (포트포워딩 없이 밖에서 닿는다)
TS_IP=$(tailscale ip -4 2>/dev/null | head -1 || true)

# ─────────────────────────────────────────────────────────────
# 밖에서 붙을 수 있게 길을 튼다
# ─────────────────────────────────────────────────────────────
#
# 사람이 판정하고 공유기를 만지게 두면 "왜 안 되지" 로 한참 헤맨다.
# 할 수 있는 것은 기계가 하고, 못 하는 것만 사람에게 넘긴다.

OPENED=""        # 실제로 밖에서 통하는 것으로 확인된 주소
NOTES=""         # 사람에게 넘길 남은 일

note() { NOTES="${NOTES}
  $1"; }

if [ -n "$AUTO_OPEN" ]; then
    echo "==> 밖에서 붙을 수 있게 길을 트는 중"

    # 1) 방화벽 — ufw 가 켜져 있을 때만 건드린다
    if command -v ufw >/dev/null && sudo ufw status 2>/dev/null | grep -q "Status: active"; then
        sudo ufw allow "$PORT"/tcp >/dev/null 2>&1 && echo "    방화벽 ${PORT}/tcp 열었습니다"
    fi

    # 2) 공유기에 UPnP 로 포트포워딩을 요청한다.
    #    되는 공유기가 꽤 많고, 되면 사람이 설정을 만질 필요가 없다.
    if [ "$REACH" = "nat" ]; then
        if ! command -v upnpc >/dev/null; then
            echo "    UPnP 도구를 설치합니다 (miniupnpc)"
            sudo apt-get install -y -qq miniupnpc >/dev/null 2>&1 || true
        fi
        if command -v upnpc >/dev/null; then
            if upnpc -e "PokeBattleBar relay" -a "$IP" "$PORT" "$PORT" TCP >/dev/null 2>&1; then
                echo "    공유기에 포트포워딩을 요청했습니다 (UPnP)"
            else
                echo "    UPnP 가 안 됩니다 — 공유기에서 직접 넣어야 합니다"
            fi
        fi
    fi

    # 3) 정말 통하는지 **밖에서** 확인한다.
    #    중계기가 실제로 떠 있어야 의미가 있다 (위에서 서비스를 시작했다).
    #    안에서 자기 공인 IP 로 붙어보는 것은 공유기 종류에 따라
    #    되기도 안 되기도 해서(헤어핀 NAT) 믿을 수 없다.
    if [ -n "$PUBLIC_IP" ] && [ "$REACH" != "cgnat" ]; then
        echo "    밖에서 ${PUBLIC_IP}:${PORT} 로 닿는지 확인하는 중…"
        # 중계기를 잠깐 띄워 두고 확인한다 (서비스가 이미 떠 있으면 그대로 쓴다)
        sleep 2
        # portchecker.io 는 POST 로 물어야 한다 (GET 은 405 를 준다).
        # 열린 포트면 status:true, 닫혀 있으면 false 가 온다 — 실제로 확인했다.
        CHECK=$(curl -s --max-time 15 -X POST "https://portchecker.io/api/v1/query" \
            -H "Content-Type: application/json" \
            -d "{\"host\":\"${PUBLIC_IP}\",\"ports\":[${PORT}]}" 2>/dev/null || true)
        case "$CHECK" in
            *'"status":true'*) OPENED="${PUBLIC_IP}:${PORT}" ;;
            *'"status":false'*)
                note "밖에서 ${PUBLIC_IP}:${PORT} 로 닿지 않습니다."
                note "  공유기에서 ${PORT}/tcp 를 ${IP} 로 넘겨 주세요(포트포워딩)."
                note "  이미 넣으셨다면 공유기를 다시 시작해 보세요." ;;
            *) : ;;
        esac
        if [ -z "$OPENED" ] && [ -z "$NOTES" ]; then
            note "밖에서 ${PUBLIC_IP}:${PORT} 로 닿는지 확인하지 못했습니다 (확인 서비스 응답 없음)."
            note "  직접 확인: https://www.yougetsignal.com/tools/open-ports/  (포트 ${PORT})"
        fi
        [ -n "$OPENED" ] && echo "    ✓ 밖에서 닿습니다 — ${OPENED}"
    fi

    # 4) CGNAT 이면 포트포워딩으로는 답이 없다 — Tailscale 로 우회한다
    if [ "$REACH" = "cgnat" ] && [ -z "$TS_IP" ]; then
        echo "    통신사 CGNAT 뒤입니다 — 포트포워딩으로는 밖에서 못 붙습니다"
        echo "    Tailscale 을 설치합니다 (무료 · 기기 100대까지)"
        if curl -fsSL https://tailscale.com/install.sh 2>/dev/null | sh >/dev/null 2>&1; then
            echo ""
            echo "    아래 주소를 브라우저로 열어 로그인하세요 (한 번만 하면 됩니다):"
            sudo tailscale up 2>&1 | sed 's/^/      /' || true
            TS_IP=$(tailscale ip -4 2>/dev/null | head -1 || true)
        else
            note "Tailscale 자동 설치에 실패했습니다. 직접 설치해 주세요:"
            note "    curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up"
        fi
    fi

    [ -n "$TS_IP" ] && OPENED="${TS_IP}:${PORT}"
fi

# 동료에게 줄 주소 — 확인된 것이 있으면 그것을, 없으면 짐작되는 것을
SHARE="${OPENED:-${PUBLIC_IP:-$IP}:${PORT}}"

cat <<EOF

────────────────────────────────────────────────────────────
설치 끝났습니다.

  동료가 앱에 적을 주소   ${SHARE}$([ -n "$OPENED" ] && echo "   ← 밖에서 닿는 것을 확인했습니다")
  상태 화면(브라우저)      http://${IP}:${WEB_PORT}/
$([ -n "$SECRET" ] && echo "  중계 암호               ${SECRET}")$([ -n "$GENERATED" ] && echo "
  ↑ 암호를 지정하지 않아 자동으로 만들었습니다. 위 두 줄을 동료에게 알려주세요.")$([ -z "$SECRET" ] && echo "
  ⚠ 암호 없이 열었습니다 — 주소를 아는 누구나 붙을 수 있습니다.")

$(if [ -n "$OPENED" ]; then
  echo "밖에서 닿는 것을 확인했습니다. 더 하실 일이 없습니다 —
위 주소와 암호를 동료에게 알려주기만 하면 됩니다."
else
case "$REACH" in
public)
  echo "이 기계에 공인 주소가 직접 붙어 있습니다. 방화벽에서 ${PORT}/tcp 만
열면 밖에서도 바로 붙습니다."
  ;;
nat)
  echo "이 기계는 공유기 뒤에 있습니다 (공인 주소 ${PUBLIC_IP}).
밖에서도 쓰려면 공유기에서 **${PORT}/tcp 를 ${IP} 로 포워딩**하고,
동료에게는 ${PUBLIC_IP}:${PORT} 를 알려주세요."
  ;;
cgnat)
  echo "⚠ 통신사 CGNAT 뒤에 있습니다 (공인 주소 ${PUBLIC_IP}).
   **포트포워딩으로는 밖에서 붙을 수 없습니다** — 그 주소는 통신사 것입니다.
   아래 중 하나를 쓰세요:
     · Tailscale  — 파이와 참가자 전원에게 깔면 100.x 주소로 바로 붙습니다
     · TCP 터널   — 예: ngrok tcp ${PORT}  (받은 host:port 를 알려주면 끝)
     · 공인 주소가 있는 서버에 중계기를 올린다 (가장 안정적)"
  ;;
*)
  echo "밖에서도 쓰려면 공유기에서 **${PORT}/tcp** 를 이 기계로 넘겨주세요.
(인터넷 쪽 주소를 확인하지 못했습니다)"
  ;;
esac
fi)$([ -n "$TS_IP" ] && echo "

  ★ Tailscale 주소가 있습니다: ${TS_IP}:${PORT}
    참가자도 Tailscale 을 깔았다면 이 주소가 제일 확실합니다
    (포트포워딩도 공인 주소도 필요 없습니다).")

넘겨야 하는 것은 이 기계 하나뿐이고, 배틀하는 두 사람은
아무 설정도 필요 없습니다.

$([ -n "$NOTES" ] && echo "
  남은 일${NOTES}
")
  ★ 밖에서 붙을 수 있는지 판정  pokebattle-relay --checknet
  ★ 이 안내를 다시 보려면      pokebattle-relay-help
    (또는  pokebattle-relay help )

  상태 보기   sudo systemctl status ${SERVICE}
  로그 보기   journalctl -u ${SERVICE} -f
  끄기        sudo systemctl disable --now ${SERVICE}
────────────────────────────────────────────────────────────
EOF
