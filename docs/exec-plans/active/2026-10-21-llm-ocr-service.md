# 添加可选多模态 LLM OCR 服务

- 状态：active
- 创建日期：2026-10-21
- 负责人：Unknown
- 关联 Issue/PR：none

## 执行上下文

- **Agent Name:** `Unknown`
- **Model:** `Unknown`
- **Environment:** `macOS Unknown / Xcode Unknown (Unknown)`

## 背景

截图入口已通过 EZOCRResult 将识别文本送入既有翻译流程，但 DetectManager 固定使用 Apple OCR。
用户要求以多模态模型替代 OCR，而不是直接进行图片翻译。

## 目标与范围

- 目标结果：可选 OpenAI 兼容 LLM OCR 服务，保留默认本地 Apple OCR；模型只转录原文。
- 允许修改路径：独立 LLMOCR 模块、OCR 选择与回调边界、设置和本地化、工程引用、相关验证和文档。
- 同任务 history：`docs/histories/2026-10/2026-10-21-llm-ocr-service.md`
- 用户限制：不使用 Codex、不使用用户 Mac；编译交由 GitHub Actions；本次新增测试、新分支推送及 GitHub Actions 已获明确许可。
- 非目标：直接图片翻译、原生 Gemini/Claude 协议、CLI OCR、自动配置或调用用户密钥。
- 验收标准：选定服务识别截图后继续既有翻译流程；保留换行、Markdown 表格和 LaTeX；错误不得当成功文本，过时结果不得覆盖新输入。

## 工作计划

1. 检查 OCR、设置、请求和结果边界，明确兼容接口。
2. 实现独立配置、网络客户端与 QueryService 适配。
3. 小范围接入 OCR 选择与请求时序保护，补设置与隐私说明。
4. 在获得许可后增加测试与 CI，验证、审查并交付。

## 风险与决策

- 默认关闭远程 OCR，明确截图将上传至配置地址且可能计费；不自动调用真实服务。
- 独立 OCR 配置，不更改现有翻译服务配置或发送翻译指令。
- 不伪造文字位置、置信度或翻译结果；拒绝截断、空响应和无效输出。
- 远程请求更慢，需要取消和过时结果保护；禁止静默重发至其他供应商。

## 进度

- [x] 确认截图到现有翻译的文本边界。
- [x] 配置、客户端和服务实现。
- [x] 设置、时序边界与本地化。
- [x] 获授权的离线测试、GitHub Actions 编译和代码审查。
- [ ] 真实服务识别质量与手动交互验收。

## 验证

- 基线：`5a594f1ecf069d1eac995926ff72c7fb3602f1ff`，工作树初始干净。
- `git diff --check`、本地化 JSON 及六种语言覆盖、工程文件引用静态检查通过。
- 只读审查发现 OCR 错误/取消时 loading 和原输入恢复问题，已通过视图控制器请求世代及当前输入恢复修复。
- 提交 `36a3e0c3cd407eda988e32723526bafe4f8b64d5` 的 macOS Debug 编译及 43 项测试、4 个 suite 全部通过。包括 OCR 客户端、6 项本机接口集成测试和两组 Markdown 回归测试。
- CI：https://github.com/CalunVier/Easydict/actions/runs/39594077034 。集成 suite 实际执行而非跳过；已生成 arm64 Debug 应用。
- 合成 HTTP fixture 只验证协议与流程，不证明真实多模态模型的识别准确度；真实模型和手动 UI、Release/Intel、正式签名及公证未验证。
- 已获准新增测试、新分支推送与 GitHub Actions；验证将使用本机 HTTP fixture，不调用真实模型或使用用户凭据。

## 完成条件

- 实现及适用检查通过，明确记录真实服务和 UI 验证范围。
- 如无法执行实际服务验证，保持 active 并如实记录，不声明全面通过。
