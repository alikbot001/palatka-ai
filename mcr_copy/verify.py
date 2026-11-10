#!/usr/bin/env python3
"""Reproduce checks for the independent MCR candidate (not the legacy suite)."""
from pathlib import Path
from datetime import datetime, timezone
import json
import shlex
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
TESTS=('engine','app','external','ui','ui_geometry','market','market_refresh','market_host',
       'sha256','updater','update_file','update_host','autorefresh','resale','purchases',
       'workspace','workspace_market','purchase_runtime','host_read','popularity',
       'vertical_list','workspace_ui','purchases_ui','popup_scope')

def main():
    commands=[['luajit',f'mcr_copy/tests/test_{name}.lua']for name in TESTS]
    commands += [[sys.executable,'-m','unittest','discover','-s','mcr_copy/tests','-p','test_*.py'],
                 [sys.executable,'build_mcr_local.py']]
    results=[]
    for command in commands:
        run=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,errors='replace')
        results.append({'command':shlex.join(command),'exit_code':run.returncode,
                        'stdout':run.stdout,'stderr':run.stderr})
        print(f'{run.returncode}: {shlex.join(command)}')
        if run.returncode:print(run.stdout+run.stderr)
    manifest=json.loads((ROOT/'outputs/palatka_mcr_local.json').read_text())
    report={'scope':'mcr_local_targeted','checked_at':datetime.now(timezone.utc).isoformat(),
            'version':manifest['version'],'artifact_sha256':manifest['sha256'],
            'lua_suites':len(TESTS),'native_acceptance':False,'checks':results}
    (ROOT/'outputs/palatka_mcr_checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    return 0 if all(r['exit_code']==0 for r in results)else 1

if __name__=='__main__':sys.exit(main())
