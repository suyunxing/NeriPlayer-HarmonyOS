import json,sys,re
sys.stdout.reconfigure(encoding='utf-8')
def rect(s):
    m=re.findall(r'-?\d+', s or '')
    return [int(x) for x in m[:4]] if len(m)>=4 else None
d=json.load(open(sys.argv[1],encoding='utf-8'))
root=rect(d['attributes']['bounds']); H=root[3]; W=root[2]
PX=float(sys.argv[2]) if len(sys.argv)>2 else 3.375
print(f'屏幕 {W}x{H}px, px/vp={PX}')
out=[]
def walk(n,depth):
    a=n.get('attributes',{}); b=rect(a.get('bounds')); ob=rect(a.get('origBounds'))
    if b and b[3]>H-420:
        out.append((depth,a.get('type'),(a.get('text') or '')[:14],b,ob))
    for c in n.get('children',[]) or []: walk(c,depth+1)
walk(d,0)
for depth,ty,t,b,ob in out:
    h=(b[3]-b[1])/PX; w=(b[2]-b[0])/PX
    print(f'{"  "*depth}{ty:12s} {t:14s} b={b} ({w:.1f}x{h:.1f}vp) 底距屏底={(H-b[3])/PX:.1f}vp')
