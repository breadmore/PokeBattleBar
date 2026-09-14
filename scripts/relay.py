#!/usr/bin/env python3
"""PokeBattleBar 방 중계기.

라즈베리파이처럼 **양쪽에서 닿는 자리**에 한 대 띄워두면, 서로 다른 네트워크에
있는 두 사람이 만날 수 있다. 양쪽 모두 이쪽으로 나가는 연결을 걸기 때문에
NAT 뒤에 있어도 되고, 포트를 열어야 하는 곳은 이 기계 한 대뿐이다.

## 게임을 모른다

짝이 맞은 뒤로는 **바이트를 그대로 흘리기만** 한다. 그래서:
  - 앱 프로토콜(v12 …)이 올라가도 이 파일은 그대로 둬도 된다
  - 버전이 안 맞으면 두 앱이 서로에게 알려준다 (여기서 판단하지 않는다)
  - 배틀 규칙이 여기 들어오지 않으므로 승패 권위는 계속 방장 쪽 앱에 있다

## 핸드셰이크

길이 4바이트(빅엔디안) + JSON, 앱의 RelayLink.swift 와 같은 형식이다.

    받는다: {"role":"host"|"guest", "room":"ABC12", "name":"영훈", "secret":null}
    보낸다: {"ok":true, "registered":true}                 방 등록됨 (host)
            {"ok":true, "paired":true, "peer":"상대이름"}   짝 맞음 (양쪽)
            {"ok":false, "reason":"..."}                   거절

## 실행

    python3 relay.py                          기본 0.0.0.0:51235
    python3 relay.py --port 51235 --secret 우리팀암호
    python3 relay.py --max-rooms 50 --idle 1800

    # 부팅할 때 같이 뜨게 (라즈베리파이)
    sudo cp relay.py /usr/local/bin/pokebattle-relay
    sudo tee /etc/systemd/system/pokebattle-relay.service <<'EOF'
    [Unit]
    Description=PokeBattleBar relay
    After=network-online.target
    [Service]
    ExecStart=/usr/bin/python3 /usr/local/bin/pokebattle-relay --secret 우리팀암호
    Restart=always
    User=nobody
    [Install]
    WantedBy=multi-user.target
    EOF
    sudo systemctl enable --now pokebattle-relay

파이썬 3.8+ 면 되고, 표준 라이브러리만 쓴다.
"""

import argparse
import asyncio
import json
import logging
import shutil
import socket
import struct
import subprocess
import sys
import time

# 핸드셰이크 프레임 상한. 앱의 RelayCodec.maxFrame 과 맞춘다 —
# 작게 잡아야 엉뚱한 데이터를 일찍 끊을 수 있다.
MAX_HELLO = 64 * 1024
# 짝이 맞은 뒤 흘리는 한 조각의 크기 (게임 프레임 자체는 앱이 조립한다)
CHUNK = 64 * 1024

log = logging.getLogger("relay")


class Room:
    """방 하나. 방장이 등록하고 손님을 기다린다.

    `paired_event` / `released` 두 신호로 **읽기 소유권**을 넘긴다.
    이게 없으면 방장을 지켜보던 읽기와 중계 파이프가 같은 스트림을 동시에
    읽으려 해서 asyncio 가 거부하고(read() called while another coroutine…),
    방장 → 손님 방향이 통째로 막힌다.
    """

    __slots__ = ("code", "host_name", "host_reader", "host_writer",
                 "created", "paired", "paired_event", "released")

    def __init__(self, code, host_name, reader, writer):
        self.code = code
        self.host_name = host_name
        self.host_reader = reader
        self.host_writer = writer
        self.created = time.monotonic()
        self.paired = False
        self.paired_event = asyncio.Event()   # 손님이 왔다
        self.released = asyncio.Event()       # 방장 감시를 접었다 (파이프가 읽어도 된다)


class LobbyClient:
    """중계 로비에 상주하는 사람 하나.

    배틀 연결과 **다른 연결**이다. 배틀 연결은 짝이 맞으면 바이트만 흘리는
    파이프가 되어버려서, 그 위에 "누가 로비에 있는지" 를 얹을 수가 없다.
    상주 연결을 따로 두면 중계기는 배틀에 대해 계속 아무것도 모른 채로
    로비만 관리한다.
    """

    __slots__ = ("name", "status", "room", "writer", "lock", "joined")

    def __init__(self, name, writer):
        self.name = name
        self.status = "free"
        self.room = None
        self.writer = writer
        # 스냅샷을 보내는 곳이 둘(입장 직후·주기 푸시)이라 쓰기를 직렬화한다
        self.lock = asyncio.Lock()
        self.joined = time.monotonic()


