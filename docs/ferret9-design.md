# Ferret9 UI — Design direction

## Brief
本地凭据/配置纳管工具（母鼬 Ferret9）：专业、克制、像 macOS 原生「设置 + 钥匙串」类工具，而不是网页表单贴在窗口里。

## Inspiration (ui-ux-pro-max + frontend-design)
- **Pattern**: Master list (left, ~52%) + Inspector (right) — 先选条目，再编辑。
- **Tone**: Developer utility — 等宽路径/命令、清晰标签、单一点亮主色。
- **Color**: 琥珀 `#E8892A` 主操作（与 Icon 一致）；危险 `#D45D5D`；面板 `#F5F5F7` / 卡片 `#FFFFFF`；正文 `#1C1C1E`；辅助 `#6B6B70`。
- **Type**: SF Pro（系统默认）；路径/命令 `monospacedSystemFont` 11pt；标签 11pt semibold secondary；正文 13pt。
- **Spacing**: 8pt grid — 行间距 12pt，面板内边距 20pt，工具栏 14pt。
- **Avoid**: 中间大面积空白、保存钮乱飞、列表挤在 1/3 宽、全窗口默认灰按钮。

## Inspector fields (unchanged IA)
CLI · 说明(+保存) · 原始路径(+Finder) · 测试命令(+测试) · 删除

## Toolbar
仅「导入」为主按钮；右侧状态「已纳管 N 条」。
