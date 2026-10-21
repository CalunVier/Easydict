# 完善翻译结果 Markdown 渲染

- 状态：active
- 创建日期：2026-10-21
- 负责人：Unknown
- 关联 Issue/PR：none

## 执行上下文

- **Agent Name:** `Unknown`
- **Model:** `Unknown`
- **Environment:** `macOS Unknown / Xcode Unknown (Unknown)`

## 背景

现有原生文本渲染器不支持表格与数学公式，且缺少完整 Markdown 解析。
当前执行环境为 Linux，不能进行 AppKit / Xcode 验证。

## 目标与范围

- 目标结果：离线、模块化的 GFM 风格 Markdown 与 KaTeX 公式渲染，保留纯文本切换。
- 允许修改路径：Markdown 功能目录、结果视图集成、Xcode 工程与相关文档。
- 同任务 history：`docs/histories/2026-10/2026-10-21-rich-markdown-rendering.md`
- 用户限制：未经逐项许可不调用 Codex；已获准新增测试、推送独立分支并触发 GitHub Actions；不改 dev、不创建上游 PR、不使用用户 Mac。
- 非目标：图片直译、OCR 路径改动、任意 HTML 执行、远程资源加载、完整 TeX 引擎。
- 验收标准：表格、行内与块公式、流式更新、暗色模式、安全链接、可复制文本、布局更新均正常；常规翻译不回归。

## 工作计划

1. 固定依赖版本并构建离线 web 资源，记录许可证。
2. 实现独立 WebKit 容器、消息桥和内容安全策略。
3. 小范围集成到现有结果视图，保留文字路径和词典 HTML 隔离。
4. 执行适用检查与审查；在 GitHub 托管 macOS runner 完成编译与测试后再评估交付；真实交互验证仍需明确报告。

## 风险与决策

- 使用成熟解析器代替继续扩展正则解析；web 资源离线打包，不依赖 CDN。
- 模型输出不可信：禁用原始 HTML，清理输出，限制 URL，禁止远程资源与网页导航。
- WebKit 高度异步变化与结果复用必须隔离，流式更新不得重载文档。
- macOS 验证为交付阻塞项；Linux 检查不能替代。

## 进度

- [x] 确认当前结果渲染与高度更新调用链。
- [x] 离线渲染资源与模块实现。
- [x] 结果视图集成；渲染视图由查询结果持有以支持列表单元复用。
- [ ] 检查、审查与 macOS 验证。

## 验证

- 初始工作树干净，基线 b4eced749d492d283f451f88e5504413e4533f44。
- Node 解析器及缓存测试：14/14 通过；DOM 清理、增量复用及注入边界测试：9/9 通过。
- 资源构建、JavaScript 语法和 `git diff --check` 通过；运行时 npm audit 未报告已知漏洞。
- GitHub Actions 验证提交 `616fe7bf6ec67511aebea2ec725ee1fdeff98fb1`：14 项解析/缓存、9 项 DOM、9 项 Chromium 回归检查通过，离线资源一致性检查通过。
- 同次 macOS Debug 编译及 26 项原生测试全部通过，包括 3 项实际 WebKit 桥接测试。运行记录：https://github.com/CalunVier/Easydict/actions/runs/39572548693 。
- CI 修复记录：更正 WebKit 回调重载参数标签；测试变量避开 Swift 的 unsafe 语法；高度测试使用实际窗口并等待 DOM 与原生高度收敛，未降低断言。
- 流式优化：有界公式缓存、保持相同位置的不变 DOM 块；修复 texmath 字符串替换误解释公式中的美元符号模式。仍执行完整 Markdown 解析和清理，不声称完全增量渲染。
- 初次只读审查发现的降级内容滚动与选词路由问题已修复；后续复核增加查询重置及单元复用时的视图所有权检查。
- 已生成 ad-hoc 签名的 arm64 Debug 应用，未做正式发布签名、公证或 Release/Intel 构建。真实使用场景的手动交互验证未完成，计划保持 active，不声明可合并。

## 完成条件

- 实现、适用回归检查与代码审查完成。
- Xcode 编译及 Mac 实机交互验证完成；否则保持 active 并记录阻塞。