class Relay:
    def __init__(self, secret=None, max_rooms=50, idle=1800, port=51235):
        self.secret = secret
        self.max_rooms = max_rooms
        self.idle = idle
        self.port = port
        self.rooms = {}
        self.lobby = {}          # id -> LobbyClient (중계 로비 상주자)
        self.next_id = 1
        self.active = 0          # 지금 중계 중인 배틀 수
        self.total = 0           # 시작 후 성사된 배틀 수
        self.started = time.monotonic()

    # --- 프레이밍 -------------------------------------------------------

    @staticmethod
    async def read_frame(reader):
        header = await reader.readexactly(4)
        (length,) = struct.unpack(">I", header)
        if length > MAX_HELLO:
            raise ValueError(f"프레임이 너무 큽니다 ({length})")
        return json.loads(await reader.readexactly(length))

    @staticmethod
    async def write_frame(writer, obj):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        writer.write(struct.pack(">I", len(body)) + body)
        await writer.drain()

    async def reject(self, writer, reason):
        try:
            await self.write_frame(writer, {"ok": False, "reason": reason})
        except (OSError, ConnectionError):
            pass

    # --- 접속 처리 -------------------------------------------------------

    async def handle(self, reader, writer):
        peer = writer.get_extra_info("peername")
        try:
            hello = await asyncio.wait_for(self.read_frame(reader), timeout=20)
        except Exception as e:
            log.info("%s 핸드셰이크 실패: %s", peer, e)
            writer.close()
            return

        role = hello.get("role")
        room_code = str(hello.get("room", "")).strip().upper()
        name = str(hello.get("name", "?"))[:64]

        if self.secret and hello.get("secret") != self.secret:
            log.info("%s 암호 불일치", peer)
            await self.reject(writer, "중계 서버 암호가 다릅니다")
            writer.close()
            return

        # 방 코드 검사는 role 판별 뒤에 한다 — 로비 상주자는 방 코드가 없다
        if role == "lobby":
            await self.serve_lobby(name, reader, writer, peer)
            return
        if not room_code:
            await self.reject(writer, "방 코드가 비어 있습니다")
            writer.close()
            return

        if role == "host":
            await self.serve_host(room_code, name, reader, writer, peer)
        elif role == "guest":
            await self.serve_guest(room_code, name, reader, writer, peer)
        else:
            await self.reject(writer, "role 은 host · guest · lobby 중 하나여야 합니다")
            writer.close()

    # --- 중계 로비 -------------------------------------------------------

    def snapshot(self):
        """로비 상주자와 대기 중인 방. 배틀 내용은 들어가지 않는다."""
        now = time.monotonic()
        return {
            "type": "lobby",
            "peers": [
                {"name": c.name, "status": c.status, "room": c.room}
                for c in sorted(self.lobby.values(), key=lambda c: c.joined)
            ],
            "rooms": [
                {"code": r.code, "host": r.host_name, "waiting": int(now - r.created)}
                for r in sorted(self.rooms.values(), key=lambda r: r.created)
            ],
        }

    async def send_to(self, client, payload):
        try:
            async with client.lock:
                await self.write_frame(client.writer, payload)
            return True
        except (OSError, ConnectionError):
            return False

    async def broadcast_lobby(self):
        if not self.lobby:
            return
        payload = self.snapshot()
        dead = []
        for cid, client in list(self.lobby.items()):
            if not await self.send_to(client, payload):
                dead.append(cid)
        for cid in dead:
            self.lobby.pop(cid, None)

    async def lobby_pusher(self, interval=3):
        """방 목록은 배틀 연결 쪽에서 바뀌므로 주기적으로도 밀어준다.

        이벤트마다 broadcast 를 심는 것보다 단순하고, 3초면 사람이 기다리는
        체감으로 충분하다. 상주자 변화는 즉시 밀어준다.
        """
        while True:
            await asyncio.sleep(interval)
            self.sweep()
            await self.broadcast_lobby()

    def find_lobby(self, name):
        """이름으로 로비 상주자를 찾는다 (같은 이름이면 먼저 들어온 사람)."""
        for client in sorted(self.lobby.values(), key=lambda c: c.joined):
            if client.name == name:
                return client
        return None

    async def forward_invite(self, sender, frame):
        """초대를 전달한다. 중계기는 방이 실제로 있는지만 확인한다.

        수락·거절은 두 앱이 알아서 하고, 중계기는 메시지를 옮기기만 한다 —
        여기에 규칙을 넣으면 앱을 고칠 때마다 중계기도 고쳐야 한다.
        """
        target_name = str(frame.get("to", ""))[:64]
        room = str(frame.get("room", "")).strip().upper()[:16]

        def fail(reason):
            return self.send_to(sender, {"type": "invitefailed",
                                         "peer": target_name, "reason": reason})

        if room not in self.rooms:
            await fail("방이 열려 있지 않습니다")
            return
        target = self.find_lobby(target_name)
        if target is None:
            await fail("상대가 중계 로비에 없습니다")
            return
        if target is sender:
            await fail("자신을 초대할 수 없습니다")
            return
        if target.status != "free":
            await fail("상대가 지금 배틀 중이거나 방을 열어둔 상태입니다")
            return

        ok = await self.send_to(target, {"type": "invite",
                                         "peer": sender.name, "room": room})
        if ok:
            log.info("초대 전달 %s → %s (방 %s)", sender.name, target_name, room)
        else:
            await fail("상대에게 전달하지 못했습니다")

    async def forward_decline(self, sender, frame):
        target = self.find_lobby(str(frame.get("to", ""))[:64])
        if target is None:
            return
        await self.send_to(target, {"type": "declined", "peer": sender.name})

    async def serve_lobby(self, name, reader, writer, peer):
        cid = self.next_id
        self.next_id += 1
        client = LobbyClient(name, writer)
        self.lobby[cid] = client
        log.info("로비 입장 %s from %s — 현재 %d명", name, peer, len(self.lobby))

        try:
            await self.write_frame(writer, {"ok": True, "registered": True})
        except (OSError, ConnectionError):
            self.lobby.pop(cid, None)
            writer.close()
            return
        await self.broadcast_lobby()

        try:
            while True:
                frame = await self.read_frame(reader)
                kind = frame.get("type")
                if kind == "status":
                    status = str(frame.get("status", "free"))
                    if status not in ("free", "hosting", "battling"):
                        status = "free"
                    room = frame.get("room")
                    client.status = status
                    client.room = str(room)[:16] if room else None
                    await self.broadcast_lobby()
                elif kind == "invite":
                    await self.forward_invite(client, frame)
                elif kind == "decline":
                    await self.forward_decline(client, frame)
                elif kind == "ping":
                    pass            # 연결 유지용 — 응답은 주기 푸시로 대신한다
        except (OSError, ConnectionError, asyncio.IncompleteReadError, ValueError,
                json.JSONDecodeError):
            pass
        finally:
            self.lobby.pop(cid, None)
            log.info("로비 퇴장 %s — 남은 %d명", name, len(self.lobby))
            writer.close()
            await self.broadcast_lobby()

    async def serve_host(self, code, name, reader, writer, peer):
        self.sweep()
        if code in self.rooms:
            await self.reject(writer, "같은 방 코드가 이미 있습니다")
            writer.close()
            return
        if len(self.rooms) >= self.max_rooms:
            await self.reject(writer, "중계 서버가 가득 찼습니다")
            writer.close()
            return

        room = Room(code, name, reader, writer)
        self.rooms[code] = room
        # peer 는 **붙어 온 쪽의 출발지 주소**다 (임시 포트라 매번 바뀐다).
        # 남에게 알려줄 주소가 아니다 — 그 오해가 실제로 있었다.
        log.info("방 등록 %s (%s) — 접속한 곳 %s · 현재 %d개",
                 code, name, peer, len(self.rooms))
        try:
            await self.write_frame(writer, {"ok": True, "registered": True})
        except (OSError, ConnectionError):
            self.rooms.pop(code, None)
            writer.close()
            return

        # 손님이 올 때까지 기다린다.
        #
        # 두 가지를 동시에 지켜본다: 손님 도착(paired_event)과 방장 연결 끊김.
        # 끊김은 읽기가 끝나는 것으로 알 수 있는데, **짝이 맞는 순간 그 읽기를
        # 반드시 접어야 한다** — 안 그러면 중계 파이프와 같은 스트림을 두 곳에서
        # 읽게 되어 방장 → 손님 방향이 막힌다. 접은 뒤 released 로 알려준다.
        watch = asyncio.ensure_future(reader.read(1))
        waiting = asyncio.ensure_future(room.paired_event.wait())
        try:
            done, _ = await asyncio.wait({watch, waiting},
                                         timeout=self.idle,
                                         return_when=asyncio.FIRST_COMPLETED)
            if waiting in done:
                watch.cancel()
                try:
                    await watch
                except (asyncio.CancelledError, OSError, ConnectionError):
                    pass
                room.released.set()     # 이제 pump 가 읽어도 된다
                return
            # 방장이 끊었거나(읽기 종료) 너무 오래 기다렸다
        except (OSError, ConnectionError, asyncio.IncompleteReadError):
            pass
        finally:
            for t in (watch, waiting):
                if not t.done():
                    t.cancel()
            if self.rooms.get(code) is room and not room.paired:
                self.rooms.pop(code, None)
                log.info("방 해제 %s (방장이 나갔거나 시간 초과)", code)
                writer.close()

    async def serve_guest(self, code, name, reader, writer, peer):
        self.sweep()
        room = self.rooms.get(code)
        if room is None:
            await self.reject(writer, f"{code} 방을 찾을 수 없습니다")
            writer.close()
            return
        if room.paired:
            await self.reject(writer, "이미 다른 사람이 들어간 방입니다")
            writer.close()
            return

        room.paired = True
        self.rooms.pop(code, None)      # 짝이 맞았으니 목록에서 뺀다 (1:1)
        room.paired_event.set()

        # 방장 쪽 감시 읽기가 접힐 때까지 기다린다 — 그래야 파이프가 그 스트림을
        # 안전하게 읽는다. 이 신호가 안 오면 방장 코루틴에 문제가 있는 것이다.
        try:
            await asyncio.wait_for(room.released.wait(), timeout=10)
        except asyncio.TimeoutError:
            log.warning("방 %s: 방장 쪽 정리가 끝나지 않았습니다", code)
            await self.reject(writer, "방장 쪽 상태가 이상합니다. 다시 시도해주세요")
            writer.close()
            room.host_writer.close()
            return

        log.info("짝 성사 %s: %s ↔ %s", code, room.host_name, name)

        try:
            await self.write_frame(room.host_writer, {"ok": True, "paired": True, "peer": name})
            await self.write_frame(writer, {"ok": True, "paired": True, "peer": room.host_name})
        except (OSError, ConnectionError):
            room.host_writer.close()
            writer.close()
            return

        # 여기서부터는 게임을 모른다 — 바이트를 그대로 흘린다.
        self.active += 1
        self.total += 1
        try:
            await asyncio.gather(
                self.pump(room.host_reader, writer),
                self.pump(reader, room.host_writer),
            )
        finally:
            self.active -= 1
        for w in (writer, room.host_writer):
            try:
                w.close()
            except OSError:
                pass
        log.info("배틀 종료 %s", code)

    @staticmethod
    async def pump(reader, writer):
        try:
            while True:
                data = await reader.read(CHUNK)
                if not data:
                    break
                writer.write(data)
                await writer.drain()
        except (OSError, ConnectionError, asyncio.IncompleteReadError):
            pass

    def sweep(self):
        """오래 기다린 빈 방을 치운다 (방장이 강제 종료된 경우)."""
        now = time.monotonic()
        stale = [c for c, r in self.rooms.items()
                 if not r.paired and now - r.created > self.idle]
        for c in stale:
            room = self.rooms.pop(c, None)
            if room:
                log.info("방 정리 %s (%d초 대기)", c, self.idle)
                try:
                    room.host_writer.close()
                except OSError:
                    pass


