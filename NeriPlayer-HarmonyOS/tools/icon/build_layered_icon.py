#!/usr/bin/env python3
# NeriPlayer HarmonyOS - 分层图标生成器
#
# 从 entry/src/main/resources/base/media/ic_neriplayer.svg 生成 HarmonyOS
# 分层图标（layered-image）所需的两层位图资源：
#
#   * 背景层：1024x1024 纯色 #1E293A，truecolor（无 alpha 通道），不含任何
#     透明像素 —— 官方要求「背景图需为纯色，不能含有透明像素」。
#   * 前景层：1024x1024 RGBA，仅保留 SVG 中 #ffffff / #919191 的图形，底透明。
#   * 启动页图标：1024x1024 RGBA 的完整合成图（背景 + 前景），供
#     startWindowIcon 使用（启动页图标只接受单层资源）。
#
# 拆分依据（实测）：ic_neriplayer.svg 的 24 个 path 只用 M/L/C/Z，无 transform、
# 渐变、透明度或 fill-rule；#1E293A 的 9 个 path 与 #ffffff/#919191 的 15 个
# path 在 256x256 网格上覆盖率为 80.36% / 19.64%，零重叠零空隙，合计 100%。
# 即这张图本身就是「实色背板 + 纯图形」结构，按颜色分组即为逐像素无损拆分，
# 不需要重绘素材。
#
# 只依赖 Python 标准库（zlib + struct）：本机无 PIL / cairosvg / ImageMagick /
# Inkscape，所以栅格化（扫描线 + 非零环绕 + 垂直超采样抗锯齿）与 PNG 编码都在
# 这里自己实现，保证任何人在干净环境下都能重现同样的资源。
#
# 用法（在 NeriPlayer-HarmonyOS 目录下）：
#     python tools/icon/build_layered_icon.py
# 加 --check 只做自检不写文件。

import argparse
import os
import re
import struct
import sys
import zlib

SIZE = 1024
SUPERSAMPLE = 4           # 每像素垂直采样行数，用于抗锯齿
BG_COLOR = (0x1E, 0x29, 0x3A)
BG_HEX = '#1e293a'

SVG_REL = os.path.join('entry', 'src', 'main', 'resources', 'base', 'media', 'ic_neriplayer.svg')
MEDIA_REL = os.path.join('entry', 'src', 'main', 'resources', 'base', 'media')
APPSCOPE_MEDIA_REL = os.path.join('AppScope', 'resources', 'base', 'media')


# ---------------------------------------------------------------- SVG 解析

def parse_paths(svg_text):
    """返回 [(fill, d), ...]，按文档顺序（即绘制顺序）。"""
    out = []
    for elem in re.findall(r'<path\b[^>]*>', svg_text, re.S):
        d = re.search(r'd="([^"]*)"', elem, re.S)
        fill = re.search(r'fill="([^"]*)"', elem, re.S)
        if d and fill:
            out.append((fill.group(1).lower(), d.group(1)))
    return out


def flatten(d, steps=24):
    """把 path 展开成折线列表。只支持 M/L/C/Z（大小写均按绝对坐标处理，
    该 SVG 全部使用绝对命令）。"""
    tokens = re.findall(r'[MLCZmlcz]|-?\d*\.?\d+', d)
    subpaths = []
    poly = []
    cur = start = (0.0, 0.0)
    i = 0
    while i < len(tokens):
        cmd = tokens[i]
        if cmd in 'Mm':
            if len(poly) > 1:
                subpaths.append(poly)
            cur = start = (float(tokens[i + 1]), float(tokens[i + 2]))
            poly = [cur]
            i += 3
        elif cmd in 'Ll':
            cur = (float(tokens[i + 1]), float(tokens[i + 2]))
            poly.append(cur)
            i += 3
        elif cmd in 'Cc':
            x1, y1, x2, y2, x3, y3 = (float(v) for v in tokens[i + 1:i + 7])
            x0, y0 = cur
            for k in range(1, steps + 1):
                t = k / steps
                u = 1.0 - t
                poly.append((
                    u * u * u * x0 + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t * x3,
                    u * u * u * y0 + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t * y3,
                ))
            cur = (x3, y3)
            i += 7
        elif cmd in 'Zz':
            if poly and poly[0] != poly[-1]:
                poly.append(poly[0])
            if len(poly) > 1:
                subpaths.append(poly)
            cur = start
            poly = [cur]
            i += 1
        else:
            # 省略命令字母的坐标对，按上一条命令的隐式重复处理（此 SVG 未出现）
            cur = (float(tokens[i]), float(tokens[i + 1]))
            poly.append(cur)
            i += 2
    if len(poly) > 1:
        subpaths.append(poly)
    return subpaths


# ---------------------------------------------------------------- 栅格化

