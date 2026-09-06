import json,sys
sys.stdout.reconfigure(encoding='utf-8')
d=json.load(open(sys.argv[1],encoding='utf-8'))
def walk(n):
    a=n.get('attributes',{})
    t=a.get('text','');ty=a.get('type','')
    if t: print(ty,'|',t[:40],'|',a.get('bounds'))
    for c in n.get('children',[]): walk(c)
walk(d)
