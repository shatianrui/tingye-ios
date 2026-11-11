# 无签名 IPA（听页）

用 `scripts/build-unsigned-ipa.sh` 在 Mac 上打出一个**无签名、瘦身版**的听页 IPA，
供侧载使用。签名版 App Store 流程完全不受影响：`Tingye.xcodeproj`、
`ExportOptions.plist`、`Tingye.entitlements` 都没有改动，无签名的覆盖只在
构建命令里传参。

## 用 GitHub Actions 打并放到 Release

工作流：`.github/workflows/build-unsigned-ipa.yml`，跑在 GitHub 的
macOS runner 上，不需要你自己的 Mac，也不需要证书。

触发方式（二选一）：

1. 手动：GitHub 网页打开仓库 → Actions → Build unsigned IPA →
   Run workflow，选择分支。可以选 `unsigned-ipa-slim` 分支直接跑，
   也可以先把这个分支合并到 main 再跑。输入里可以选是否瘦身字体、
   是否用 `-Osize`、以及自定义 Release tag（留空自动生成）。
2. 打 tag：`git tag unsigned-1.24.0-20261112.1 && git push origin <tag>`，
   tag 必须以 `unsigned-` 开头，工作流会用该 tag 名直接发 Release。

自动生成的 tag 格式沿用仓库已有的习惯：
`unsigned-<版本>-<日期>.<序号>`，例如 `unsigned-1.24.0-20261112.1`，
版本号从 pbxproj 读。Release 附件是 `Tingye-unsigned.ipa` 和
`Tingye-unsigned.ipa.sha256`（`shasum -a 256` 校验），同时还会留一份
Actions artifact（保留 30 天），即使 Release 步骤失败也能下载。

之前已有同类 Release，例如
`unsigned-1.24.0-20261110.1`（附件约 37 MB，由 github-actions[bot]
上传），本工作流沿用同一 tag / 附件命名。

注意：私有仓库的 macOS runner 按 GitHub 计费规则消耗分钟数；
工作流不需要任何 secret，只用默认 `GITHUB_TOKEN` 发 Release。

## 怎么打（本地 Mac）

```sh
chmod +x scripts/build-unsigned-ipa.sh   # 第一次，或直接用 bash scripts/build-unsigned-ipa.sh
# 默认：瘦身字体（见下）
scripts/build-unsigned-ipa.sh

# 保留全部 4 个字体（包更大）
scripts/build-unsigned-ipa.sh --full-fonts

# 更小二进制（-Osize，可能稍慢）
scripts/build-unsigned-ipa.sh --osize

# 把 .dSYM 拷到 build/dSYM/（不打进 IPA，方便以后看崩溃）
scripts/build-unsigned-ipa.sh --keep-dsym
```

产物在 `build/Tingye-unsigned.ipa`（`build/` 已在 `.gitignore` 里）。
版本号不写死，脚本从 `project.pbxproj` 读 `MARKETING_VERSION` /
`CURRENT_PROJECT_VERSION`。注意：目前 pbxproj 是 **1.24.0（128）**，
而 README 写的是 1.24.0（123），以 pbxproj 为准。

构建要点（都在脚本里）：Release、`generic/platform=iOS`、仅 arm64、
`CODE_SIGNING_ALLOWED=NO`、`CODE_SIGN_IDENTITY=""`、
`CODE_SIGNING_REQUIRED=NO`、`CODE_SIGN_STYLE=Manual`、
`CODE_SIGN_ENTITLEMENTS=Tingye/Tingye-unsigned.entitlements`（空）、
`DEVELOPMENT_TEAM=""`、Whole Module `-O`、`DEBUG_INFORMATION_FORMAT=dwarf`、
strip / 死代码消除全开。不走 `ExportOptions.plist` 的 `-exportArchive`，
而是直接从 `.xcarchive` 取出 `Tingye.app`，去掉 `_CodeSignature` /
`embedded.mobileprovision`（如有），打包成 `Payload/Tingye.app` 再 zip。

## 瘦身做了什么

