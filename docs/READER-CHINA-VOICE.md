# 正文单一高亮与中国区语音

本轮将原生正文的朗读高亮统一为浅色背景，移除额外跟读下划线；标注面板只提供浅底样式。旧直线/波浪线标注仅在显示时映射为浅底，不改写旧书摘与备份中的样式字段。阅读方式按较小范围保留：本轮没有删除原书图文或连续滚动入口。

声音与朗读页新增「智谱 GLM · 中国区」「MiniMax · 中国区」直接配置入口，保留各自模型、音色和 Keychain 密钥的隔离存储。GLM 使用 `https://open.bigmodel.cn/api/paas/v4/audio/speech`；MiniMax 主接口使用 `https://api.minimax.cn/v1/t2a_v2`，原官方国内域名保留为兼容回退。默认模型为 glm-tts / speech-2.8-hd，支持试听、MiniMax 账号音色查询与原有朗读控制。

请求构造增加空文本/空密钥校验与服务商模型/音色校正，未知提供方不会误发给 MiniMax。MiniMax Token Plan 密钥不附加 GroupId，普通密钥支持可选 GroupId。设置中提供官方控制台链接，不代替用户申请或购买语音额度。

官方依据：

- [智谱 GLM-TTS](https://docs.bigmodel.cn/cn/guide/models/sound-and-video/glm-tts)
- [MiniMax 中国区同步语音合成](https://platform.minimax.cn/docs/api-reference/speech-t2a-http)
- [MiniMax 音色查询](https://platform.minimax.cn/docs/api-reference/voice-management-get)

新增 5 项高亮/请求契约回归和 2 项中国区设置入口 UI 回归，加入手动发布流程，测试不使用真实密钥、不触发付费云合成。实际播放仍取决于用户密钥权限、余额和网络；本轮未声称通过付费语音实听。
