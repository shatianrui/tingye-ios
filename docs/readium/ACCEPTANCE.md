# 听页 Readium 全量迁移验收

记录日期：2026-11-16 UTC。工作区 readium-engine；版本 1.25.0（142）。交付物见 [UNIT1](UNIT1.md)、[UNIT2](UNIT2.md)、[UNIT3](UNIT3.md)、[UNIT4](UNIT4.md)；验收依据是 [PLAN](PLAN.md) 四个单元的验收段落及 5.3 转换合同。

**当前状态：实现已落盘，发布验收未完成。** “通过（静态）”只表示本文列出的文件/结构检查；“未实测”不表示用例已通过。“已知限制”是不能承诺恢复/实现的边界。Linux 无 Swift、Xcode、iOS SDK，本轮未执行任何 XCTest、模拟器 UI 或 archive；目标为单测 173 个和 UI 28 个全部实测通过，尚不能宣称全绿。

## 四单元交付物

| 单元 | 已落盘交付 | 验收状态 |
| --- | --- | --- |
| 1 | exact Readium 3.11.1、单一 ZIP fork；原包持久化/事务/摘要、Store/cache/pin、LegacyEPUBBuilder、PublicationMap；原包/存量夹具与许可 | 工程/原夹具静态检查通过；历史后续 CI 已有相关单测通过，总体仍需本轮回归与 Release/EPUBCheck。 |
| 2 | EPUB 唯一路由、Navigator 容器/会话、七纸面、偏好/字体桥接、目录/错误/重试、统一统计 visibility | 实现与纯函数测试存在；本轮未实测，视觉/旋转/fixed/竖排仍待设备。 |
| 3 | 四类引用双存、StoredLocator、TextDOMIndex、迁移/快照、选区/标注、全部跳转、简繁原文/显示投影、KVS | 已提供 Tests #17 的全单测 160/160 基线；本轮改动后不能沿用为通过，需重跑。 |
| 4 | Readium 文本层唯一导入、句级 TTS/search 分组、原包附件往返、许可证/空间 UI、首次快照并发修复、UI 改写/冒烟 | 213 对象工程/源文件词法/夹具等静态检查通过；新增 13 个单测和 1 个 UI 尚未运行。 |

## 对照 PLAN 全量验收