包体大头是字体。4 个内置中文字体共约 45 MB：

| 字体 | 大小 | 处理 |
| --- | --- | --- |
| NotoSansCJKsc-Regular.otf（思源黑体） | 约 15.7 MB | 保留，UI 必需 |
| LXGWWenKaiLite-Regular.ttf（霞鹜文楷） | 约 13.2 MB | 无签名版默认移除 |
| LXGWNeoXiHei.ttf（霞鹜新晰黑） | 约 7.1 MB | 无签名版默认移除 |
| NotoSerifCJKsc-Regular.otf（思源宋体） | 约 7.0 MB | 保留，正文默认字体 |

默认移除两个 LXGW 字体，未压缩约省 **20.3 MB**。IPA 是 zip 压缩，
实际文件能小多少要看压缩率，字体本身已是压缩格式，所以别指望
IPA 直接小 20 MB，以 Mac 上实测的 `ls -lh` 为准。

移除是**只针对无签名版打包后的副本**，仓库里的字体文件、签名版
包体、以及 `Theme.swift` 的 `bundledFonts` 都不动。运行时已有回退，
不会崩溃：

- CoreText 阅读路径：`UIFont(name:)` 取不到字体时落到系统字体。
- 原书模式 CSS：楷体落到 `Kaiti SC`，新晰黑落到 `sans-serif`。
- 之前在设置里选了楷体 / 新晰黑的用户，在这个版本里会看到回退字体，
  而不是报错。

为什么不做字体子集化：书籍可能含生僻字、繁体、人名、古文，子集化缺字
会在一页内混字体；更关键的是 `ReaderView` 用字体度量做 CoreText 分页，
字形度量一变，分页、句子坐标、划线、跟读高亮都可能错位。风险大于收益，
所以先不做。

其他瘦身：仅 arm64、不带 `.dSYM`、strip 开启、zip 最高压缩。
`SongLandscape.png`（约 2.26 MB）是 xcassets 里唯一的大图，暂未动，
如需再压可单独处理。

## 无签名版不能用的功能

`Tingye.entitlements` 里的 iCloud / 钥匙串组权限在无签名包里不存在，
代码里已有降级，不会崩溃，但以下功能会失效：

- iCloud Drive 手动备份与还原（含旧签名版留下的 iCloud 快照）
- iCloud 键值存储自动同步阅读位置（跨设备续读）；本机位置不受影响
- 从 iCloud 删除某本书
- 沿用旧签名版钥匙串里的 TTS 密钥、源站密码、会话令牌，
  需要重新输入；新密钥在新签名下可以正常保存

备份 / 还原按钮在无签名版里仍可点，但每次都会失败，失败文案目前
写的是“未登录 / 未开 iCloud Drive”，实际原因是缺权限，这一点
后续可以再修文案。删除时请用“仅删除本机”，“删除本机和 iCloud”
在无签名版里会失败，但本机副本不会被删。

能用的：本机书库、阅读、听书（重输密钥后可用云语音）、本地导入 /
导出、WiFi 传书、SMB、系统语音。

## 安装

这个 IPA 是**无签名**的，不能直接装到未越狱的 iPhone 上。
请用你自己的个人证书重签后再安装，例如 AltStore、Sideloadly，
或用 TrollStore / 越狱设备直接安装。具体步骤以你所用工具的说明为准。

## 验证

脚本打完后会自动检查：

- `lipo -info` 应为 arm64 单架构
- `codesign -dv` 应显示未签名
- `unzip -l` 里不应有 `.dSYM`、`_CodeSignature`、`embedded.mobileprovision`
- 瘦身模式下不应有 `LXGW` 字体
- `Info.plist` 里的 `CFBundleShortVersionString` / `CFBundleVersion`
  应与 pbxproj 一致

本机（Linux）无法运行 Xcode，所以这份脚本**尚未在 Mac 上实测构建**。
第一次在 Mac 上跑时请把完整输出贴回来，失败时先看归档日志，
常见原因是 entitlements 或团队设置没被命令行覆盖。
