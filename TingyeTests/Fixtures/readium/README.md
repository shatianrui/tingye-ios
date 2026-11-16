# Readium 单元 1 夹具

本目录全部是听页为测试原创的数据，无第三方书籍内容。

- `original.epub`：EPUB 3，两个 spine 文档、中文平铺 nav、2×2 PNG 封面。mimetype 第一项、stored、无 extra。
- `legacy-book.json`：原生 Book 根结构；三章，document HTML/CSS、body 残壳、中文路径、重复原 path、无 HTML 的旧章、nativeImages、重复图片 data URI、封面、章间 fragment、缺失图片/字体/远程 CSS 依赖。

Swift 测试另在内存中派生坏 XML、内嵌 data URI、无资源、坏包及取消场景，不改原夹具。生成的 Publication 在测试的独立临时目录内，测试结束删除。

单元 3 的 `catalog-141.json` / `catalog-142.json` 为原创目录夹具，分别缺少/包含 142 TextAnchor；均含阅读、听书、书签及带笔记的旧 green/wavy 划线。`locator-book.json` 使用相同根 JSON / Chapter.fields 形态，提供与这些引用完整吻合的 DOM。原 `legacy-book.json` 则保留清洗前后正文差异，继续用于保守未解析验证。所有夹具为文本；`original.epub.b64` 仍由测试解码到临时目录，不新增二进制。