# --- 웹 UI -------------------------------------------------------------
#
# 라즈베리파이는 대개 화면이 없다. 그래서 "잘 돌고 있는지", "지금 누가 기다리는지",
# "동료에게 뭘 알려줘야 하는지" 를 브라우저로 볼 수 있게 한다.
# 읽기 전용이다 — 여기서 배틀에 개입할 수 있는 것은 없다.

PAGE = """<!doctype html><html lang="ko"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>PokeBattleBar 중계기</title>
<style>
 body{font:14px/1.6 -apple-system,BlinkMacSystemFont,"Apple SD Gothic Neo",sans-serif;
      margin:0;padding:24px;background:#ece4d0;color:#1c2b4a}
 .card{background:#f6f0e0;border:2px solid #1c2b4a;border-radius:10px;
       padding:16px 18px;margin:0 auto 14px;max-width:640px;box-shadow:3px 3px 0 rgba(28,43,74,.16)}
 h1{font-size:18px;margin:0 0 4px} h2{font-size:13px;margin:0 0 8px;color:#c8382e}
 .big{font-size:26px;font-weight:800;font-family:ui-monospace,Menlo,monospace}
 .dim{color:#6b7689;font-size:12px}
 table{width:100%;border-collapse:collapse;font-size:13px}
 th,td{text-align:left;padding:5px 4px;border-bottom:1px solid rgba(28,43,74,.18)}
 code{background:rgba(28,43,74,.08);padding:1px 5px;border-radius:4px;
      font-family:ui-monospace,Menlo,monospace}
 .ok{color:#2c8a55;font-weight:700}
</style>
<div class="card">
  <h1>🔴 PokeBattleBar 중계기</h1>
  <div class="dim">이 기계가 서로 다른 네트워크에 있는 두 사람을 이어줍니다.</div>
  <p><span class="ok" id="state">확인 중…</span> <span class="dim" id="uptime"></span></p>
  <h2>동료에게 알려줄 주소</h2>
  <p class="big" id="addr">—</p>
  <div class="dim">앱의 <b>중계 서버로 만나기</b> 칸에 이 주소를 적습니다.
    암호를 걸어뒀다면 암호도 함께 알려주세요.</div>
</div>
<div class="card">
  <h2>기다리는 방</h2>
  <table><thead><tr><th>방 코드</th><th>방장</th><th>기다린 시간</th></tr></thead>
  <tbody id="rooms"><tr><td colspan="3" class="dim">없음</td></tr></tbody></table>
  <p class="dim">방을 연 사람이 <b>방 코드</b>를 상대에게 알려주면 그 사람이 들어옵니다.</p>
</div>
<div class="card">
  <h2>지금까지</h2>
  <p>중계 중인 배틀 <b id="active">0</b>판 · 누적 <b id="total">0</b>판 ·
     암호 <b id="secret">-</b></p>
</div>
<script>
async function tick(){
  try{
    const r = await fetch('api/status');
    const d = await r.json();
    document.getElementById('state').textContent = '작동 중';
    document.getElementById('uptime').textContent = '· ' + d.uptime + ' 동안';
    document.getElementById('addr').textContent = d.share;
    document.getElementById('active').textContent = d.active;
    document.getElementById('total').textContent = d.total;
    document.getElementById('secret').textContent = d.secret ? '있음' : '없음';
    const tb = document.getElementById('rooms');
    tb.innerHTML = d.rooms.length ? '' :
      '<tr><td colspan="3" class="dim">없음 — 아무도 방을 열지 않았습니다</td></tr>';
    for (const room of d.rooms){
      const tr = document.createElement('tr');
      tr.innerHTML = '<td><code>'+room.code+'</code></td><td></td><td class="dim"></td>';
      tr.children[1].textContent = room.host;
      tr.children[2].textContent = room.waiting + '초';
      tb.appendChild(tr);
    }
  }catch(e){
    document.getElementById('state').textContent = '연결 끊김';
  }
}
tick(); setInterval(tick, 2000);
</script>
</html>"""


