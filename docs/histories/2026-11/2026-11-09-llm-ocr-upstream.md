## 2026-11-09 | 任务：将 LLM OCR 移植到最新上游

**Links:** [进行中的计划](../../exec-plans/active/2026-11-09-llm-ocr-upstream.md)

### 执行上下文

- **Agent Name:** `Eggy`
- **Model:** `Unknown`
- **Environment:** `macOS Unknown / Xcode Unknown (Unknown)`；Linux 实现，macOS CI 待执行。

### 用户请求

创建独立分支追平上游，只移植 LLM OCR 并保留上游 Markdown，不创建上游 PR。

### 变更

- 基于 tisfeng/Easydict dev 9e0d7159f38ff7d3468b8622a633094436d654b4 创建 feat/llm-ocr-upstream。
- 移植原 fork 36a3e0c3 的 OCR 模块、设置、21 个本地化 key、请求取消与过时结果保护。
- 适配上游工程引用和已移动的 OCR 错误处理；没有带入旧 Markdown 实现或测试。
- 保留原 OCR 离线测试与 loopback fixture，CI 选择 OCR suites 和上游 MarkdownRendererTests。

### 设计意图

从干净上游基线移植单一功能，避免旧分支 Markdown 替换实现覆盖上游改进。默认仍为 Apple OCR；远程 OCR 只转录原文并交给现有翻译流程。

### 验证

- `git diff --check`：通过。
- 本地化 JSON、七语言覆盖及原上游 key 保持不变：通过。
- 工程 UUID 唯一性、六个 Swift 文件注册及 Sources 引用：通过。
- 工作流 YAML 解析和 `bash -n`：通过。
- Python fixture 编译及 success、HTTP 503、delay/release 检查：通过；不是 Swift 服务实测。
- 独立只读代码审查：无确认缺陷。
- 上游 Markdown 文件差异：无。
- Xcode 编译、Swift suites、macOS UI/截图及真实模型识别准确率：未运行。

### 受影响文件

- `Easydict/Swift/Service/LLMOCR/`
- `Easydict/Swift/Model/DetectManager.swift`
- `Easydict/Swift/View/SettingView/Tabs/TabView/AdvancedTab.swift`
- `Easydict/objc/ViewController/Window/BaseQueryWindow/EZBaseQueryViewController.m`
- `Easydict/App/Localizable.xcstrings`
- `Easydict.xcodeproj/project.pbxproj`
- `EasydictTests/Service/LLMOCR/`
- `.github/workflows/llm-ocr.yml`

### 后续事项

- 推送新分支后检查准确提交的 macOS CI；不可沿用旧分支的通过结果。
- Linux 无法提供 macOS UI 实测截图；真实模型验证需要明确授权的供应商及凭据。

- 2026-11-11：上游新增流式 OCR 后重新适配，仅在服务选择边界增加可选 LLM adapter；保留上游 DetectManager 与控制器状态逻辑，并运行其 OCRStreamingTests。补充乌尔都语。
