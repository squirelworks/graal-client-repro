# InstallShield 3 archive (_SETUP.1) extractor, for installs that ship the
# client only inside the installer (1.21). Each member is PKWARE DCL
# imploded; blast.py undoes that. Files land in OUTDIR/<group>/.
# extract an InstallShield 3 _SETUP.1 archive: is3x.py ARCHIVE OUTDIR
import sys,os,struct
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from blast import blast
a=open(sys.argv[1],'rb').read(); out=sys.argv[2]
nfiles=struct.unpack_from('<H',a,0x0c)[0]
doff=struct.unpack_from('<I',a,0x29)[0]; ndirs=struct.unpack_from('<H',a,0x31)[0]
foff=struct.unpack_from('<I',a,0x33)[0]
dirs=[];p=doff
for i in range(ndirs):
    cnt,el,nl=struct.unpack_from('<HHH',a,p); dirs.append(a[p+6:p+6+nl].decode('latin1')); p+=el
p=foff
for i in range(nfiles):
    di,size,cs,off=struct.unpack_from('<HIII',a,p+1); el=struct.unpack_from('<H',a,p+23)[0]; nl=a[p+29]
    name=a[p+30:p+30+nl].decode('latin1')
    path=os.path.join(out,dirs[di].replace('\\','/'),name)
    os.makedirs(os.path.dirname(path),exist_ok=True)
    data=blast(a[off:off+cs]) if cs else b''
    assert len(data)==size,(name,len(data),size)
    open(path,'wb').write(data); p+=el
print(nfiles,'files',dirs)
