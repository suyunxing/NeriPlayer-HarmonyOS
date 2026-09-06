import json, collections, os, sys
sys.stdout.reconfigure(encoding='utf-8')
d = json.load(open(sys.argv[1], encoding='utf-8'))
c = collections.Counter()
hits = []
watch = ('Router.ets', 'RouteStack.ets', 'Index.ets')
for f in d:
    p = f.get('filePath', '')
    for m in f.get('messages', []):
        c[m.get('severity')] += 1
        if os.path.basename(p) in watch:
            hits.append((os.path.basename(p), m.get('severity'), m.get('line'), (m.get('message') or '')[:90]))
print('SEV', dict(c))
print('--- 本次改动文件相关 ---')
for h in hits:
    print(h)
if not hits:
    print('(无)')
