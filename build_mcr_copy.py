#!/usr/bin/env python3
"""Build a separate full MCR client preview plus local arbitrage. No network."""
from pathlib import Path
import hashlib
import json
import re
import subprocess

ROOT=Path(__file__).resolve().parent
BASE_HASH='e9bde4c5299e53118af664012d4aa1e9644373b489bdb0a3ff603bf74c4ab8d5'


def assemble(raw):
    if hashlib.sha256(raw).hexdigest()!=BASE_HASH:
        raise ValueError('MCR reference differs from verified 1.15.5 snapshot')
    source=raw.decode('cp1251')
    patches=[]
    def patch(before,after):
        nonlocal source
        if source.count(before)!=1:
            raise ValueError('Integration anchor is not unique: '+before[:100])
        source=source.replace(before,after,1)
        patches.append((before.encode('cp1251'),after.encode('cp1251')))
    modules=[]
    for variable,name in [('E','engine'),('factory','app'),('resale','resale'),('purchases','purchases'),
        ('popularity','popularity'),('workspace','workspace'),('navigation','navigation'),('V','vertical_list'),('ui','ui'),
        ('workspace_ui','workspace_ui'),('purchases_ui','purchases_ui'),('external','external')]:
        content=(ROOT/'mcr_copy/src'/f'{name}.lua').read_text()
        modules.append(f'local {variable}=(function()\n{content}\nend)()\n')
    prefix="-- Palatka full MCR client preview; original attribution retained.\nPalatkaMCR=(function()\n"+''.join(modules)+"local A=factory(E);A.external=external;A.vertical_list=V;workspace(A,E,resale(E),purchases(E),popularity(E));navigation(A);ui(A);workspace_ui(A);purchases_ui(A);return A\nend)()\n"
    patch(source[:70],prefix+source[:70])
    ready='while not isSampAvailable()do wait(-244297-(-244297))end'
    patch(ready,ready+' PalatkaMCR.start();')
    patch('function lIlIlIIl(h)', 'function lIlIlIIl(h)PalatkaMCR.capture(h);')
    patch('function llIIl_l_()', 'function llIIl_l_()if O3==F3.arbitrage then PalatkaMCR.draw_center();return end;')
    patch('function llII_III()', 'function llII_III()if O3==F3.arbitrage then PalatkaMCR.draw_right();return end;')
    # Keep the original frame, size, font and decoration paths. The additional
    # independent section can be opened by /parb without altering MCR auth state.
    start=source.index('mainFrame=B.OnFrame(')
    gate=source.index('if L6.status then',start)
    end=gate+len('if L6.status then')
    anchor=source[max(start,gate-140):end]
    patch(anchor,anchor[:-len('if L6.status then')]+'if L6.status or O3==F3.arbitrage then')
    start=source.index('function llIIl_I_()')
    end=source.index('function llIIl_ll()',start)
    section=source[start:end]
    m=re.search(r'B\.ScrollMouse\(r\[[^\]]+\],true\)B\.EndChild\(\)end\s*$',section)
    if not m:raise ValueError('Missing original sidebar footer')
    before=m[0]
    nav="B.Spacing();if B.Button(x.SCALE_BALANCED..'##PalatkaArbitrage',B.ImVec2(-1,constHeightButtonSidebar))and llIllll_()then F3.arbitrage=10;O3=10 end;B.CenterText(u8('Арбитраж'));"
    # The bundled FontAwesome bank may not expose this icon on every install.
    nav=nav.replace('x.SCALE_BALANCED',"(x.SCALE_BALANCED or x.ARROW_RIGHT_ARROW_LEFT or '+')")
    patch(before,nav+before)
    callback='function lI_II_Il(h,B,a)'
    patch(callback,callback+'local pa_parse=a;a=function(v)local result=pa_parse(v);PalatkaMCR.capture_external(result);return result end;')
    install=(ROOT/'mcr_copy/src/host.lua').read_text()
    suffix='\n-- Palatka local extension host; MCR license state remains untouched.\n'+install+'\n'
    tail=source[-100:]
    patch(tail,tail+suffix)
    return source.encode('cp1251'),patches


def main():
    raw=(ROOT/'mcr_copy/vendor/mcrm-1.15.5.lua').read_bytes()
    output,patches=assemble(raw)
    target=ROOT/'outputs/palatka_mcr_preview.lua'
    target.parent.mkdir(exist_ok=True)
    target.write_bytes(output)
    subprocess.run(['luajit','-b',str(target),'/dev/null'],check=True)
    manifest={'version':'3.0.0-mcr-preview.1','base_version':'MCR Mobile 1.15.5',
        'base_sha256':BASE_HASH,'sha256':hashlib.sha256(output).hexdigest(),
        'bytes':len(output),'integration_patches':len(patches),'native_acceptance':False,
        'base_authentication':'preserved','local_arbitrage_requires_mcr_key':False}
    (ROOT/'outputs/palatka_mcr_preview.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(json.dumps(manifest,indent=2))


if __name__=='__main__':main()