| 条目 | 状态 | 证据及待做 |
| --- | --- | --- |
| 单一 ZIP identity、exact 依赖、工程/生成器不漏文件 | 通过（静态）；resolve 未实测 | 锁定 16 个 identity，app 三个 Toolkit product；新 Source/许可唯一挂接；生成器递归规则已有。需 Mac 实际 resolver。 |
| Release unsigned archive、CSS/JS/字体资源 bundle | 未实测 | 本轮无 Xcode；构建脚本未改，须检查 IPA 中 Toolkit bundle 和瘦身字体回退。不能使用发布 workflow 代替本地构建验收。 |
| 原包 readingOrder/TOC/cover、坏包明确错误 | 未实测（实现/测试齐） | ReadiumPublicationTests、TextSnapshotTests；新导入不再有旧 EPUB 解析入口。 |
| 存量派生合法 EPUB、spine/nav/images/cover | 未实测（历史单测基线通过） | LegacyEPUBBuilder 测试保留；无原包不重算已有 text。 |
| 派生 EPUBCheck | 未实测 | XML 良构/CRC 已静态通过，不能代替 EPUBCheck。需对实际 Swift 生成的包检查。 |
| body 残壳/缺 HTML/中文与重复 path/data URI/缺资源/封面/图片章 | 未实测（夹具/测试存在） | UNIT1 夹具和重建报告；单元 4 新增纯插图章、空章及实体/ruby/表格/长句。 |
| 取消、写入失败、ENOSPC、异常杀进程/重启恢复 | 部分测试存在；未实测 | 取消与 catalog 故障/事务重放有测试；真实低存储、系统杀进程待真机。 |
| 清缓存再生、并发合并、活跃 pin 保护 | 未实测（实现/测试齐） | Store source/cache 分离、进程 pin 前缀；旧 Store 的活跃 pin 也不被新 Store 清理。 |
| 同 ID 替换/修书/还原不复用旧 source/cache/Locator authority | 未实测（实现/测试齐） | 持久 epoch、会话 generation、revision 双屏障；备份往返测试含旧回调拒绝。 |
| EPUB 所有阅读入口进入 Navigator；其他格式原引擎 | 通过（静态）；入口 UI 未实测 | ReaderRouter 保留漫画/PDF 优先，只按 format=EPUB 切换；未用 document 猜格式。 |
| 翻章、内部链接、原层级 TOC/派生平铺 TOC | 未实测 | 原包保留 Readium TOC；派生目录源数据只够平铺；UI 改写检查 EPUB TOC 双向跳章。 |
| 七纸面×日夜、alwaysLight | 未实测（纯函数测试存在） | paper/mist/ancient/eink/white/blue/night 的背景/正文/次字均有期望表；真机需逐组看对比度。 |
| 字号/行距/段距/页边距/缩进/对齐/字距 | 未实测；负字距为已知限制 | 与同套 ReaderPreferences 换算；Toolkit 负字距钳制 0，原用户值保留。视觉尺寸待校准。 |
| system/四内置/自定义 TTF/OTF/TTC/缺字体回退 | 未实测 | 文件存在性、family/metrics/TTC URL 有测试；完整与瘦身 IPA 的实际 WebKit face 仍需验证。 |
| 滚动/分页/横竖屏/宽屏双栏/eink | 未实测 | 650 宽度与滚动/eink/双页分支有测试，需设备观察排版/位置保持。 |
| fixed-layout、竖排、SVG 样本 | 未实测 | 没有专门实际设备样本；SVG 文字兼容抽取已接，不能据此声称版式和选区均通过。 |
| 偏好/字体/简繁切换后保留位置 | 未实测（实现/测试齐） | 普通偏好 submitPreferences；重建以原文 Locator 恢复，generation 隔离旧回调。 |
| 简繁只改显示；源字节/text 不变、原文/选区往返 | 未实测；不确定边界为已知限制 | UNIT3 单测基线包含长度变化/词语/emoji；不确定替换内部边界不产精确标注。 |
| 阅读统计/后台听书互斥，不重复计时 | 未实测（原测试保留） | 只有现有 5 秒 tick，EPUB 接同一 visibility；Player 展开不算前台正文。 |
| 5.3-1 旧章→href、spine 变化与缺 path 受限查找 | 未实测（实现/测试齐） | 原包路径/唯一标题、派生明确映射、跨章文本候选；重复文本不能唯一确定时保留 unresolved。 |
| 5.3-2 UTF-16/DOM/原文与显示范围 | 未实测（历史单测基线通过） | TextDOMIndex 与 TextOffsetMap；实体、标题、空白、ruby、表格、脚注、emoji 回归保留。 |
| 5.3-3 >120 字/多句完整划线、五色+旧 green、三样式 | 未实测（历史单测基线通过） | Highlight 全文/ID/date/note 保留；user Decoration，不用句首短 quote 冒充范围。 |
| 5.3-4 反解句/跨度/锚点；听书句反向 Locator | 未实测（实现/测试齐） | 旧坐标、TextAnchor、原文 Locator 三层都保留；新桥覆盖可见位置与播放句。 |
| 5.3-5 精确/重定位/近似/unresolved 等级，初始化回调屏障 | 未实测（实现/测试齐） | approx 不改兼容坐标，unresolved 原业务数据保留；请求 UUID 与 source revision 校验。 |
| 5.3-6 TXT/MOBI/PDF/漫画等仍原生，逻辑 Locator 往返 | 未实测（历史单测基线通过） | 未改其他格式解析/排版/听书逻辑；本轮仅 async 调用适配和备份公共边界。 |
| 5.3-7 四类引用、可取消/重试/原子提交、首次备份不污染 | 未实测（新增回归） | 全局 NSLock 保证首次快照仅创建一次；两本书并发迁移测试要求首次备份字节仍为迁移前 catalog。 |
| 5.3-8 KVS 双写/去重/上限/旧端回声，备份兼容 | 未实测（历史基线+新测试） | 原 KVS c/p/t 与扩展不变；新附件 Optional，整库 v1/单书 v2 不升级。需真实双设备验证。 |
| 书签/搜索/摘记/今日一句/听书→阅读均走桥 | 未实测 | 单元 3 统一目标入口保留；单元 4 Player 返回共用 sentence 目标；所有入口需 UI/真机串测。 |
| 新 EPUB 只用 Readium 解释结构，句切分与旧 HTML 路径一致 | 通过（静态接线）；XCTest 未实测 | 删除旧 epub 解析函数；SnapshotBuilder 复用 HTMLText/Sentence；6 个新测试中包含一致性、元数据/封面/映射、拒绝坏包、回滚。 |
| 旧 EPUB 文本/进度/搜索/听书不因升级被重算 | 通过（静态）；运行回归未实测 | 只有新导入或带原包恢复生成快照，其他存量原文仍按旧数据派生。 |
| 当前页/选区起播、句 seek、后台、系统/云语音、停止/恢复/跟随开关 | 未实测 | 句级桥与 EPUB 控件已接；不动 SpeechPlayer 实际播放机制。系统/GLM/MiniMax、锁屏后台仍需设备。 |
| EPUB TTS Decoration、暂停清理，不清 user；阅读/听书互不覆盖 | 未实测（实现/测试齐） | 三组单独 apply；自动跟随不 persist 成阅读位置。播放器保留逐字字幕，EPUB 正文只做整句 Decoration。 |
| 书内重复搜索/标题结果跳转和短暂命中标示 | 未实测（实现/测试齐） | 复用原搜索，真实 UTF-16 范围，标题-only 不误标正文；确认导航后两秒清 search。 |
| 书架百分比/最近阅读不被音频改写 | 未实测（原回归保留） | sentenceCounts/readFraction 原口径；稳定失败 UI 已单独定性，不能据源码宣布已修复。 |
| 整库/单书导出→删本机→新库恢复 source/Locator | 未实测（6 个新备份测试） | 包括 makeLibraryExportFile、新库恢复、精确 Locator、同 ID 新附件/旧无附件、坏附件降级。 |
| iCloud 快照删除书目连同附件移除 | 未实测（真实本地 store 测试存在） | 覆盖 ICloudBackupStore.save/read/removeBook 的改写与删除，不只是内存数组过滤。 |
| 旧 JSON 无附件仍可读、旧端忽略新字段 | 未实测（结构兼容/回归存在） | Optional 解码，无大版本升级，路径描述本身不能授权恢复旧 source。 |
| 许可证 UI/出处与锁定版本一致，原文件不可清、派生缓存可清 | 通过（静态）；UI 未实测 | 完整组件清单与随包许可；source 归书库单列，cache 清理经过 Store。 |
| 大书内存、首开/二次打开、备份时间/峰值 | 未实测 | 无可用设备或采样数据，不能把缓存预算当峰值。JSON base64 全库备份有明显内存开销。 |
| 离线/重启/低存储恢复 | 未实测 | 本地源/派生无需网络；故障注入仅源码测试，真实设备待验。 |
| 全单测/EPUB UI/全 UI/unsigned archive | 未实测 | 本轮目标 173 单测、28 UI、Release archive；无 skip 或测试删除。 |
| 构建 142、不改 workflows/git/其他格式规则 | 通过（静态与操作记录） | 四处显式构建号 142；锁文件/workflows SHA 相同；无 git 命令。 |

