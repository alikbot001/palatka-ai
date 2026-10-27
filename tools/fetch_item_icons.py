#!/usr/bin/env python3
"""Prepare offline PNGs from the same public icon service used by Market Helper.
Pillow is needed only for this optional asset refresh, never on the phone.
"""
import argparse,collections,concurrent.futures,hashlib,io,json,re,time,urllib.request,urllib.parse
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--workers',type=int,default=4);p.add_argument('--limit',type=int);args=p.parse_args()
cat=json.loads((ROOT/'data/arz_items.json').read_bytes().decode('cp1251'))
canonical=lambda name:re.sub(r'\{[0-9a-fA-F]+\}','',name).strip().casefold()
counts=collections.Counter(canonical(name) for name in cat.values())
rows=[(int(i),n) for i,n in cat.items() if counts[canonical(n)]==1 and n.strip() and n!='-' and 'DELETED' not in n]
rows.sort(key=lambda r:(not any(k in r[1].lower() for k in ('ларец','рулетк','case','box','тайник')),r[0]))
if args.limit:rows=rows[:args.limit]
out=ROOT/'icons/items';out.mkdir(parents=True,exist_ok=True)
manifest_path=ROOT/'data/item_icons.json'
manifest=json.loads(manifest_path.read_text()) if manifest_path.exists() else {'source':'https://va-ta.com/api/items/icon/by-name/img','items':{},'missing':{}}
manifest.setdefault('named',{})
if not args.limit:rows += [(key,meta['name']) for key,meta in manifest['named'].items()]
name_by_key={str(key):name for key,name in rows}

def fetch(row):
 item_id,name=row;key=str(item_id);dest=out/(key+'.png')
 bucket='named' if key.startswith('name_') else 'items'
 prior=manifest[bucket].get(key)
 if prior and prior['name']==name and dest.exists() and hashlib.sha256(dest.read_bytes()).hexdigest()==prior['sha256']:return key,prior,None
 url=manifest['source']+'?name='+urllib.parse.quote(name)
 try:
  with urllib.request.urlopen(url,timeout=12) as f:
   if f.headers.get_content_type() not in ('image/webp','image/png'):return key,None,'not_image'
   raw=f.read(2_000_001)
  if len(raw)>2_000_000:return key,None,'oversized'
  with Image.open(io.BytesIO(raw)) as im:
   im.load()
   if im.width>2048 or im.height>2048:return key,None,'oversized_dimensions'
   rgba=im.convert('RGBA');rgba.thumbnail((96,96),Image.Resampling.LANCZOS)
   # Keep original proportions and transparency; no substitute artwork.
   canvas=Image.new('RGBA',(96,96),(0,0,0,0));canvas.paste(rgba,((96-rgba.width)//2,(96-rgba.height)//2))
   canvas.save(dest,'PNG',optimize=True)
  png=dest.read_bytes()
  return key,{'name':name,'url':url,'sha256':hashlib.sha256(png).hexdigest(),'bytes':len(png)},None
 except urllib.error.HTTPError as e:return key,None,'HTTP '+str(e.code)
 except Exception as e:return key,None,type(e).__name__

def save():
 manifest['numeric_count']=len(manifest['items']);manifest['named_count']=len(manifest['named']);manifest['count']=manifest['numeric_count']+manifest['named_count']
 manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
start=time.monotonic();done=0;good=0;bad=collections.Counter()
with concurrent.futures.ThreadPoolExecutor(max_workers=min(6,max(1,args.workers))) as pool:
 for key,meta,error in pool.map(fetch,rows):
  done+=1
  if meta:manifest['named' if key.startswith('name_') else 'items'][key]=meta;manifest['missing'].pop(key,None);good+=1
  else:manifest['missing'][key]={'name':name_by_key[key],'error':error};bad[error]+=1
  if done%50==0 or done==len(rows):
   save();print(f'{done}/{len(rows)} ready={good} missing={sum(bad.values())} elapsed={time.monotonic()-start:.1f}s errors={dict(bad)}',flush=True)
save()
