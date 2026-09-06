import json,sys,re
sys.stdout.reconfigure(encoding='utf-8')
def rect(s):
    m=re.findall(r'-?\d+', s or '')
    return [int(x) for x in m[:4]] if len(m)>=4 else None
pat=sys.argv[2] if len(sys.argv)>2 else ''
d=json.load(open(sys.argv[1],encoding='utf-8'))
out=[]
def walk(n):
    a=n.get('attributes',{}); t=(a.get('text') or '').strip()
    b=rect(a.get('bounds'))
    if t and b and (not pat or pat in t):
        out.append((t,b,a.get('type','')))
    for c in n.get('children',[]) or []: walk(c)
walk(d)
for t,b,ty in out:
    print(f'{t[:24]!r:28} {b} cx={(b[0]+b[2])//2} cy={(b[1]+b[3])//2} {ty}')
