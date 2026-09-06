import json,sys,re
sys.stdout.reconfigure(encoding='utf-8')
def rect(s):
    m=re.findall(r'-?\d+', s or '')
    return [int(x) for x in m[:4]] if len(m)>=4 else None
def walk(n,out):
    a=n.get('attributes',{})
    ty=a.get('type','')
    t=(a.get('text') or '').strip()
    b=rect(a.get('bounds')); ob=rect(a.get('origBounds'))
    if ty=='Text' and t and b and ob:
        bw,bh=b[2]-b[0], b[3]-b[1]
        ow,oh=ob[2]-ob[0], ob[3]-ob[1]
        # 布局矩形有尺寸，但可见矩形被裁掉 >2px
        if ow>0 and oh>0 and (ow-bw>2 or oh-bh>2):
            out.append((t, f'vis {bw}x{bh}', f'lay {ow}x{oh}', a.get('origBounds')))
    for c in n.get('children',[]) or []: walk(c,out)
for p in sys.argv[1:]:
    d=json.load(open(p,encoding='utf-8'))
    out=[]; walk(d,out)
    print(f'== {p} -> 被裁剪 Text: {len(out)}')
    for t,v,l,ob in out[:25]:
        print('   ', repr(t[:34]), v, l, ob)