class WebUI:
    """중계기 상태를 보여주는 아주 작은 HTTP 서버 (표준 라이브러리만)."""

    def __init__(self, relay):
        self.relay = relay

    async def handle(self, reader, writer):
        try:
            request = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), timeout=10)
        except (asyncio.TimeoutError, asyncio.IncompleteReadError, ValueError, OSError):
            writer.close()
            return
        lines = request.decode("latin-1").split("\r\n")
        parts = lines[0].split(" ")
        path = parts[1] if len(parts) > 1 else "/"
        host_header = ""
        for line in lines[1:]:
            if line.lower().startswith("host:"):
                host_header = line.split(":", 1)[1].strip()
                break

        if path.startswith("/api/status"):
            body = json.dumps(self.status(host_header), ensure_ascii=False).encode("utf-8")
            ctype = "application/json; charset=utf-8"
        else:
            body = PAGE.encode("utf-8")
            ctype = "text/html; charset=utf-8"

        writer.write(
            b"HTTP/1.1 200 OK\r\n"
            + f"Content-Type: {ctype}\r\n".encode()
            + f"Content-Length: {len(body)}\r\n".encode()
            + b"Cache-Control: no-store\r\nConnection: close\r\n\r\n"
            + body
        )
        try:
            await writer.drain()
        except (OSError, ConnectionError):
            pass
        writer.close()

    def status(self, host_header):
        now = time.monotonic()
        # 보는 사람이 실제로 이 기계에 닿은 주소를 그대로 알려준다 —
        # 공인 주소든 사내 주소든 그게 상대에게 알려줄 주소다.
        hostname = (host_header.rsplit(":", 1)[0] if host_header else "") or "이 기계의 주소"
        if hostname.startswith("[") and hostname.endswith("]"):
            hostname = hostname[1:-1]
        seconds = int(now - self.relay.started)
        return {
            "share": f"{hostname}:{self.relay.port}",
            "secret": bool(self.relay.secret),
            "active": self.relay.active,
            "total": self.relay.total,
            "uptime": f"{seconds // 3600}시간 {seconds % 3600 // 60}분",
            "rooms": [
                {"code": r.code, "host": r.host_name, "waiting": int(now - r.created)}
                for r in sorted(self.relay.rooms.values(), key=lambda r: r.created)
            ],
        }


