#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""听页 · v30 设计稿渲染管线。

把 pages/*.html 渲染成单屏 PNG（@2x，390×844 逻辑尺寸），再拼成两张分组接触表。

为什么用「量化 PNG + 分组 JPG」而不是全分辨率大图：
  GitHub 侧单次写入请求有 ~500KB 上限，一张容纳全部 28 屏的全分辨率接触表
  即使压到 JPEG 也要 280KB 以上（缩到 160px 单格仍如此），塞不进单次请求。
  因此：单屏用 256 色调色板 PNG（体积降约 2/3，视觉无损），接触表按组拆成两张 JPG。

用法：
  python3 Design/v30-anthropic/render-previews.py            # 渲染全部
  python3 Design/v30-anthropic/render-previews.py shelf      # 只渲染指定页（不带 .html）

输出：
  Design/v30-anthropic/previews/<page>.png          单屏（量化 PNG）
  Design/v30-anthropic/previews/_overview-1.jpg     接触表 · 阅读与播放
  Design/v30-anthropic/previews/_overview-2.jpg     接触表 · 书库与设置
"""
import os
import sys

from PIL import Image, ImageDraw
from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
PAGES = os.path.join(HERE, 'pages')
OUT = os.path.join(HERE, 'previews')
CHROME = '/root/.cache/ms-playwright/chromium-1243/chrome-linux/chrome'

# 页面顺序（决定接触表里的排列）
ORDER = [
    'reader', 'reader-chrome', 'reader-contents', 'reader-preferences',
    'reader-annotations', 'notes', 'player', 'voice', 'focus',
    'focus-summary', 'book-finish', 'comic',
    'shelf', 'shelf-grid', 'library-management', 'book-detail', 'import',
    'remote-sources', 'me', 'stats', 'reading-calendar',
    'settings-reading', 'settings-general', 'settings-data', 'settings-about',
    'states', 'accessibility', 'app-icon',
]

# 接触表分组：每组单独一张，控制在单次写入请求上限内
GROUPS = [
    ('_overview-1.jpg', ['reader', 'reader-chrome', 'reader-contents',
                         'reader-preferences', 'reader-annotations', 'notes',
                         'player', 'voice', 'focus', 'focus-summary',
                         'book-finish', 'comic']),
    ('_overview-2.jpg', ['shelf', 'shelf-grid', 'library-management', 'book-detail',
                         'import', 'remote-sources', 'me', 'stats', 'reading-calendar',
                         'settings-reading', 'settings-general', 'settings-data',
                         'settings-about', 'states', 'accessibility', 'app-icon']),
]

TILE_W = 240
COLS = 6
PAD = 22


def quantize(path: str) -> int:
    """把 PNG 压成 256 色调色板：体积降约 2/3，界面截图色阶有限，视觉无损。"""
    before = os.path.getsize(path)
    im = Image.open(path).convert('RGB')
    q = im.quantize(colors=256, method=Image.MEDIANCUT, dither=Image.FLOYDSTEINBERG)
    q.save(path, optimize=True)
    return before - os.path.getsize(path)


def render(page_name: str, out_dir: str):
    """渲染一页。一页含多个 .device 时逐个出图：<page>-1.png、<page>-2.png…"""
    html = os.path.join(PAGES, page_name + '.html')
    with sync_playwright() as p:
        browser = p.chromium.launch(executable_path=CHROME,
                                    args=['--no-sandbox', '--font-render-hinting=none'])
        ctx = browser.new_context(viewport={'width': 1700, 'height': 1000},
                                  device_scale_factor=2)
        page = ctx.new_page()
        page.goto('file://' + html)
        page.wait_for_timeout(250)
        devs = page.query_selector_all('.device')
        if not devs:
            print(f'  [WARN] {page_name}.html 没有 .device 元素')
            browser.close()
            return []
        outs = []
        multi = len(devs) > 1
        for i, dev in enumerate(devs):
            png = os.path.join(out_dir, (f'{page_name}-{i + 1}.png' if multi
                                         else page_name + '.png'))
            dev.screenshot(path=png)
            saved = quantize(png)
            outs.append(png)
            print(f'  ✅ {os.path.basename(png)}  压缩 {saved // 1024}KB')
        browser.close()
    return outs


def contact_sheet(files, path: str):
    """把若干单屏拼成一张接触表 JPG。"""
    tiles = [(os.path.splitext(os.path.basename(f))[0], Image.open(f).convert('RGB'))
             for f in files if os.path.exists(f)]
    if not tiles:
        return None
    th = int(TILE_W * 844 / 390)
    rows = (len(tiles) + COLS - 1) // COLS
    W = COLS * (TILE_W + PAD) + PAD
    H = rows * (th + PAD + 20) + PAD
    canvas = Image.new('RGB', (W, H), (232, 230, 222))
    d = ImageDraw.Draw(canvas)
    for i, (name, im) in enumerate(tiles):
        r, c = divmod(i, COLS)
        x = PAD + c * (TILE_W + PAD)
        y = PAD + r * (th + PAD + 20)
        canvas.paste(im.resize((TILE_W, th), Image.LANCZOS), (x, y))
        d.text((x + 4, y + th + 4), name, fill=(60, 58, 54))
    canvas.save(path, quality=82, optimize=True, progressive=True)
    return path


def main():
    os.makedirs(OUT, exist_ok=True)
    if len(sys.argv) > 1:
        names = [a if a.endswith('.html') else a + '.html' for a in sys.argv[1:]]
        names = [os.path.splitext(n)[0] for n in names]
    else:
        names = [f for f in sorted(os.listdir(PAGES)) if f.endswith('.html')]
        names = [os.path.splitext(n)[0] for n in names]
    ok = []
    for n in names:
        try:
            outs = render(n, OUT)
            for o in outs:
                ok.append(os.path.splitext(os.path.basename(o))[0])
        except Exception as e:
            print(f'  ❌ {n}: {e}')

    print()
    for out_name, members in GROUPS:
        files = [os.path.join(OUT, m + '.png') for m in members]
        p = contact_sheet(files, os.path.join(OUT, out_name))
        if p:
            print(f'  ✅ {out_name}  {os.path.getsize(p) // 1024}KB  （{len(members)} 屏）')
    print(f'\n共 {len(ok)} 张单屏；接触表 2 张。')


if __name__ == '__main__':
    main()
