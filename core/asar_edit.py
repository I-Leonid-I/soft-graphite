import json,struct,hashlib,shutil,os
from pathlib import Path
def edit(archive,changes):
 p=Path(archive);tmp=p.with_suffix('.asar.new')
 with p.open('rb') as f:
  h=struct.unpack('<4I',f.read(16));j=json.loads(f.read(h[3]));base=8+h[1];f.seek(0,2);offset=f.tell()-base;payload=[]
  for name,transform in changes.items():
   e=j
   for segment in name.split('/'):e=e['files'][segment]
   f.seek(base+int(e['offset']));old=f.read(e['size']);new=transform(old)
   e['offset']=str(offset);e['size']=len(new);offset+=len(new);payload.append(new)
   if 'integrity' in e:
    v=e['integrity'];bs=v['blockSize'];v['hash']=hashlib.sha256(new).hexdigest();v['blocks']=[hashlib.sha256(new[i:i+bs]).hexdigest() for i in range(0,len(new),bs)]
  js=json.dumps(j,separators=(',',':'),ensure_ascii=False).encode();aligned=(len(js)+3)//4*4
  with tmp.open('wb') as out:
   out.write(struct.pack('<4I',4,8+aligned,4+aligned,len(js))+js+b'\0'*(aligned-len(js)));f.seek(base);shutil.copyfileobj(f,out)
   for v in payload:out.write(v)
 os.chmod(tmp,p.stat().st_mode);tmp.replace(p)
