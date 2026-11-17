# 坠井者

数值解谜 + 肉鸽的小游戏，横屏 16:9，计划发布微信 / 抖音小游戏和 Steam。

- 设计方案：[docs/game-design.md](docs/game-design.md)（Word 版：`docs/坠井者-游戏设计方案.docx`）

## 当前进度：M1 玩法原型

- 战斗公式固定、可预览：先攻、吸血、反伤、二连击
- 7×7 格子地图：墙、怪物、道具（血瓶、赤晶、青晶、骨钥、金币）、骨门、血门、出口
- 过关条件：走到出口即可，不用清怪；精英活着时出口被封住；只能往下走
- 出口结算：清层奖励、剩余血瓶换金币、可选卖掉骨钥
- 撤回（一次点击算一步）、重开本层、重新开始
- 求解器：算出每层的最优打法，用来检查关卡能不能过、难度合不合适
- 手工 3 层教学关
- 横屏网页试玩：点击和键盘都能玩

## 开发命令

```bash
npm install
npm run preview     # 浏览器试玩：http://localhost:8080
npm test            # 核心逻辑单元测试
npm run solve       # 每层的最优解 vs 贪心玩家，调关卡用
npm run typecheck
```

## 目录

```
src/core/     纯 TypeScript 核心逻辑（不依赖任何引擎，以后接 Cocos / Steam 版直接复用）
  config.ts   怪物、道具、角色数值
  combat.ts   战斗公式
  floor.ts    文字地图解析
  rules.ts    格子交互规则（游戏和求解器共用）
  game.ts     一局游戏的状态和操作
  solver.ts   求解器
  levels.ts   M1 手工关卡
web/          横屏网页试玩界面
tests/        单元测试
tools/        关卡检查工具
docs/         设计文档
```

## 怎么改关卡

关卡在 `src/core/levels.ts`，用文字画地图：

```
#  墙        .  空地      @  入口      >  出口
D  骨门      B  血门
k  骨钥      h  小血瓶    H  大血瓶    r  赤晶    b  青晶    $  金币袋
m  井苔      e  盲鳗      f  骨蛙      c  锈甲虫  v  回声蝠  g  溺魂  x  裂岩蟹  G  石鳞守卫
```

改完运行 `npm run solve`，看最优解剩多少血、和贪心玩家差多少，再运行 `npm test` 确认三层都能通关。