# --- 설명서 (pokebattle-relay help) ------------------------------------
#
# 설치한 사람이 몇 달 뒤에 "이게 뭐였지" 하고 물어볼 곳이 필요하다.
# README 를 찾아보게 하지 않고, **실제 설정값을 채워서** 그 자리에서 보여준다.

SERVICE_NAME = "pokebattle-relay"


def local_ip():
    """밖으로 나갈 때 쓰는 내 주소. 실제로 패킷을 보내지는 않는다."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("192.0.2.1", 1))     # 문서용 주소 (RFC 5737)
        return s.getsockname()[0]
    except OSError:
        return None
    finally:
        s.close()


def service_state():
    """systemd 에 등록돼 있으면 지금 상태 (없으면 None)."""
    if not shutil.which("systemctl"):
        return None
    try:
        out = subprocess.run(["systemctl", "is-active", SERVICE_NAME],
                             capture_output=True, text=True, timeout=5)
        return out.stdout.strip() or None
    except (OSError, subprocess.SubprocessError):
        return None


def make_secret(length=12):
    """사람이 받아 적을 수 있는 암호를 만든다.

    헷갈리는 글자(0/O, 1/l/I)를 빼고, 네 글자마다 하이픈을 넣는다 —
    전화로 불러주거나 메신저로 옮겨 적기 쉬워야 한다.
    """
    import secrets
    alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
    raw = "".join(secrets.choice(alphabet) for _ in range(length))
    return "-".join(raw[i:i + 4] for i in range(0, length, 4))


def print_guide(port, web_port):
    ip = local_ip() or "<이 기계의 주소>"
    state = service_state()
    if state == "active":
        status = "작동 중"
    elif state is None:
        status = "systemd 에 등록되지 않음 (직접 실행 중이거나 꺼져 있음)"
    else:
        status = f"멈춤 ({state})"

    unit = f"/etc/systemd/system/{SERVICE_NAME}.service"
    print(f"""