## 测试总账

| 套件 | 方法数 | 本轮运行/通过 |
| --- | ---: | --- |
| NativeCoreTests | 113 | 0 / 未运行 |
| ReadiumPublicationTests | 10 | 0 / 未运行 |
| ReadiumPreferencesTests | 12 | 0 / 未运行 |
| ReadiumLocatorTests | 15 | 0 / 未运行 |
| LocatorMigrationTests | 11 | 0 / 未运行 |
| ReadiumTextSnapshotTests | 6 | 0 / 未运行 |
| ReadiumBackupSourceTests | 6 | 0 / 未运行 |
| 单测总计 | **173** | **0 / 未运行** |
| DesignFlowTests | **28** | **0 / 未运行** |

总控提供的历史基线：Tests #17 单测 160/160；UI 21/27，失败为四项 OriginalReader、RecentReadingStaysPrimary、HomeShowsContinueAndRecent。Tests #15 UI 21/27、#16 UI 22/27；ReaderKeepsActionSlots 在 #15 败、后两轮过。历史记录不计入本轮测试执行数。

本轮实际通过的检查：完整 pbxproj OpenStep 解析（213 对象）、引用/新增成员/真实 Source 路径、Swift 词法定界符/字符串/注释、异步调用点、新旧 base64 夹具 ZIP CRC/mimetype/XML、UTF-8 新文件、测试方法计数、构建号与锁文件/workflows 哈希。不是 Swift typecheck；没有 SPM resolve、XCTest、UI、Release 或 EPUBCheck 运行结果。

