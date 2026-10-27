#!/usr/bin/env python3
"""Run every active Lua regression with bounded execution; report actual exit codes."""
from pathlib import Path
import json
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
runtime = shutil.which('luajit')
if not runtime:
    sys.exit('LuaJIT is required for the full FFI/startup suite; no tests were run.')
checks = [('build', [sys.executable, 'build.py'])]
checks.extend((p.name, [runtime, str(p.relative_to(ROOT))]) for p in sorted((ROOT/'tests').glob('test_*.lua')))
checks.append(('verify_standalone.lua', [runtime, 'tests/verify_standalone.lua']))
rows = []
for name, cmd in checks:
    try:
        result = subprocess.run(cmd, cwd=ROOT, capture_output=True, timeout=45)
        status = result.returncode
        output = (result.stdout + result.stderr).decode('utf-8', errors='replace')
    except subprocess.TimeoutExpired as exc:
        status, output = 124, f'Timeout: {exc}'
    rows.append({'check': name, 'exit_code': status, 'output': output})
    print(f'{"PASS" if status == 0 else "FAIL"} {name} (exit {status})', flush=True)
    if status:
        print(output, flush=True)
report = ROOT/'docs'/'test-results.json'
report.write_text(json.dumps(rows, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
print(f'{sum(r["exit_code"] == 0 for r in rows)}/{len(rows)} checks passed')
sys.exit(0 if all(r['exit_code'] == 0 for r in rows) else 1)