PokeBattleBar 중계기
════════════════════════════════════════════════════════════
이 기계는 배틀을 하지 않습니다. 서로 다른 네트워크에 있는 두 사람을
이어주고 데이터를 전달만 합니다.

현재 상태
  {status}
  중계 포트     {port}/tcp
  상태 화면     {web_port}/tcp

배틀하는 사람에게 전달할 것
────────────────────────────────────────────────────────────
  중계 주소: {ip}:{port}
  중계 암호: 설치할 때 지정한 값
────────────────────────────────────────────────────────────
  · 같은 네트워크 안에서만 쓴다면 위 주소를 그대로 알려줍니다
  · 밖에서도 접속한다면 공인 IP 또는 도메인을 알려줍니다
  · 암호가 기억나지 않으면:  sudo grep -o 'secret [^ ]*' {unit}

확인
  브라우저로  http://{ip}:{web_port}/  → "작동 중" 이면 정상입니다.
  누가 방을 열고 기다리는지도 이 화면에 보입니다.

포트포워딩 (다른 네트워크에서 접속할 때만)
  공유기에서 TCP {port} → 이 기계로 전달합니다.
  {web_port}(상태 화면)은 전달하지 마세요 — 내부에서만 보는 편이 안전합니다.
  이 기계에 고정 IP 를 할당해 두세요. IP 가 바뀌면 접속이 끊깁니다.

