#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""听页 · v30 设计稿自检。

逐页检查：
  1. CSS 常见拼写错误（grid-template-template-columns 这类重复片段）
  2. 页面里用到的 class 是否在 colors_and_type.css / device.css / 页面内 <style> 里有定义
  3. CSS 声明里是否硬编码了 hex 颜色（颜色必须走令牌；正文里的色值标签不算）
  4. 是否引用了外部资源（离线打不开）
  5. 内容是否溢出 .device 框（用 Chromium 实测每个框的 scrollHeight）

用法：python3 Design/v30-anthropic/lint-pages.py
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PAGES = os.path.join(HERE, 'pages')


def resolve_chrome() -> str:
    """优先用设计环境里的 Playwright Chromium；本机没有时改用已安装的 Chrome。"""
    candidates = [
        os.environ.get('CHROME_PATH', ''),
        '/root/.cache/ms-playwright/chromium-1243/chrome-linux/chrome',
        r'C:\Program Files\Google\Chrome\Application\chrome.exe',
        r'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
    ]
    for path in candidates:
        if path and os.path.isfile(path):
            return path
    return candidates[1]


CHROME = resolve_chrome()

TYPO_PATTERNS = [
    (r'grid-template-template-columns', 'grid-template-columns 写重了'),
    (r'grid-templat-columns', 'grid-template-columns 拼写错误'),
    (r'border-radius-radius', 'border-radius 写重了'),
    (r'padding-padding', 'padding 写重了'),
    (r'font-size-size', 'font-size 写重了'),
    (r'color-color', 'color 写重了'),
    (r'flex-direction-direction', 'flex-direction 写重了'),
]

# 只在 CSS 声明位置里找硬编码颜色
HEX_IN_DECL = re.compile(
    r'(?:^|[;{\s])(?:color|background|background-color|border|border-color|fill|stroke|'
    r'box-shadow|text-shadow|outline-color)\s*:\s*[^;{}]*?#[0-9A-Fa-f]{3,8}\b', re.I | re.M)

EXTERNAL = re.compile(r'(?:src|href)\s*=\s*["\'](https?:)?//', re.I)

# 基础类名白名单（来自 device.css / colors_and_type.css）
ALLOW = {
    'ico', 'fill', 'dot', 'tb-mid', 'cap-title', 'cap-note', 'cap-tokens',
    'title', 'sub', 'nm', 'st', 'ok', 'bad', 'warn', 'q', 'n', 'meta', 'num', 'unit',
    'label', 'value', 'msg', 'on', 'is-active', 'is-selected', 'is-clay', 'is-outline',
    'is-soft-clay', 'wide', 'space', 'kr', 'key', 'mono', 'serif',
    'sw', 'swatches', 'big', 'variants', 'home', 'grid4', 'kbd', 'se', 'ax5', 'dark',
    'imp-list', 'imp-item', 'empty-wrap', 'toast-bar', 'dialog', 'acts', 'nores', 't',
}


def collect_classes(css_text: str) -> set:
    return set(re.findall(r'\.([A-Za-z_][A-Za-z0-9_-]*)', css_text))


def overflow_check(pages):
    """实测每个 .device 的内容高度是否超出框高。"""
    from playwright.sync_api import sync_playwright
    bad = []
    with sync_playwright() as p:
        b = p.chromium.launch(executable_path=CHROME, args=['--no-sandbox'])
        pg = b.new_context(viewport={'width': 1900, 'height': 1200}).new_page()
        for name in pages:
            pg.goto('file://' + os.path.join(PAGES, name))
            pg.wait_for_timeout(180)
            res = pg.evaluate("""() => {
              const out = [];
              document.querySelectorAll('.device').forEach((d, i) => {
                const r = d.getBoundingClientRect();
                let maxB = 0, culprit = '';
                d.querySelectorAll('*').forEach(el => {
                  const b = el.getBoundingClientRect();
                  if (b.bottom > maxB) { maxB = b.bottom; culprit = el.className || el.tagName; }
                });
                out.push({i, h: r.height, maxB: maxB, over: maxB - r.bottom, culprit: String(culprit).slice(0,40)});
              });
              return out;
            }""")
            for r in res:
                if r['over'] > 2:
                    bad.append(f"{name}[{r['i']}]: 内容超出框底 {r['over']:.0f}px（{r['culprit']}）")
        b.close()
    return bad


def main():
    base = ''
    for f in ('colors_and_type.css', 'device.css'):
        base += open(os.path.join(HERE, f), encoding='utf-8').read()
    base_classes = collect_classes(base)

    problems = []
    pages = sorted(f for f in os.listdir(PAGES) if f.endswith('.html'))
    for name in pages:
        src = open(os.path.join(PAGES, name), encoding='utf-8').read()
        style_blocks = '\n'.join(re.findall(r'<style>(.*?)</style>', src, re.S))
        local_classes = collect_classes(style_blocks)

        for pat, msg in TYPO_PATTERNS:
            for m in re.finditer(pat, src):
                problems.append(f'{name}: {msg} —— {m.group(0)}')

        used = set()
        for m in re.finditer(r'class="([^"]+)"', src):
            used.update(m.group(1).split())
        for c in sorted(used):
            if c in base_classes or c in local_classes or c in ALLOW:
                continue
            problems.append(f'{name}: class .{c} 未定义')

        for m in HEX_IN_DECL.finditer(style_blocks):
            line_start = style_blocks.rfind('\n', 0, m.start()) + 1
            line = style_blocks[line_start:style_blocks.find('\n', m.start())]
            if 'exempt:' in line:
                continue          # 显式豁免：系统控件模拟等非应用界面配色
            problems.append(f'{name}: CSS 里硬编码颜色 —— {m.group(0).strip()[:70]}')

        for m in EXTERNAL.finditer(src):
            problems.append(f'{name}: 引用外部资源 —— {src[max(0,m.start()-30):m.start()+60]}')

        # 「实心只给墨底主按钮」：主按钮不得刷成陶土或 danger 实心。
        for m in re.finditer(r'class="[^"]*btn-primary[^"]*"[^>]*style="[^"]*background:\s*var\(--ty-(clay|danger)[^"]*"', src):
            problems.append(f'{name}: 实心按钮用了陶土/danger —— {m.group(0)[:90]}')

    problems += overflow_check(pages)

    if problems:
        print(f'发现 {len(problems)} 个问题：')
        for p in problems:
            print('  -', p)
        return 1
    print(f'✅ {len(pages)} 页全部通过：无拼写错误、无未定义 class、'
          f'CSS 无硬编码颜色、无外部资源、实心按钮只用墨底、内容未溢出设备框。')
    return 0


if __name__ == '__main__':
    sys.exit(main())