def coverage(dlist, size=SIZE, ss=SUPERSAMPLE):
    """把若干 path 按非零环绕规则填充，返回每像素覆盖度（0.0~1.0）的
    float 列表，长度 size*size。

    垂直方向做 ss 倍超采样，水平方向按区间端点的小数部分精确累加覆盖，
    效果接近解析抗锯齿。"""
    scale = 1024.0 / size
    edges = []
    for d in dlist:
        for poly in flatten(d):
            for (x0, y0), (x1, y1) in zip(poly, poly[1:]):
                if y0 != y1:
                    edges.append((x0 / scale, y0 / scale, x1 / scale, y1 / scale))

    # 按扫描行分桶，避免每行遍历全部边
    buckets = [[] for _ in range(size)]
    for e in edges:
        lo, hi = (e[1], e[3]) if e[1] < e[3] else (e[3], e[1])
        r0 = max(0, int(lo))
        r1 = min(size - 1, int(hi))
        for r in range(r0, r1 + 1):
            buckets[r].append(e)

    cov = [0.0] * (size * size)
    weight = 1.0 / ss
    for row in range(size):
        bucket = buckets[row]
        if not bucket:
            continue
        base = row * size
        for s in range(ss):
            y = row + (s + 0.5) / ss
            xs = []
            for (x0, y0, x1, y1) in bucket:
                if (y0 <= y < y1) or (y1 <= y < y0):
                    xs.append((x0 + (x1 - x0) * (y - y0) / (y1 - y0), 1 if y1 > y0 else -1))
            if not xs:
                continue
            xs.sort()
            wind = 0
            for k in range(len(xs) - 1):
                wind += xs[k][1]
                if wind == 0:
                    continue
                xa, xb = xs[k][0], xs[k + 1][0]
                if xb <= 0.0 or xa >= size or xb <= xa:
                    continue
                xa = max(xa, 0.0)
                xb = min(xb, float(size))
                ca, cb = int(xa), int(xb)
                if ca == cb:
                    cov[base + ca] += (xb - xa) * weight
                    continue
                cov[base + ca] += (ca + 1 - xa) * weight
                for c in range(ca + 1, cb):
                    cov[base + c] += weight
                if cb < size:
                    cov[base + cb] += (xb - cb) * weight
    return cov


def hex_rgb(text):
    text = text.lstrip('#')
    return (int(text[0:2], 16), int(text[2:4], 16), int(text[4:6], 16))


def compose(layers, size=SIZE):
    """把 [(rgb, coverage), ...] 按顺序做 source-over 合成，返回 RGBA bytes。"""
    # 预乘 alpha 累加，最后反预乘
    pr = [0.0] * (size * size)
    pg = [0.0] * (size * size)
    pb = [0.0] * (size * size)
    pa = [0.0] * (size * size)
    for (r, g, b), cov in layers:
        for i, a in enumerate(cov):
            if a <= 0.0:
                continue
            if a > 1.0:
                a = 1.0
            inv = 1.0 - a
            pr[i] = r * a + pr[i] * inv
            pg[i] = g * a + pg[i] * inv
            pb[i] = b * a + pb[i] * inv
            pa[i] = a + pa[i] * inv
    out = bytearray(size * size * 4)
    for i in range(size * size):
        a = pa[i]
        j = i * 4
        if a <= 0.0:
            continue
        out[j] = min(255, int(pr[i] / a + 0.5))
        out[j + 1] = min(255, int(pg[i] / a + 0.5))
        out[j + 2] = min(255, int(pb[i] / a + 0.5))
        out[j + 3] = min(255, int(a * 255.0 + 0.5))
    return bytes(out)


# ---------------------------------------------------------------- PNG 编码

def write_png(path, size, data, color_type):
    """color_type 2 = truecolor RGB（每像素 3 字节），6 = RGBA（4 字节）。"""
    stride = 3 if color_type == 2 else 4
    raw = bytearray()
    for row in range(size):
        raw.append(0)  # filter type 0 (None)
        start = row * size * stride
        raw += data[start:start + size * stride]

    def chunk(tag, payload):
        return (struct.pack('>I', len(payload)) + tag + payload
                + struct.pack('>I', zlib.crc32(tag + payload) & 0xFFFFFFFF))

    ihdr = struct.pack('>IIBBBBB', size, size, 8, color_type, 0, 0, 0)
    png = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr)
           + chunk(b'IDAT', zlib.compress(bytes(raw), 9)) + chunk(b'IEND', b''))
    with open(path, 'wb') as fp:
        fp.write(png)
    return len(png)


# ---------------------------------------------------------------- 主流程

