# 无签名构建 · 纸页与松绿

本改版保留阅读、听书、导入、书库整理与本地数据结构，重新设计首页、全局色彩与底部导航。设计范围与检查记录见 [设计说明](REDESIGN-PAPER-PINE.md)。阅读器保存的字体与纸色继续生效。

## 在 Mac 构建

安装完整 Xcode，选择其 Developer 目录后，在仓库根目录执行：

```sh
bash scripts/build-unsigned.sh
```

产物为 `build/Tingye-unsigned.ipa` 与 SHA-256 文件。脚本通过独立 xcconfig 禁用签名、团队、描述文件与原团队 entitlements，并定义 `TINGYE_UNSIGNED`。不需要 Apple 开发者证书；Swift Package 首次解析仍需联网。原签名构建仍使用 Tingye scheme 的现有配置。

也可推送本分支后，手动运行 GitHub Actions 的 **Unsigned iOS** 工作流，下载构建产物。工作流先运行无签名能力隔离的模拟器用例，再打包；现有云同步测试需使用原构建配置单独回归。工作流不会上传 TestFlight 或发布 Release。本次未推送、未运行远端工作流。

## 安装与功能范围

无签名 IPA 是待签名产物，不能直接在普通 iPhone 上运行。用自己的签名工具及对应描述文件重新签名后安装；可安装性取决于所用签名与设备。原 Bundle ID 保留；重签改变 Bundle ID 或钥匙串组后，不能保证沿用已有安装的数据与密钥。操作前请导出本地书籍备份。

此配置不包含原团队的 iCloud 容器与共享钥匙串组。自动阅读位置同步不启动，手动 iCloud 操作给出明确提示；本地书库及导出继续可用。语音密钥继续使用系统默认私有 Keychain，不写入明文文件。原签名配置中的 iCloud 功能不受该开关影响。

## 验证范围

当前开发环境为 Linux，没有 Xcode、iOS SDK 与模拟器。仅可执行脚本语法、配置和静态检查；未声称 Swift 编译、模拟器回归或真机安装通过。现有 NativeCoreTests / DesignFlowTests 需在 Mac 上执行，再审查日夜、小屏和最大字号的实际画面。
