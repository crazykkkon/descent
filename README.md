# 坠井者

> **Steam 版用 LÖVE + Lua 制作（`love/` 目录）**，TypeScript 原型（`src/core/`）作为规则参照和算例来源。
> LÖVE 安装包下载：https://github.com/crazykkkon/descent/releases/tag/love-latest

数值解谜 + 肉鸽游戏，横屏 16:9。只做 Steam 版（买断制）。

- 网页原型：https://crazykkkon.github.io/descent/ （停在井的契约版，不再更新）
- 设计方案：[docs/game-design.md](docs/game-design.md)（Word 版：`docs/坠井者-游戏设计方案.docx`）

## 当前进度：断臂转轮版（LÖVE 白盒）

- 开局界面（继续 / 开始 / 设置 / 退出）；第一次开始是 **5 层教学关卡**，第 5 层被井底之眼打死，醒来右臂变成一个空的**断臂转轮**
- **断臂转轮**：三个轮子各 5 格，刻图案（印记怪、精英三选一、当铺、大转盘、诏令）、擦图案，自己拉杆转武器；每局清空
- 地图 **16×11**，下一层有两个候选时地图上有两个出口，走哪个去哪层；出口只给一句不说破的话
- 设施层：大转盘、当铺、骨坛、营火；井神的诏令；第 9、17 层交井租；第 20 层井底之眼
- 规则写在 TypeScript 原型（`src/core/`），Lua 版用标准算例逐条对账；地图池导出到 `love/src/data/pools.lua`
- 详细规则和讨论项：设计方案第三～六章

## 开发命令

```bash
npm install
npm run preview     # 浏览器试玩：http://localhost:8080
npm test            # 核心逻辑单元测试
npm run solve       # 每张图的最优解 vs"赶路""清图"两种乱打，以及所有选图组合能否通关
npx tsx tools/fill.ts f2-ring 2500 1   # 内容搜索：在手画墙壁的内容格里找合适的怪物和奖励摆法
npm run typecheck
npm run vectors       # 从原型导出标准算例到 love/tests/vectors.lua
npm run love:test     # LÖVE 版用标准算例对账（需要 luajit）
npm run mainline      # 路线检查：每个种子按几种选法连续求解到井底
npm run love:build    # 打 Windows / Mac 安装包和 .love（输出到 love/dist/）
npm run build:demo  # 打包成单文件 demo/index.html，可放到任何静态网页托管，也能直接发给别人
```

## 目录

```
src/core/     纯 TypeScript 核心逻辑（不依赖任何引擎，Steam 版和以后的小游戏版直接复用）
  config.ts   怪物、道具、角色数值
  combat.ts   战斗公式
  floor.ts    文字地图解析
  rules.ts    格子交互规则（游戏和求解器共用）
  game.ts     一局游戏的状态和操作
  solver.ts   求解器
  intel.ts    楼梯口情报
  contract.ts 井的契约
  slot.ts     井中轮（老虎机）
  levels.ts   试玩版关卡：每层 3 布局 × 2 配置，选图和换图规则
  mainline.ts 20 层主线白盒（Lua 版的关卡数据从这里导出）
web/          横屏网页试玩界面
tests/        单元测试
tools/        关卡检查工具（solve.ts）、内容搜索工具（fill.ts）
docs/         设计文档
```

## 怎么改关卡

关卡在 `src/core/levels.ts`，每层 3 种布局，每种布局 2 套配置（墙壁必须一样），用文字画地图：

```
#  墙        .  空地      @  入口      >  出口
D  骨门      B  血门
k  骨钥      h  小血瓶    H  大血瓶    r  赤晶    b  青晶    $  金币袋
m  井苔      e  盲鳗      f  骨蛙      c  锈甲虫  v  回声蝠  g  溺魂  x  裂岩蟹  G  石鳞守卫
w  井鼠      u  盐蚀蛞蝓  p  骸骨祭司  K  守门人    E  井底之眼（占位）
S  井中轮·骨轮  T  井中轮·苔轮  M  补给摊
```

改完运行 `npm run solve`，看最优解剩多少血、和乱打的差多少、有没有开局白拿的奖励，再运行 `npm test` 确认所有组合都能通关。
