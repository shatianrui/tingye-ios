#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""听页 · v30「Claude · Anthropic」应用图标生成器。

设计主张（Anthropic 语汇）
  · 奶油画布 #FAF9F5 打底 + 炭黑墨 #141413 的摊开书页 + 唯一陶土色 #D97757 的三道声波
  · 扁平、无渐变、无描边装饰；陶土只出现在「正在发生」的三道声波上
  · 构图留白充足：内容落在 1024 画布中心约 62% 的方形内，系统圆角后仍完整
  · 三变体：浅色 / 深色 / 着色（着色为纯灰阶，交由系统着色）

输出：
  app-icon/icon-light.svg / icon-dark.svg / icon-tinted.svg
  app-icon/AppIcon.png / AppIcon-dark.png / AppIcon-tinted.png  (1024×1024, RGB, 无 alpha)
  app-icon/preview-sheet.png                                  (三变体 × 三尺寸预览)
"""
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
CHROME = '/root/.cache/ms-playwright/chromium-1243/chrome-linux/chrome'

# ── 变体配色 ────────────────────────────────────────────────────────────
VARIANTS = {
    'light': {
        'ground': '#FAF9F5',
        'book':   '#141413',
        'wave':   '#D97757',
        'label':  '浅色',
    },
    'dark': {
        'ground': '#141413',
        'book':   '#FAF9F5',
        'wave':   '#E08C6E',
        'label':  '深色',
    },
    'tinted': {
        'ground': '#F2F2F0',
        'book':   '#4A4A48',
        'wave':   '#9A9A96',
        'label':  '着色',
    },
}

# ── 几何 ────────────────────────────────────────────────────────────────
CANVAS = 1024

# 摊开的书：两页在中缝分开 16px（中缝露出地面色），顶边呈浅 V、底边呈浅 Λ。
BOOK_LEFT = 176
BOOK_RIGHT = 848
BOOK_TOP_OUTER = 496
BOOK_TOP_SPINE = 576
BOOK_BOTTOM_OUTER = 736
BOOK_BOTTOM_SPINE = 814
SPINE_GAP = 16
SPINE_X = 512

# 声波：三道同心圆弧，圆心落在书脊下方的书页里，向上张开 ±52°。
WAVE_CX = 512
WAVE_CY = 630
WAVE_RADII = (190, 285, 380)
WAVE_HALF_SPAN = 52          # 度，对称于竖直轴
WAVE_STROKE = 34

# 光学微调：书重、弧轻，整体上移 12px 让视觉重心落在画布中心。
GROUP_DY = -12


def wave_path(r: float) -> str:
    """从左端点沿大弧（经过正上方）画到右端点。"""
    a = math.radians(WAVE_HALF_SPAN)
    dx = r * math.sin(a)
    dy = r * math.cos(a)
    x0, y0 = WAVE_CX - dx, WAVE_CY - dy
    x1, y1 = WAVE_CX + dx, WAVE_CY - dy
    return (f'M {x0:.2f} {y0:.2f} '
            f'A {r:.2f} {r:.2f} 0 0 1 {x1:.2f} {y1:.2f}')


def build_svg(v: dict) -> str:
    g, b, w = v['ground'], v['book'], v['wave']
    inner_l = SPINE_X - SPINE_GAP // 2
    inner_r = SPINE_X + SPINE_GAP // 2
    left = (f'M {BOOK_LEFT} {BOOK_TOP_OUTER} L {inner_l} {BOOK_TOP_SPINE} '
            f'L {inner_l} {BOOK_BOTTOM_SPINE} L {BOOK_LEFT} {BOOK_BOTTOM_OUTER} Z')
    right = (f'M {BOOK_RIGHT} {BOOK_TOP_OUTER} L {inner_r} {BOOK_TOP_SPINE} '
             f'L {inner_r} {BOOK_BOTTOM_SPINE} L {BOOK_RIGHT} {BOOK_BOTTOM_OUTER} Z')
    waves = '\n'.join(
        f'    <path d="{wave_path(r)}" fill="none" stroke="{w}" '
        f'stroke-width="{WAVE_STROKE}" stroke-linecap="round"/>'
        for r in WAVE_RADII)

    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" viewBox="0 0 {CANVAS} {CANVAS}">
  <rect width="{CANVAS}" height="{CANVAS}" fill="{g}"/>
  <g transform="translate(0 {GROUP_DY})">
  <g fill="{b}">
    <path d="{left}"/>
    <path d="{right}"/>
  </g>
  <g>
{waves}
  </g>
  </g>
</svg>
'''


def render_png(svg_path: str, png_path: str):
    """用 Chromium 把 SVG 渲染成 1024×1024 PNG（无 alpha）。"""
    from playwright.sync_api import sync_playwright
    html = f'''<!doctype html><html><head><meta charset="utf-8"><style>
html,body{{margin:0;padding:0;background:#fff;}}
img{{display:block;width:{CANVAS}px;height:{CANVAS}px;}}
</style></head><body><img src="file://{svg_path}"></body></html>'''
    html_path = svg_path.replace('.svg', '.render.html')
    with open(html_path, 'w', encoding='utf-8') as f:
        f.write(html)
    with sync_playwright() as p:
        browser = p.chromium.launch(
            executable_path=CHROME,
            args=['--no-sandbox', '--font-render-hinting=none'])
        page = browser.new_page(viewport={'width': CANVAS, 'height': CANVAS},
                                device_scale_factor=1)
        page.goto('file://' + html_path)
        page.wait_for_timeout(300)
        page.screenshot(path=png_path, omit_background=False)
        browser.close()
    os.remove(html_path)


def build_preview_sheet(pngs: dict):
    """三变体 × 三尺寸的预览台。"""
    from playwright.sync_api import sync_playwright
    sizes = [180, 96, 48]
    cells = []
    for key in ('light', 'dark', 'tinted'):
        for s in sizes:
            cells.append(
                f'<figure><img src="file://{pngs[key]}" style="width:{s}px;height:{s}px" '
                f'alt="{key} {s}"><figcaption>{key} · {s}</figcaption></figure>')
    html = f'''<!doctype html><html><head><meta charset="utf-8"><style>
html,body{{margin:0;background:#E8E6DE;font:12px/1.4 -apple-system,system-ui,sans-serif;color:#3D3D3A;}}
.wrap{{display:grid;grid-template-columns:repeat(3,auto);gap:26px 46px;padding:34px 40px;width:max-content;}}
figure{{margin:0;display:flex;flex-direction:column;align-items:center;gap:9px;}}
img{{border-radius:22.37%;display:block;}}
figcaption{{font-size:11px;color:#6E6D66;letter-spacing:.02em;}}
</style></head><body><div class="wrap">{''.join(cells)}</div></body></html>'''
    html_path = os.path.join(HERE, '.preview.html')
    out_path = os.path.join(HERE, 'preview-sheet.png')
    with open(html_path, 'w', encoding='utf-8') as f:
        f.write(html)
    with sync_playwright() as p:
        browser = p.chromium.launch(executable_path=CHROME, args=['--no-sandbox'])
        page = browser.new_page(viewport={'width': 900, 'height': 700},
                                device_scale_factor=2)
        page.goto('file://' + html_path)
        page.wait_for_timeout(600)
        page.screenshot(path=out_path, full_page=True)
        browser.close()
    os.remove(html_path)


def main():
    out = HERE
    os.makedirs(out, exist_ok=True)
    pngs = {}
    for key, v in VARIANTS.items():
        svg_path = os.path.join(out, f'icon-{key}.svg')
        png_path = os.path.join(out, f'AppIcon{"" if key == "light" else "-" + key}.png')
        with open(svg_path, 'w', encoding='utf-8') as f:
            f.write(build_svg(v))
        render_png(svg_path, png_path)
        pngs[key] = png_path
        print(f'生成 {os.path.basename(svg_path)} / {os.path.basename(png_path)}')
    build_preview_sheet(pngs)
    print('生成 preview-sheet.png')
    print('完成。')


if __name__ == '__main__':
    main()
