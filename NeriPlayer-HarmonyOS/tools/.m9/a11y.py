# dev-only: M9.3 touch-target + accessibility-label audit over a uitest dumpLayout JSON.
# density = 3.5 px/vp here (DisplayManagerService VirtualWidth 377 vp / 1320 px).
# Sizes come from origBounds, not bounds: bounds is the *clipped* visible rect, so a
# control at the edge of a scroll viewport measures far smaller than it is laid out
# (the 扫描 button reads 9.7vp by bounds and 32.0vp by origBounds).
# Only the app's own window is audited; system windows share the dump.
import json, re, sys
sys.stdout.reconfigure(encoding='utf-8')
DENSITY = 3.5
BOUNDS = re.compile(r'\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]')
INTERACTIVE = {'Button', 'Toggle', 'Checkbox', 'Radio', 'Slider', 'Search', 'TextInput', 'Select'}

def texts(n):
    a = n.get('attributes', {})
    out = [a.get('text', ''), a.get('description', ''), a.get('hint', '')]
    for c in n.get('children', []):
        out += texts(c)
    return [t for t in out if t]

def collect(n, rows, wins):
    a = n.get('attributes', {})
    m = BOUNDS.match(a.get('origBounds') or a.get('bounds', ''))
    if m:
        x1, y1, x2, y2 = (int(v) for v in m.groups())
        w, h = (x2 - x1) / DENSITY, (y2 - y1) / DENSITY
        hit = a.get('clickable') == 'true' or a.get('longClickable') == 'true'
        if (hit or a.get('type') in INTERACTIVE) and a.get('visible') == 'true' and w > 0 and h > 0:
            win = a.get('hostWindowId', '?')
            wins[win] = wins.get(win, 0) + 1
            rows.append((win, round(min(w, h), 1), round(w, 1), round(h, 1),
                         a.get('type', ''), ' / '.join(texts(n))[:34]))
    for c in n.get('children', []):
        collect(c, rows, wins)

appwin = sys.argv[1]
for path in sys.argv[2:]:
    rows, wins = [], {}
    collect(json.load(open(path, encoding='utf-8')), rows, wins)
    mine = sorted(r for r in rows if r[0] == appwin)
    print(f'== {path}  窗口分布 {wins}  应用窗口({appwin}) 可交互 {len(mine)} 个（vp, origBounds）')
    for _, minv, w, h, ty, label in mine:
        flag = 'XX<40' if minv < 40 else ('!<48' if minv < 48 else '  ok')
        print(f'  {flag} {w}x{h} {ty:12s} {label or "(无可读文本)"}')
    print(f'  -> <40vp: {sum(1 for r in mine if r[1] < 40)}; <48vp: {sum(1 for r in mine if r[1] < 48)};'
          f' 无可读文本: {sum(1 for r in mine if not r[5])}')
