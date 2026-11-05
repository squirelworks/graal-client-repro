# PKWARE DCL "implode" decompressor (after zlib contrib/blast.c) and an
# InstallShield 3 _SETUP.1 member reader.  usage: blast.py ARCHIVE OFFSET CSIZE OUT
import sys
litlen=[11,124,8,7,28,7,188,13,76,4,10,8,12,10,12,10,8,23,8,9,7,6,7,8,7,6,55,8,23,24,12,11,7,9,11,12,6,7,22,5,7,24,6,11,9,6,7,22,7,11,38,7,9,8,25,11,8,11,9,12,8,12,5,38,5,38,5,11,7,5,6,21,6,10,53,8,7,24,10,27,44,253,253,253,252,252,252,13,12,45,12,45,12,61,12,45,44,173]
lenlen=[2,35,36,53,38,23]
distlen=[2,20,53,230,247,151,248]
base=[3,2,4,5,6,7,8,9,10,12,16,24,40,72,136,264]
extra=[0,0,0,0,0,0,0,0,1,2,3,4,5,6,7,8]
def build(rep):
    lens=[]
    for b in rep:
        lens+= [b&15]*((b>>4)+1)
    count=[0]*14
    for l in lens: count[l]+=1
    offs=[0]*14
    for i in range(1,13): offs[i+1]=offs[i]+count[i]
    sym=[0]*len(lens)
    for s,l in enumerate(lens):
        if l: sym[offs[l]]=s; offs[l]+=1
    return count,sym
LIT=build(litlen); LEN=build(lenlen); DIST=build(distlen)
class Bits:
    def __init__(s,d,p): s.d=d; s.p=p; s.buf=0; s.cnt=0
    def bits(s,n):
        v=s.buf
        while s.cnt<n:
            v|=s.d[s.p]<<s.cnt; s.p+=1; s.cnt+=8
        s.buf=v>>n; s.cnt-=n
        return v&((1<<n)-1)
    def decode(s,h):
        count,sym=h; code=first=index=0
        for l in range(1,14):
            code|=s.bits(1)^1
            c=count[l]
            if code<first+c: return sym[index+code-first]
            index+=c; first+=c; first<<=1; code<<=1
        raise ValueError('bad code')
def blast(d,p=0):
    b=Bits(d,p); lit=b.bits(8); dic=b.bits(8)
    assert lit in (0,1) and dic in (4,5,6), (lit,dic)
    out=bytearray()
    while True:
        if b.bits(1):
            sy=b.decode(LEN); ln=base[sy]+b.bits(extra[sy])
            if ln==519: break
            sy=2 if ln==2 else dic
            dist=(b.decode(DIST)<<sy)+b.bits(sy)+1
            for i in range(ln): out.append(out[-dist])
        else:
            out.append(b.decode(LIT) if lit else b.bits(8))
    return bytes(out)
if __name__=='__main__':
    a=open(sys.argv[1],'rb').read(); off=int(sys.argv[2],0); cs=int(sys.argv[3],0)
    o=blast(a[off:off+cs]); open(sys.argv[4],'wb').write(o); print(len(o))
