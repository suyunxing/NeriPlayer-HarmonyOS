import json,sys
sys.stdout.reconfigure(encoding='utf-8')
d=json.load(open(sys.argv[1],encoding='utf-8')); ts=[]
def walk(n):
    a=n.get('attributes',{}); t=(a.get('text') or '').strip()
    if t and a.get('type')=='Text' and len(ts)<5: ts.append(t[:18])
    for c in n.get('children',[]) or []: walk(c)
walk(d); print('TITLE:', ts)
