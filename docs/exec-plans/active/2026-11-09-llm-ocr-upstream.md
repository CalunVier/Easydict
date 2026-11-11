# 将 LLM OCR 移植到最新上游

- 状态：active
- 创建日期：2026-11-09
- 负责人：Unknown
- 关联 Issue/PR：none

## 执行上下文

- **Agent Name:** `Eggy`
- **Model:** `Unknown`
- **Environment:** `macOS Unknown / Xcode Unknown (Unknown)`；实现环境为 Linux，macOS 验证交由 GitHub Actions。

## 背景

用户要求独立分支追平上游，只移植已有 LLM OCR，保留上游原生 Markdown。

## 目标与范围

- 目标结果：以 tisfeng/Easydict dev 9e0d7159f38ff7d3468b8622a633094436d654b4 为基线，移植 36a3e0c3 的 OCR。
- 允许修改路径：LLMOCR、DetectManager、OCR 控制器、设置、本地化、工程引用、专属测试及 CI。
- 同任务 history：`docs/histories/2026-11/2026-11-09-llm-ocr-upstream.md`
- 用户限制：使用 Linux，不使用用户 Mac；新分支推送到 CalunVier/Easydict，运行 GitHub Actions，不创建上游 PR。
- 非目标：旧分支的 RichMarkdownView、MarkdownResources 及其他 Markdown 替换实现。
- 验收标准：OCR 专属测试与上游 Markdown 测试通过，未修改上游 Markdown 实现。

## 工作计划

1. 确认并冻结最新 upstream/dev。
2. 移植 OCR，适配工程引用和上游错误处理。
3. 静态检查、只读审查、推送独立分支及运行 macOS CI。
4. 记录结果和验证限制。

## 风险与决策

- 保留默认 Apple OCR；只有开启 LLM OCR 才发送图片。
- 沿用本地 HTTP fixture，不调用真实供应商、不使用用户密钥。
- Linux 无法执行 Xcode 或 macOS 界面截图，明确区分 CI 和人工验证。

## 进度

- [x] 冻结上游基线。
- [x] 移植 OCR 与工程引用。
- [x] 本地静态检查。
- [x] 独立代码审查：无确认缺陷。
- [ ] 推送新分支和 macOS CI。

## 验证

- `git diff --check` 通过。
- 本地化 JSON、21 个 OCR key 的七语言覆盖及上游 key 保持不变检查通过。
- 工程 UUID 唯一性、六个 Swift 文件引用与 Sources 检查通过。
- Python fixture 编译检查通过。
- macOS 编译、测试、人工 UI 和真实模型准确率尚未验证。

## 完成条件

- 完成代码审查与准确提交的 macOS CI，并记录任何未验证项。

- 2026-11-11：上游新增流式 OCR 后重新适配，仅在服务选择边界增加可选 LLM adapter；保留上游 DetectManager 与控制器状态逻辑，并运行其 OCRStreamingTests。补充乌尔都语。
