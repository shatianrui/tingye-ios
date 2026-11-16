#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""听页 · v30 设计稿渲染管线。

把 pages/*.html 渲染成单屏 PNG（390×844），并拼一张总览图。

用法：
  python3 Design/v30-anthropic/render-previews.py            # 渲染全部
  python3 Design/v30-anthropic/render-previews.py shelf      # 只渲染指定页（不带 .html）

输出：Design/v30-anthropic/previews/<page>.png 与 previews/_overview.png
"""
import os
import sys

from PIL import Image
from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
PAGES = os.path.join(HERE, 'pages')
OUT = os.path.join(HERE, 'previews')
CHROME = '/root/.cache/ms-playwright/chromium-1243/chrome-linux/chrome'

# 页面顺序（决定总览图里的排列）
ORDER = [
    'reader', 'reader-chrome', 'reader-contents', 'reader-preferences',
    'reader-annotations', 'notes', 'player', 'voice', 'focus',
    'focus-summary', 'book-finish', 'comic',
    'shelf', 'shelf-grid', 'library-management', 'book-detail', 'import',
    'remote-sources', 'me', 'stats', 'reading-calendar',
    'settings-reading', 'settings-general', 'settings-data', 'settings-about',
    'states', 'accessibility', 'app-icon',
]


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
            outs.append(png)
        browser.close()
    return outs


def overview(names, out_dir: str):
    """把单屏 PNG 拼成总览图（每行 6 张）。names 为 PNG 文件名（不含扩展名）。"""
    tiles = []
    for n in names:
        f = os.path.join(out_dir, n + '.png')
        if os.path.exists(f):
            tiles.append((n, Image.open(f).convert('RGB')))
    if not tiles:
        return None
    tw = 300
    cols = 6
    th = int(tw * 844 / 390)
    pad = 26
    rows = (len(tiles) + cols - 1) // cols
    W = cols * (tw + pad) + pad
    H = rows * (th + pad + 22) + pad
    canvas = Image.new('RGB', (W, H), (232, 230, 222))
    from PIL import ImageDraw
    d = ImageDraw.Draw(canvas)
    for i, (name, im) in enumerate(tiles):
        r, c = divmod(i, cols)
        x = pad + c * (tw + pad)
        y = pad + r * (th + pad + 22)
        canvas.paste(im.resize((tw, th), Image.LANCZOS), (x, y))
        d.text((x + 4, y + th + 5), name, fill=(60, 58, 54))
    path = os.path.join(out_dir, '_overview.png')
    canvas.save(path)
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
                print(f'  ✅ {os.path.basename(o)}')
        except Exception as e:
            print(f'  ❌ {n}: {e}')
    ov = overview(ok, OUT)
    print(f'\n共 {len(ok)} 张；总览：{ov}')


if __name__ == '__main__':
    main()
