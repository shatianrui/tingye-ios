# 待激活的测试 workflow（暂存说明）

本目录里的 `tests.yml` 是给 GitHub Actions 用的测试 workflow，内容已定稿，
但**暂存**在这里，还没有生效。生效位置应该是：

```
.github/workflows/tests.yml
```

## 为什么暂存

Muse 的 GitHub 集成（GitHub App）没有 `workflows` 权限，向
`.github/workflows/` 推送文件会被 GitHub 拒绝
（`403 Resource not accessible by integration`，git trees API 与
contents API 均已实测被拒）。这和当初 `build-unsigned-ipa.yml`
落地时遇到的情况一样，需要仓库所有者在网页端手动提交这一个文件。

## 激活步骤（网页端，约 2 分钟）

1. 打开分支 `ci-add-actions-tests`，新建文件
   `.github/workflows/tests.yml`（Add file → Create new file）。
2. 把本目录 `docs/ci/tests.yml` 的内容**原样**粘贴进去，
   提交到同一分支 `ci-add-actions-tests`。
3. 提交后本 PR 会自动触发 workflow：`unit-tests`（TingyeTests）
   与 `ui-tests`（TingyeUITests，非阻断）两个 job 开始在
   macOS runner 上跑。
4. 激活完成后，本目录（`docs/ci/`）可以删除，避免留下一份
   会过期的 workflow 副本；不删也不会被 Actions 执行，无副作用。

## 这个 workflow 做什么

- 触发：手动 `workflow_dispatch` + 每个 `pull_request`。
- `unit-tests`：`xcodebuild test -scheme Tingye -only-testing:TingyeTests`，
  跑在动态挑选的 iPhone 模拟器上；失败会让 PR 变红；
  xcresult 与日志作为 artifact 上传。
- `ui-tests`：`-only-testing:TingyeUITests`，单独 job、
  `continue-on-error: true` 非阻断。原因：已知 8 个 UI 用例过期
  （断言已删除的标识符 continue.reading、now.listen、now.search、
  navigation.tab.0/1/2），必红，是测试过期而非 App bug；
  先只出报告，修好用例后再去掉非阻断。
- 不改动现有 `build-unsigned-ipa.yml` 的任何行为。