def main():
    parser = argparse.ArgumentParser(description='Generate HarmonyOS layered icon assets')
    parser.add_argument('--check', action='store_true', help='only verify the split, write nothing')
    parser.add_argument('--root', default='.', help='NeriPlayer-HarmonyOS directory')
    args = parser.parse_args()

    root = os.path.abspath(args.root)
    svg_path = os.path.join(root, SVG_REL)
    if not os.path.isfile(svg_path):
        print('ERROR: not found: %s' % svg_path, file=sys.stderr)
        return 1

    with open(svg_path, encoding='utf-8-sig') as fp:
        svg = fp.read()
    header = re.search(r'<svg[^>]*>', svg, re.S).group(0)
    if 'viewBox="0 0 1024 1024"' not in header:
        print('ERROR: unexpected viewBox, the 1024 canvas assumption no longer holds:\n  %s'
              % header, file=sys.stderr)
        return 1

    paths = parse_paths(svg)
    bg_paths = [d for fill, d in paths if fill == BG_HEX]
    fg_groups = []
    for fill, d in paths:
        if fill == BG_HEX:
            continue
        if fg_groups and fg_groups[-1][0] == fill:
            fg_groups[-1][1].append(d)
        else:
            fg_groups.append((fill, [d]))
    print('paths: %d total, %d background(%s), %d foreground in %d colour run(s): %s'
          % (len(paths), len(bg_paths), BG_HEX, len(paths) - len(bg_paths), len(fg_groups),
             ', '.join('%s x%d' % (f, len(g)) for f, g in fg_groups)))

    # 自检：在 256 网格上确认「背板 + 图形」互补，拆分才是无损的
    grid = 256
    bg_cov = coverage(bg_paths, size=grid, ss=2)
    fg_cov = coverage([d for _, g in fg_groups for d in g], size=grid, ss=2)
    total = grid * grid
    solid_bg = sum(1 for v in bg_cov if v > 0.99)
    solid_fg = sum(1 for v in fg_cov if v > 0.99)
    gap = sum(1 for i in range(total) if bg_cov[i] < 0.01 and fg_cov[i] < 0.01)
    print('self-check on %dx%d: background %.2f%%, foreground %.2f%%, uncovered %.4f%%'
          % (grid, grid, solid_bg * 100.0 / total, solid_fg * 100.0 / total,
             gap * 100.0 / total))
    if gap * 100.0 / total > 0.5:
        print('ERROR: %.4f%% of the canvas is covered by neither layer; a flat background '
              'would change those pixels. Re-check the SVG before shipping.'
              % (gap * 100.0 / total), file=sys.stderr)
        return 1
    if args.check:
        print('--check: split verified, nothing written')
        return 0

    # 前景层：按绘制顺序合成各颜色组
    print('rasterising foreground at %dx%d (%dx vertical supersampling)...' % (SIZE, SIZE, SUPERSAMPLE))
    layers = [(hex_rgb(fill), coverage(group)) for fill, group in fg_groups]
    foreground = compose(layers)

    # 背景层：纯色 RGB，逐字节全不透明
    background = bytes(BG_COLOR) * (SIZE * SIZE)

    # 启动页图标：前景压在背景上的完整合成图（单层，带 alpha 以便系统裁形）
    start_icon = bytearray(SIZE * SIZE * 4)
    for i in range(SIZE * SIZE):
        j = i * 4
        fa = foreground[j + 3] / 255.0
        inv = 1.0 - fa
        start_icon[j] = int(foreground[j] * fa + BG_COLOR[0] * inv + 0.5)
        start_icon[j + 1] = int(foreground[j + 1] * fa + BG_COLOR[1] * inv + 0.5)
        start_icon[j + 2] = int(foreground[j + 2] * fa + BG_COLOR[2] * inv + 0.5)
        start_icon[j + 3] = 255

    media = os.path.join(root, MEDIA_REL)
    appscope = os.path.join(root, APPSCOPE_MEDIA_REL)
    # entry 与 AppScope 用不同文件名：编译期 AppScope 资源会合入模块同名路径并
    # 覆盖模块资源，同名会让 module.json5 里配的图标被 AppScope 的覆盖掉。
    targets = [
        (os.path.join(media, 'layered_foreground.png'), 6, foreground),
        (os.path.join(media, 'layered_background.png'), 2, background),
        (os.path.join(media, 'startIcon.png'), 6, bytes(start_icon)),
        (os.path.join(appscope, 'app_layered_foreground.png'), 6, foreground),
        (os.path.join(appscope, 'app_layered_background.png'), 2, background),
    ]
    for path, ctype, payload in targets:
        size_bytes = write_png(path, SIZE, payload, ctype)
        print('  wrote %-58s %s %7.1f KiB'
              % (os.path.relpath(path, root).replace('\\', '/'),
                 'RGBA' if ctype == 6 else 'RGB ', size_bytes / 1024.0))

    total_px = SIZE * SIZE
    clear = sum(1 for i in range(total_px) if foreground[i * 4 + 3] == 0)
    solid = sum(1 for i in range(total_px) if foreground[i * 4 + 3] == 255)
    print('background layer: colour type 2, no alpha channel -> cannot contain transparent pixels')
    print('foreground layer: %.2f%% clear, %.2f%% opaque, %.2f%% antialiased edge'
          % (clear * 100.0 / total_px, solid * 100.0 / total_px,
             (total_px - clear - solid) * 100.0 / total_px))
    return 0


if __name__ == '__main__':
    sys.exit(main())
