import json,sys,re,itertools
sys.stdout.reconfigure(encoding='utf-8')
def rect(s):
    m=re.findall(r'-?\d+', s or '')
    return [int(x) for x in m[:4]] if len(m)>=4 else None
def scan(p):
    d=json.load(open(p,encoding='utf-8'))
    # 屏宽取自根节点，别写死 1320：折叠/2in1/平板各不相同
    root=rect(d.get('attributes',{}).get('bounds')) or [0,0,1320,0]
    W=root[2]
    over=[]; clip=[]; boxes=[]; head=[]
    def walk(n, scrollable):
        a=n.get('attributes',{}); ty=a.get('type',''); t=(a.get('text') or '').strip()
        # Scroll/List/Grid/Swiper 内允许超出：内容本来就靠滚动到达
        sc = scrollable or ty in ('Scroll','List','Grid','Swiper','WaterFlow')
        b=rect(a.get('bounds')); ob=rect(a.get('origBounds'))
        if t and b and ob:
            if len(head)<5: head.append(t)
            if not sc and (ob[2] > W or ob[0] < 0):
                over.append((t, a.get('origBounds'), ty))
            bw,bh=b[2]-b[0],b[3]-b[1]; ow,oh=ob[2]-ob[0],ob[3]-ob[1]
            if ow>0 and oh>0 and (ow-bw>2 or oh-bh>2):
                clip.append((t, f'{bw}x{bh}', f'{ow}x{oh}', sc))
            # 指南要求「组件不得叠加」：只比 Text 叶子，容器天然互相包含
            if ty=='Text': boxes.append((t,b))
        for c in n.get('children',[]) or []: walk(c, sc)
    walk(d, False)
    lap=[]
    for (t1,a),(t2,b) in itertools.combinations(boxes,2):
        ox=min(a[2],b[2])-max(a[0],b[0]); oy=min(a[3],b[3])-max(a[1],b[1])
        if ox>2 and oy>2: lap.append((t1,t2,ox,oy))
    return over, clip, lap, head, W
for p in sys.argv[1:]:
    over, clip, lap, head, W = scan(p)
    hard=[c for c in clip if not c[3]]
    tag=p.replace('\\','/').split('/')[-1]
    print(f'== {tag} (屏宽 {W}): 非滚动区溢出屏幕 {len(over)}; 非滚动区被裁剪 {len(hard)}; 滚动区裁剪 {len(clip)-len(hard)}; 文本重叠 {len(lap)}')
    print(f'   TITLE {head}')
    for t,ob,ty in over[:8]:  print('   OVERFLOW', repr(t[:28]), ob, ty)
    for c in hard[:8]:        print('   CLIPPED ', repr(c[0][:28]), c[1], '<-', c[2])
    for t1,t2,ox,oy in lap[:8]: print('   OVERLAP ', repr(t1[:20]), 'x', repr(t2[:20]), f'{ox}x{oy}px')
