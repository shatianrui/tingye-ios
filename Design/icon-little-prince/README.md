# 听页 · 抱书的小王子（02 定稿）

用户已选定 **02「抱书的小王子」**，并授权完成后上传。图标已替换进 App，随 **1.18.0（105）** 于 **2026-10-20** 完成 iOS / Mac Catalyst Release 归档与 TestFlight 上传。两端均收到成功回执，上传时 Apple 状态为正在处理，**尚未确认可安装**；没有提交正式 App Store 审核。

## 最终图标

打开 [最终预览](final/index.html) 或 [定稿总览](final/overview.png)。默认 PNG 与用户选中的初始预览逐字节相同；夜间与着色版本只调整配色，不改变人物、姿势、构图与表情。

| 用途 | SVG 源稿 | PNG 资源 |
| --- | --- | --- |
| 默认：柔和鼠尾草绿 | [light.svg](final/light.svg) | [AppIcon.png](final/AppIcon.png) |
| iOS 夜间：深绿背景与柔和书页 | [dark.svg](final/dark.svg) | [AppIcon-dark.png](final/AppIcon-dark.png) |
| iOS 系统着色：中性灰阶输入 | [tinted.svg](final/tinted.svg) | [AppIcon-tinted.png](final/AppIcon-tinted.png) |

实际 App 使用 `Tingye/Resources/Assets.xcassets/AppIcon.appiconset/` 下的同名文件，保留原有 appearance 配置。iPhone / iPad 归档包含三种外观；Mac 归档使用默认资源生成 `AppIcon.icns`。系统着色图展示的是灰阶输入，最终色彩由 iOS 的桌面选色决定，不以网页模拟代替真机效果。

源图为 **1024 × 1024、不带 alpha 的方形 PNG**，不预烘焙圆角。预览页中的圆角、阴影、桌面背景与 60 / 40 CSS px 样例仅是展示效果，不是系统截图。

## 可复现生成与安装

从仓库根目录执行，需要本机 Google Chrome；浏览器使用一次性配置目录，只渲染本地 SVG，不读取个人浏览器配置或连接账号。

```sh
# 只生成 Design 下的最终 SVG / PNG，不改 App
python3 Design/icon-little-prince/render-icons.py

# 明确安装：复制已检查的三张 PNG 到现有 AppIcon 资源目录
python3 Design/icon-little-prince/render-icons.py --install

# 原生解码与逐像素检查：尺寸、无 alpha、完全不透明、着色图灰阶
swift Design/icon-little-prince/validate-icons.swift
```

`02-reading.svg` 是用户选定构图的单一源稿；`render-icons.py` 提供夜间 / 着色映射，并检查默认图与选型 PNG 的 SHA-256 一致。SVG 无外部图片或字体依赖，颗粒由本地滤镜生成。PNG 为 Chrome 1024 × 1024、1 倍像素比渲染。渲染器升级后若输出变化，应复核像素差异，不要绕过默认图一致性检查。

## 验证与发布证据

- 三图尺寸与不透明检查通过；CoreGraphics 逐像素检查着色图 RGB 最大通道差为 0。日志 `build/little-prince-icon/pixel-validation.log`，资源哈希 `build/little-prince-icon/final-assets.json`。
- iPhone 17e / iOS 27 **95 / 95 项回归通过**：`build/icon-105-tests.log`、`build/Icon105Tests.xcresult`。
- iOS 与 Mac Catalyst Release 归档、签名 / 权限 / dSYM / DEBUG 隔离检查通过。使用 `assetutil` 验证了包内的图标外观，并抽样查看了 iOS PNG 与 Mac ICNS 的导出图。
- 上传日志：`build/upload-105.log`、`build/upload-105-mac.log`；均返回 `Upload succeeded` 与 `EXPORT SUCCEEDED`，进程退出码为 0。处理回执不等于 TestFlight 已可安装。
- 生产构建输入相对 104 仅改变三张图标和两个构建号配置文件；应用功能 Swift 源码未改。完整发布记录与真机验收边界见 [发布历史](../../docs/RELEASE_HISTORY.md)、[验收清单](../../docs/ACCEPTANCE.md)。

## 初始选型记录

[三款初始提案](index.html) 与 [选型阶段总览](previews/overview.png) 保留历史展示。01、02、03 是三个独立方向，不是同一图标的外观版本；当时的「未替换」说明仅对应选型阶段。01 与 03 没有加入 App。

图形以《小王子》的故事意象重新绘制，没有导入扫描书封、网络角色图片或现成图标，不代表特定出版社的官方素材。
