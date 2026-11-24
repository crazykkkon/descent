<!-- 和 CLAUDE.md 内容一致，给 Codex 等其他 AI 助手读。改规则时两份一起改。 -->
# 《坠井者》工作须知

## 开工前必须先读最新的制作交接稿

每次做《坠井者》相关的工作（写代码、改关卡、调数值、改设计方案）之前：

1. 拉取 `crazykkkon/xiaochengxu` 的**默认分支**（用 `git remote show origin` 查默认分支名，不要假设是 main）。
2. 在默认分支的 `docs/` 目录里找文件名包含"交接稿"的文档；有多份时，以**最近一次提交**的为准（`git log --format='%h %ad' -- 'docs/*交接稿*'`）。
3. 读全文（Word 文档可以用 `pandoc 文件.docx -t markdown` 转成文字）。
4. 按下面的规则使用它。

### 怎么对待交接稿里的内容
- **标为"已确认"的**：以此为准，直接按它做。
- **标为"沿用原案"的**：是原方案里早已定下的内容，同样按定论处理。
- **其余所有内容**（建议、待验证、评审意见、具体层位、价格、节奏、规格等）：**只作为讨论项**，不能当成已经决定的事。要采纳时先和制作人确认。
- 交接稿、设计方案（`docs/game-design.md`）和现有代码之间有冲突时，不要自己选边，列出冲突让制作人决定。
- 制作人在对话里表达过倾向、但交接稿没标"已确认"的事，记成"讨论项（制作人倾向：……）"。

## 分工
- Codex 主要负责《坠井者》的美术，包括像素素材、场景表现、实机可读性和美术交接。

## 当前技术路线
- Steam Demo：**LÖVE（Love2D）+ Lua**（交接稿 a9ca98b 已确认）。
- `src/core/` 的 TypeScript 原型是规则的参照实现：Lua 版要用同一组输入逐条对账（战损、断臂转轮、大转盘、当铺、骨坛、诏令、路线、存档）。
- 求解器和设计工具继续用 TypeScript（制作人倾向）；Lua 代码在 `love/` 目录（制作人倾向）。
- 只做 Steam，按电脑分辨率；不做小程序（制作人倾向）。试玩发 Windows / Mac 安装包（制作人倾向）。
- 改了 `src/core/` 的规则：先改原型 → `npm test` → `npm run vectors` 重新导出算例 → 改 `love/src/core/` → `npm run love:test` 必须 0 条不一致。

## 仓库要点
- 设计方案：`docs/game-design.md`（Word 版同目录）；`crazykkkon/xiaochengxu` 的 `docs/descent/` 里有一份同步副本。
- 核心规则是纯 TypeScript（`src/core/`），游戏和求解器共用同一份规则；改规则后跑 `npm test`。
- 关卡检查：`npm run solve`；路线检查：`npm run mainline`；内容搜索：`tools/fill.ts`。
- 当前玩法是**断臂转轮版**（设计方案第二十五章）：井的契约、楼梯口情报、井中轮老虎机、武器格已去掉。
- 画面方向（制作人定）：**A · 斜俯视立体 + 机械臂转轮**（设计方案 25.6）。
- 推送到 `main` 会自动发布 LÖVE 安装包：https://github.com/crazykkkon/descent/releases/tag/love-latest 。网页原型（https://crazykkkon.github.io/descent/ ）从断臂转轮版起不再更新，只能手动发布。
- LÖVE 版本地运行：`cd love && love .`；无界面自检：`DESCENT_AUTOTEST=1 xvfb-run -a love .`（先走新手教程，再用强角色走完 20 层；截图在 ~/.local/share/love/descent/）。地图池由原型导出到 `love/src/data/pools.lua`，不要手改。