28 项 UI 逐项状态如下；全部因无模拟器而未运行，没有整套 skip：

| 用例（省略 test 前缀） | 本轮源码处理 | 实测 |
| --- | --- | --- |
| EPUBDerivedFixtureSmokeAndSearch | 新增派生 EPUB 正文/目录/搜索/设置/返回 | 未实测 |
| HomeShowsContinueAndRecentWithoutScrolling | 保留场景、补目标状态等待 | 未实测 |
| RecentReadingStaysPrimaryWhileAnotherBookHasListeningProgress | 独立定性、限定英雄卡选择器与终态 | 未实测 |
| HomeSearchOpensExistingShelfSearch | 保留 | 未实测 |
| ReaderToolsAndTypographyRemainAvailable | TXT 原生覆盖保留 | 未实测 |
| PagedReaderChromeDoesNotReflowOrMoveReadingPosition | TXT 原生几何覆盖保留 | 未实测 |
| DarkHomeAndShelfKeepPrimaryActionsReachable | 保留 | 未实测 |
| ShelfOrganizeAndDetailsAreExplicit | 保留 | 未实测 |
| PlayerCanScrubSentencesAndKeepPaused | 保留 | 未实测 |
| LargestTypePlayerControlsRemainReachable | 保留 | 未实测 |
| LargestTypeHomeAndShelfActionsRemainReachable | 保留 | 未实测 |
| MixedImportUsesResultsInsteadOfSuccessAlert | 保留 | 未实测 |
| ReaderKeepsActionSlotsAndChapterNavigationDoesNotSeekAudio | 保留 TXT 场景、补状态等待；另有 EPUB 覆盖 | 未实测 |
| OriginalReaderKeepsFollowingThroughRepeatedPlaybackToggles | EPUB 句级高亮/暂停/继续/独立跳章 | 未实测 |
| ReaderNotesAndSearchOpenWithoutStartingAudio | TXT 原生覆盖保留 | 未实测 |
| ReaderMoreGroupsDayNightAndKeepsBookmarkSeparate | TXT 原生覆盖保留 | 未实测 |
| ShelfSeparatesFilterSortAndLayoutAndProtectsDeletion | 保留 | 未实测 |
| PlayerToolsAreDirectAndPreservePausedState | 保留 | 未实测 |
| MiniPlayerOnlyExpandsAndTogglesAndEndNeedsConfirmation | 保留 | 未实测 |
| LargestTypeReaderToolsCanScrollWithoutLosingBackButton | TXT 原生覆盖保留 | 未实测 |
| MarginProfileAndAppearanceRoutesRemainAvailable | 保留 | 未实测 |
| OriginalReaderKeepsTypographyAndContentsReachable | EPUB 正文/目录/设置/纸色保持 | 未实测 |
| OriginalReaderDarkModeKeepsChapterControlsReachable | EPUB 夜间目录双向跳章 | 未实测 |
| OriginalReaderChromeDoesNotResizeOrMoveItsColumn | EPUB 可见正文/视口/元素几何 | 未实测 |
| PDFReaderKeepsReadingToolsAndNotesReachable | PDF 覆盖保留 | 未实测 |
| PDFReaderChromeDoesNotResizeScaleOrMoveItsPage | PDFKit 几何覆盖保留 | 未实测 |
| MarginDarkPlayerAndReaderKeepControlsReachable | 保留 | 未实测 |
| LandscapePlayerKeepsPlaybackVisible | 保留 | 未实测 |

## 已知限制

