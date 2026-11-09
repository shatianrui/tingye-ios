"""Create tiny, synthetic EPUB regression fixtures (no copyrighted book content)."""
from pathlib import Path
import struct
import zlib
import zipfile

root = Path(__file__).resolve().parent.parent / 'TingyeTests' / 'Fixtures'
def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)

png = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0))
       + chunk(b'IDAT', zlib.compress(b'\x00\x22\x66\x44')) + chunk(b'IEND', b''))

for legacy in (False, True):
    nav_item = '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>' if not legacy else ''
    package = f'''<package xmlns="http://www.idpf.org/2007/opf" version="{'2.0' if legacy else '3.0'}" unique-identifier="id">
      <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">fixture</dc:identifier><dc:title>加载回归样本</dc:title><dc:creator>听页测试</dc:creator><meta name="cover" content="cover"/></metadata>
      <manifest>{nav_item}<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
      <item id="one" href="Text/one.xhtml" media-type="application/xhtml+xml"/>
      <item id="two" href="Text/two.xhtml" media-type="application/xhtml+xml"/>
      <item id="cover" href="Images/cover%20one.png" media-type="image/png" properties="cover-image"/>
      <item id="vector" href="Images/vector.svg" media-type="image/svg+xml"/>
      <item id="font" href="Fonts/test.woff2" media-type="font/woff2"/>
      <item id="css" href="Styles/book.css" media-type="text/css"/></manifest>
      <spine toc="ncx"><itemref idref="two"/><itemref idref="one"/></spine></package>'''
    files = {
      'META-INF/container.xml': '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OPS/book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>',
      'OPS/book.opf': package,
      'OPS/nav.xhtml': '<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><body><nav epub:type="toc"><ol><li><a href="Text/one.xhtml#start">第一卷 <span>春风</span> 续</a><ol><li><a href="Text/two.xhtml">第二章</a></li></ol></li></ol></nav></body></html>',
      'OPS/toc.ncx': '<ncx><navMap><navPoint id="one"><navLabel><text>旧目录第一卷</text></navLabel><content src="Text/one.xhtml#start"/><navPoint id="two"><navLabel><text>旧目录第二章</text></navLabel><content src="Text/two.xhtml"/></navPoint></navPoint></navMap></ncx>',
      'OPS/Text/one.xhtml': '<html xmlns="http://www.w3.org/1999/xhtml"><head><link href="../Styles/book.css" rel="stylesheet"/><style>.inline{background-image:url("../Images/cover%20one.png")}</style></head><body><p id="start">第一段<strong>粗体</strong>尾声。</p><img src="../Images/cover%20one.png"/><img src="../Images/vector.svg"/><svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink"><image xlink:href="../Images/cover%20one.png"/></svg><p>正文示例 url(../Images/cover%20one.png)</p></body></html>',
      'OPS/Text/two.xhtml': '<html xmlns="http://www.w3.org/1999/xhtml"><body><h2>文件内标题</h2><p>第二章的正文。</p></body></html>',
      'OPS/Styles/book.css': '@font-face{font-family:Fixture;src:url("../Fonts/test.woff2")} .art{background:url(../Images/cover%20one.png)}',
      'OPS/Images/cover one.png': png,
      'OPS/Images/vector.svg': '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10" fill="green"/></svg>',
      'OPS/Fonts/test.woff2': b'placeholder font bytes; not a rendering fixture',
    }
    target = root / ('loading-ncx.epub' if legacy else 'loading-nav.epub')
    with zipfile.ZipFile(target, 'w') as archive:
        archive.writestr('mimetype', 'application/epub+zip', compress_type=zipfile.ZIP_STORED)
        for name, data in files.items():
            archive.writestr(name, data, compress_type=zipfile.ZIP_DEFLATED)
    print(target.name)
