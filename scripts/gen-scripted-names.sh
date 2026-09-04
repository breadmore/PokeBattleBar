#!/bin/bash
# handleScriptedMove 의 case 목록을 뽑아 Swift 상수로 만든다.
#
# **손으로 적으면 반드시 낡는다.** 실제로 기술을 새로 구현한 뒤 이 목록을
# 갱신하지 않아서, 감사(--usability)가 "중력·흑안개는 아무 일도 안 한다" 고
# 계속 보고했다 — 구현은 되어 있었다.
#
#   ./scripts/gen-scripted-names.sh
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="Sources/PokeBattleBar/Battle/ScriptedMoveNames.swift"

python3 - "$OUT" <<'PY'
import re, sys

src = open('Sources/PokeBattleBar/Battle/BattleEngine.swift', encoding='utf-8').read()
i = src.find('mutating func handleScriptedMove')
if i < 0:
    raise SystemExit('handleScriptedMove 를 찾을 수 없습니다')
body = src[i:]

names = set()
for m in re.finditer(r'^\s*case ((?:"[a-z0-9\-]+"(?:,\s*)?)+):', body, re.M):
    names.update(re.findall(r'"([a-z0-9\-]+)"', m.group(1)))
names = sorted(names)

rows = []
for k in range(0, len(names), 4):
    rows.append('        ' + ', '.join(f'"{n}"' for n in names[k:k+4]) + ',')

open(sys.argv[1], 'w', encoding='utf-8').write(f'''// 자동 생성 — scripts/gen-scripted-names.sh
//
// handleScriptedMove 의 case 목록입니다. 손으로 고치지 마세요.
// 기술을 새로 구현하면 이 스크립트를 다시 돌리세요 —
// 낡은 목록은 감사가 "구현 안 됐다" 고 잘못 보고하게 만듭니다.

extension BattleEngine {{
    /// **손으로 구현한 기술 이름 전체.**
    /// 감사(--usability)가 "이 기술이 실제로 무언가 하는가" 를 판단할 때 본다.
    static let scriptedMoveNames: Set<String> = [
{chr(10).join(rows)}
    ]
}}
''')
print(f'    기술 {len(names)}개 -> {sys.argv[1]}')
PY
