#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""听页 · v30 设计画廊生成器。

把 pages/ 下的每一屏拼成一张可浏览的总览页（iframe 内嵌真实页面，可点击交互）。
产物：Design/v30-anthropic/gallery.html

用法：python3 Design/v30-anthropic/make-gallery.py
"""
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
PAGES = os.path.join(HERE, 'pages')

# 展示顺序（与 render-previews.py 的 ORDER 对齐，未列出的按字母追加）
ORDER = [
    'reader', 'reader-chrome', 'reader-contents', 'reader-preferences',
    'reader-annotations', 'notes', 'player', 'voice', 'focus',
    'focus-summary', 'book-finish', 'comic',
    'shelf', 'shelf-grid', 'library-management', 'book-detail', 'import',
    'remote-sources', 'me', 'stats', 'reading-calendar',
    'settings-reading', 'settings-general', 'settings-data', 'settings-about',
    'states', 'accessibility', 'app-icon',
]

LABELS = {
    'reader': '阅读器 · 静读态', 'reader-chrome': '阅读器 · 工具态',
    'reader-contents': '目录面板', 'reader-preferences': '排版面板',
    'reader-annotations': '选区面板', 'notes': '摘记列表',
    'player': '听书面板', 'voice': '声音设置',
    'focus': '专注会话', 'focus-summary': '专注小结', 'book-finish': '读完收尾',
    'comic': '漫画阅读', 'shelf': '书库 · 列表', 'shelf-grid': '书库 · 网格',
    'library-management': '书库 · 整理', 'book-detail': '书籍详情',
    'import': '添书', 'remote-sources': '远程书源', 'me': '我的',
    'stats': '统计', 'reading-calendar': '阅读日历',
    'settings-reading': '设置 · 阅读', 'settings-general': '设置 · 通用',
    'settings-data': '设置 · 数据与备份', 'settings-about': '设置 · 关于',
    'states': '状态与空态', 'accessibility': '无障碍与适配', 'app-icon': '应用图标',
}

SCALE = 0.62
W, H = 390, 844
# 内层页面 body 有 48px 内边距、.device 外描边 8px：
#   横向 device 起点 = 48 + (310 - 390)/2 = 8px（含描边共 406）
#   纵向 device 起点 = 48px（含描边共 40→900）
# iframe 用 406×956，再用 translate 抵消纵向偏移，保证设备框完整可见。
IF_W, IF_H = 406, 956
OFF_Y = 40


def page_title(path):
    src = open(path, encoding='utf-8').read()
    m = re.search(r'<title>(.*?)</title>', src, re.S)
    return m.group(1).strip() if m else os.path.basename(path)


def main():
    files = sorted(f[:-5] for f in os.listdir(PAGES) if f.endswith('.html'))
    ordered = [p for p in ORDER if p in files] + [p for p in files if p not in ORDER]

    cards = []
    for name in ordered:
        path = os.path.join(PAGES, name + '.html')
        label = LABELS.get(name, name)
        cards.append(f'''
    <figure class="card">
      <div class="frame">
        <iframe src="pages/{name}.html" title="{label}" loading="lazy" scrolling="no" tabindex="-1"></iframe>
      </div>
      <figcaption>
        <span class="nm">{label}</span>
        <span class="fn">{name}.html</span>
      </figcaption>
    </figure>''')

    html = f'''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>听页 · v30「Claude · Anthropic」设计画廊</title>
<link rel="stylesheet" href="colors_and_type.css">
<style>
  body {{ display:block; padding:56px 40px 80px; background:var(--ty-canvas); }}
  header {{ max-width:1180px; margin:0 auto 44px; }}
  header .kicker {{ font-size:11px; font-weight:500; letter-spacing:2px; color:var(--ty-clay-text); text-transform:uppercase; }}
  header h1 {{ font-family:var(--ty-font-serif); font-size:40px; color:var(--ty-ink); margin:10px 0 12px; font-weight:400; }}
  header p {{ font-size:16px; color:var(--ty-ink-2); line-height:1.7; max-width:760px; }}
  header .rule {{ height:2px; background:var(--ty-ink); margin:22px 0 0; width:56px; }}
  .grid {{ max-width:1180px; margin:0 auto; display:grid; grid-template-columns:repeat(auto-fill,minmax({round(IF_W*SCALE,1)+40}px,1fr)); gap:34px 26px; }}
  .card {{ margin:0; }}
  .frame {{ width:{round(IF_W*SCALE,1)}px; height:{round((IF_H-2*OFF_Y)*SCALE,1)}px; overflow:hidden;
            border-radius:20px; box-shadow:0 6px 20px rgba(20,20,19,0.13);
            border:6px solid #1B1A18; background:var(--ty-canvas); }}
  .frame iframe {{ width:{IF_W}px; height:{IF_H}px; border:0; transform-origin:0 0;
                   transform:translateY({round(-OFF_Y*SCALE,2)}px) scale({SCALE}); }}
  figcaption {{ margin-top:11px; display:flex; flex-direction:column; gap:2px; }}
  figcaption .nm {{ font-family:var(--ty-font-serif); font-size:15px; color:var(--ty-ink); }}
  figcaption .fn {{ font-family:var(--ty-font-mono); font-size:11px; color:var(--ty-ink-4); }}
  footer {{ max-width:1180px; margin:56px auto 0; padding-top:22px; border-top:1px solid var(--ty-line);
            font-size:12px; color:var(--ty-ink-4); display:flex; justify-content:space-between; }}
</style>
</head>
<body>
  <header>
    <div class="kicker">TINGYE · DESIGN GALLERY</div>
    <h1>听页 · v30「Claude · Anthropic」</h1>
    <p>全界面视觉重设计：奶油画布、四档暖中性墨色、唯一品牌色陶土只标记「正在发生」；
       宋体做标题、等宽做数字、实心墨底做主动作。信息架构沿用 v29「书房」，数据层与功能行为不变。</p>
    <div class="rule"></div>
  </header>

  <div class="grid">{''.join(cards)}
  </div>

  <footer>
    <span>Design/v30-anthropic · {len(cards)} 屏 · 由 make-gallery.py 生成</span>
    <span>本页每格都是可交互的真实设计稿（iframe 内嵌）</span>
  </footer>
</body>
</html>
'''
    out = os.path.join(HERE, 'gallery.html')
    with open(out, 'w', encoding='utf-8') as f:
        f.write(html)
    print(f'生成 {out}（{len(cards)} 屏）')


if __name__ == '__main__':
    main()
