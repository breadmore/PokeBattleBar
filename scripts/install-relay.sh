#!/bin/bash
# PokeBattleBar 중계기 설치 — 라즈베리파이(또는 아무 리눅스)에서 실행합니다.
#
# 이 기계는 배틀을 하지 않습니다. 서로 다른 네트워크에 있는 두 사람을
# **이어주기만** 합니다. 그래서 포켓몬 앱을 깔 필요가 없고(맥 전용입니다),
# 파이썬 3 만 있으면 됩니다.
#
#   bash install-relay.sh                     암호 없이
#   bash install-relay.sh                      암호를 자동으로 만들어 준다
#   bash install-relay.sh --secret 우리팀암호   암호를 직접 정하고
#   bash install-relay.sh --no-secret          암호 없이 (같은 집 안에서만)
#   bash install-relay.sh --port 47474 --web-port 47475
#
# 끝나면 동료에게 알려줄 주소와 상태 화면 주소를 출력합니다.
set -euo pipefail

PORT=47474
WEB_PORT=47475
SECRET=""
NO_SECRET=""
SERVICE=pokebattle-relay

while [ $# -gt 0 ]; do
    case "$1" in
        --secret)   SECRET="${2:-}"; shift 2 ;;
        --no-secret) NO_SECRET=1; shift ;;
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

cat <<EOF

────────────────────────────────────────────────────────────
설치 끝났습니다.

  동료가 앱에 적을 주소   ${IP}:${PORT}
  상태 화면(브라우저)      http://${IP}:${WEB_PORT}/
$([ -n "$SECRET" ] && echo "  중계 암호               ${SECRET}")$([ -n "$GENERATED" ] && echo "
  ↑ 암호를 지정하지 않아 자동으로 만들었습니다. 위 두 줄을 동료에게 알려주세요.")$([ -z "$SECRET" ] && echo "
  ⚠ 암호 없이 열었습니다 — 주소를 아는 누구나 붙을 수 있습니다.")

$(case "$REACH" in
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
esac)$([ -n "$TS_IP" ] && echo "

  ★ Tailscale 주소가 있습니다: ${TS_IP}:${PORT}
    참가자도 Tailscale 을 깔았다면 이 주소가 제일 확실합니다
    (포트포워딩도 공인 주소도 필요 없습니다).")

넘겨야 하는 것은 이 기계 하나뿐이고, 배틀하는 두 사람은
아무 설정도 필요 없습니다.

  ★ 밖에서 붙을 수 있는지 판정  pokebattle-relay --checknet
  ★ 이 안내를 다시 보려면      pokebattle-relay-help
    (또는  pokebattle-relay help )

  상태 보기   sudo systemctl status ${SERVICE}
  로그 보기   journalctl -u ${SERVICE} -f
  끄기        sudo systemctl disable --now ${SERVICE}
────────────────────────────────────────────────────────────
EOF