관리
  sudo systemctl status {SERVICE_NAME}         상태
  journalctl -u {SERVICE_NAME} -f              로그
  sudo systemctl restart {SERVICE_NAME}        재시작
  sudo systemctl disable --now {SERVICE_NAME}  중지

설정 바꾸기 (포트·암호)
  sudo nano {unit}     ExecStart 줄을 고칩니다
  sudo systemctl daemon-reload && sudo systemctl restart {SERVICE_NAME}

이 설명서를 다시 보려면:  pokebattle-relay help
════════════════════════════════════════════════════════════
""".rstrip())


async def main():
    ap = argparse.ArgumentParser(description="PokeBattleBar 방 중계기")
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=51235)
    ap.add_argument("--secret", default=None,
                    help="접속 암호. 안 주면 자동으로 만들어 화면에 보여준다")
    ap.add_argument("--no-secret", action="store_true",
                    help="암호 없이 연다 (같은 집 안에서만 쓸 때)")
    ap.add_argument("--max-rooms", type=int, default=50)
    ap.add_argument("--idle", type=int, default=1800, help="빈 방을 치우기까지 (초)")
    ap.add_argument("--web-port", type=int, default=51236,
                    help="상태 화면 포트 (0 이면 웹 UI 없음)")
    ap.add_argument("--guide", action="store_true",
                    help="설정값이 채워진 설명서를 보여주고 끝낸다")
    args = ap.parse_args()

    if args.guide:
        print_guide(args.port, args.web_port)
        return

    logging.basicConfig(level=logging.INFO,
                        format="%(asctime)s %(message)s", datefmt="%H:%M:%S")

    # **암호를 안 주면 만들어 준다.**
    #
    # 중계기는 오가는 내용을 볼 수 있고, 주소만 알면 누구나 붙을 수 있다.
    # 그런데 --secret 을 깜빡하기 쉬워서 그대로 열린 채로 도는 일이 생긴다.
    # 기본을 "암호 있음" 으로 두고, 정말 열고 싶으면 --no-secret 을 적게 한다.
    secret = args.secret
    generated = False
    if args.no_secret:
        secret = None
    elif not secret:
        secret = make_secret()
        generated = True

    relay = Relay(secret=secret, max_rooms=args.max_rooms,
                  idle=args.idle, port=args.port)
    server = await asyncio.start_server(relay.handle, args.host, args.port)
    addrs = ", ".join(str(s.getsockname()) for s in server.sockets)
    log.info("중계기 시작 %s", addrs)

    ip = local_ip() or "<이 기계의 주소>"
    if generated:
        # 자동으로 만든 암호는 **눈에 띄게** 보여줘야 한다 —
        # 로그 사이에 묻히면 동료에게 알려줄 수가 없다.
        print(f"""
════════════════════════════════════════════════════════════
  암호를 지정하지 않아 자동으로 만들었습니다.

    중계 주소   {ip}:{args.port}
    중계 암호   {secret}

  이 두 줄을 배틀할 동료에게 알려주세요.
  (직접 정하려면 --secret 우리팀암호, 암호 없이 열려면 --no-secret)
════════════════════════════════════════════════════════════
""", flush=True)
    elif secret:
        log.info("암호 있음 — 앱에도 같은 값을 적어야 합니다")
    else:
        log.info("암호 없음 — 주소를 아는 누구나 붙을 수 있습니다 (--no-secret)")

    asyncio.ensure_future(relay.lobby_pusher())

    servers = [server]
    if args.web_port:
        web = await asyncio.start_server(WebUI(relay).handle, args.host, args.web_port)
        servers.append(web)
        log.info("상태 화면 http://<이 기계 주소>:%d/", args.web_port)

    async with server:
        await asyncio.gather(*(s.serve_forever() for s in servers))


if __name__ == "__main__":
    # `pokebattle-relay help` 처럼 그냥 쳐도 설명서가 나오게 한다 —
    # 몇 달 뒤에 옵션 이름(--guide)까지 기억할 이유가 없다.
    if len(sys.argv) > 1 and sys.argv[1] in ("help", "guide", "도움말"):
        sys.argv[1] = "--guide"
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