- EPUB 的 fade/blur 没有同名 Toolkit 转场，使用 Navigator 标准翻页，原偏好值保留给原生格式。
- Readium 3.11.1 不接受负字距，EPUB 显示钳制为 0；字号/行距等跨引擎数值映射仍待视觉校准。
- 存量数据未保存的原字体、音视频、部分图片/CSS 依赖、原 TOC 层级与版式无法无损恢复；派生报告记录损失，补原包才能恢复来源内容。
- 简繁不确定替换块的内部边界不伪造精确选区/Decoration；只保存原文 Locator，显示转换不改源文件/text。
- 定位资源读取上限 4 MiB、单资源文本上限 350,000 UTF-16，索引 LRU 约 16 MiB；全书候选等预算见 UNIT3。预算外会降为近似/未解析，无法精确定位的标注仍保留。多个相同 href/重复文本无法可靠消歧时不承诺唯一位置。
- EPUB 正文是句级 TTS Decoration，未新增字级 Decoration；播放器原有逐字字幕/时间不变。无法精确反解的可见位置会提示，不能冒充按当前句成功起播。
- 直接非 HTML/SVG 媒体作为 readingOrder 的 EPUB 不能生成本次兼容文本快照，明确报格式错误；没有旧解析器静默回退。
- 单书 BackupPacket 继续只含 Book+阅读进度及新增原包附件，不扩展到全部书签/划线/听书进度；整库包含四类引用。
- JSON base64 原包附件带来体积、峰值内存与临时空间开销，未做大书实测；没有静默附件大小上限或大版本升级。
- 首次快照锁保障当前单进程不同任务/实例，不提供多进程写库合同。空间统计涵盖各 owner 并按文件分配字节相加，硬链接 pin 可能重复计数；清理入口只清当前书库的派生缓存，其他书库缓存保留。
- 出版物脚本/隐式远程资源策略尚缺专门恶意样本的端到端审计；没有把仅外链导航拦截称为完整安全验收。

## Mac/CI 与真机待验交接

先在 Mac 执行实际依赖解析和完整单测（选可用的 iOS 模拟器目的地），再运行全部 28 个 DesignFlowTests；保存 xcresult 和失败行/可访问性树。尤其重复运行审计中的 7 项，不能只跑过一次就关闭时序问题。之后执行本地 unsigned Release archive，检查 bundle、字体回退和可安装启动；不触发发布 workflow。对 Swift 实际生成的派生包跑 EPUBCheck。

交给用户的真机清单：

1. 备份现有书库，选一册原包 EPUB 与一册无原包存量 EPUB；首开/退出/杀进程/离线重开，检查正文、目录、链接、阅读位置与 source 保留。
2. 两类书逐项检查七纸面日夜/常亮、四内置字体与自定义 TTF/OTF/TTC、瘦身缺字体、字号/行段距/缩进/对齐/字距、滚动/分页、旋转/双栏；另准备竖排/fixed/SVG 样本。记录 fade/blur 与负字距差异。
3. 原文/简繁各建书签与三种划线，含重复文本、长多句、emoji、ruby/表格/脚注；改色/笔记/删除、从详情/摘记/今日一句/搜索/播放器返回，核对原文范围和旧数据不丢。
4. 翻到章中当前页/选区起播，系统、GLM、MiniMax 分别测句 seek、暂停/继续、结束、跟随开关、跨章跟随、锁屏/后台；手动阅读跳章不得 seek 声音，声音回调不得覆盖独立阅读断点。核对 user 划线在暂停 TTS 后仍在。
5. 重复搜索词、首尾空白、仅目录标题命中；逐项点击核对位置与两秒标示，之后原划线仍在；检查前台阅读/后台音频统计互斥及书架百分比/最近阅读。
6. 单书与整库分别导出到文件，删除本机后导入新库；核对 source 摘要、TOC/版式、精确 Locator。再用旧无附件/坏附件/同 ID 不同原包恢复；不得沿用旧 source。实际 iCloud 双设备也做一次往返与删除快照书目附件。
7. 阅读时打开空间整理，清 EPUB/其他/全部缓存；当前页面和后续翻页可用，原包仍在，派生包可再生。测大书首开、二次打开、导出/恢复峰值与低存储失败；保留耗时、内存、损失报告和故障后库可恢复的记录。

在上述运行门槛与关键数据安全场景未实测完成前，本记录不将迁移标为发布验收通过；构建号 143 由总控合并发布时决定。
