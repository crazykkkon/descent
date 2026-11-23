-- 由 tools/export-vectors.ts 从 src/core/mainline.ts 自动生成，不要手改。
-- 20 层主线白盒：每层的参数、布局和配置。intelPick 的格子下标已经换成 Lua 的 1 开始。
-- 层位、地图、数值、井租、补给摊价格都是讨论项（见 src/core/mainline.ts 开头的说明）。
return {
  pools = {
    {
      params = {
        gem = 2,
        smallPotion = 50,
        bigPotion = 150,
        gold = 20,
        name = "第 1 层 · 井口",
        hint = "怪物格子上的数字是打它要掉的血。不用清怪，走到出口就行；奖励都在怪物身后，值不值得打，自己算。",
        bloodCost = 40
      },
      layouts = {
        {
          name = "两条路",
          variants = {
            {
              map = { "..m.r#...", ".#####.#.", "@...e...>", ".###.###.", ".#b.m#h..", ".#####.#.", "....m...." },
              intelPick = {
                cell = 59,
                mustFight = false
              }
            },
            {
              map = { "..m.b#.h.", ".#####.#.", "@...e...>", ".###.###.", ".#r.m#...", ".#####.#.", "....m..m." },
              intelPick = {
                cell = 59,
                mustFight = false
              }
            }
          }
        },
        {
          name = "回廊",
          variants = {
            {
              map = { "@...e....", ".###.###.", ".#r...b#.", ".##...##.", "..m.#.m..", ".#######e", "...m.h.e>" },
              intelPick = {
                cell = 62,
                mustFight = false
              }
            },
            {
              map = { "@...m....", ".###.###.", ".#b.$..#.", ".##...##.", "..e.#.m..", ".#######m", "...m.r.e>" },
              intelPick = {
                cell = 5,
                mustFight = false
              }
            }
          }
        },
        {
          name = "侧室",
          variants = {
            {
              map = { "#r#h..#b#", "#m###e#e#", "#.#...#.#", "@.....e.>", "#.#.#.###", "#e#D#m..#", "#k#h#..h#" },
              intelPick = {
                cell = 34,
                mustFight = true
              }
            },
            {
              map = { "#b#...#r#", "#e###m#m#", "#.#...#.#", "@.....e.>", "#.#.#.###", "#m#D#m..#", "#k#h#..h#" },
              intelPick = {
                cell = 34,
                mustFight = true
              }
            }
          }
        }
      }
    },
    {
      params = {
        gem = 2,
        smallPotion = 50,
        bigPotion = 150,
        gold = 20,
        name = "第 2 层 · 苔壁",
        hint = "如果签了契约：喝下任何一瓶血瓶都会毁约，押金不退。",
        bloodCost = 60
      },
      layouts = {
        {
          name = "侧厅",
          variants = {
            {
              map = { "@.....f...>", "##.#.######", "hv.#.vh####", "####.######", "####m..r###", "###########", "###########" },
              contract = {
                condition = "noPotion",
                deposit = 50,
                atk = 3,
                def = 0,
                refund = 60,
                gold = 10
              },
              intel = "下一层有两瓶血瓶。"
            }
          }
        },
        {
          name = "长廊",
          variants = {
            {
              map = { "@.h.f.H.v.>", ".##.#.#.###", ".m..#.e.###", "###########", "###########", "###########", "###########" },
              contract = {
                condition = "noPotion",
                deposit = 50,
                atk = 3,
                def = 0,
                refund = 60,
                gold = 10
              },
              intel = "下一层有两瓶血瓶。"
            }
          }
        },
        {
          name = "双道",
          variants = {
            {
              map = { "@.e.h.e.h.>", ".#########.", ".....e...f.", "#m#########", "#r#########", "###########", "###########" },
              contract = {
                condition = "noPotion",
                deposit = 50,
                atk = 3,
                def = 0,
                refund = 60,
                gold = 10
              },
              intel = "下一层有两瓶血瓶。"
            }
          }
        }
      }
    },
    {
      params = {
        gem = 2,
        smallPotion = 50,
        bigPotion = 150,
        gold = 20,
        bloodCost = 80,
        name = "第 3 层 · 回声",
        hint = "井壁边有个补给摊，站到旁边就能买。回声蝠会先打你一下。",
        stall = {
          {
            id = "hp",
            amount = 80,
            price = 25
          },
          {
            id = "atk",
            amount = 2,
            price = 40
          },
          {
            id = "def",
            amount = 2,
            price = 40
          }
        }
      },
      layouts = {
        {
          name = "主线",
          variants = {
            {
              map = { "@..f.#B..h.", ".M##.#.###.", ".#v.D....#>", ".#.###k#.#.", "...#r..#...", "##v#.###.#.", "h..f.....bb" },
              intelPick = {
                cell = 58,
                mustFight = false
              }
            }
          }
        }
      }
    },
    {
      params = {
        gem = 2,
        smallPotion = 50,
        bigPotion = 150,
        gold = 20,
        name = "第 4 层 · 鳞厅",
        hint = "石鳞守卫封住了出口，它每回合打你两下。先把前面三条小道里的宝石拿到手，再去打它。",
        bloodCost = 60,
        eliteReward = true
      },
      layouts = {
        {
          name = "三道",
          variants = {
            {
              map = { "@.m.r.e.h", ".#######.", ".v.b.f.$.", ".#######.", ".c.$...e.", "####G####", "####>####" },
              intelPick = {
                cell = 50,
                mustFight = true
              }
            },
            {
              map = { "@.v.b.e.$", ".#######.", ".m.r.f.h.", ".#######.", ".e.$...c.", "####G####", "####>####" },
              intelPick = {
                cell = 50,
                mustFight = true
              }
            }
          }
        }
      }
    },
    {
      params = {
        gem = 2,
        smallPotion = 40,
        bigPotion = 100,
        gold = 25,
        bloodCost = 80,
        name = "第 5 层 · 暗河",
        hint = "井鼠挤在一起时更凶：每有一只相邻的井鼠，攻击 +5。先打边上落单的。"
      },
      layouts = {
        {
          name = "主线",
          variants = {
            {
              map = { "@....#.wwr.", ".###.#.w##.", ".#h......#.", ".#.##.##.#.", ".e.#..ww.#.", ".###...w.#.", "....v.#..f>" },
              intelPick = {
                cell = 46,
                mustFight = false
              }
            }
          }
        }
      }
    },
    {
      params = {
        gem = 2,
        smallPotion = 40,
        bigPotion = 100,
        gold = 25,
        bloodCost = 80,
        name = "第 6 层 · 盐窟",
        hint = "盐蚀蛞蝓每打中你一下，你这一仗的防御就 −1。攻击越高，打得越快越省血。"
      },
      layouts = {
        {
          name = "主线",
          variants = {
            {
              map = { "@..k.#..u.$", ".###.#.####", ".#e..D....h", ".#.#####.#.", ".c.#u.b#.#.", ".#.#.###.#.", "...f.....x>" },
              intelPick = {
                cell = 46,
                mustFight = false
              }
            }
          }
        }
      }
    },
    {
      params = {
        gem = 2,
        smallPotion = 40,
        bigPotion = 100,
        gold = 25,
        bloodCost = 80,
        name = "第 7 层 · 骨龛",
        hint = "骸骨祭司让相邻的怪物防御 +6。先拆祭司，还是硬闯？"
      },
      layouts = {
        {
          name = "主线",
          variants = {
            {
              map = { "@...e..#..h", ".#####.#.#.", ".#r..B.p..h", ".#.####x###", ".....g...f.", ".###.#.###.", "h..m.#...v>" },
              intelPick = {
                cell = 50,
                mustFight = false
              }
            }
          }
        }
      }
    },
    {
      params = {
        gem = 2,
        smallPotion = 40,
        bigPotion = 100,
        gold = 25,
        bloodCost = 80,
        name = "第 8 层 · 绳桥",
        hint = "下一层的出口要交井租。金币不够就得拿攻击或防御抵。"
      },
      layouts = {
        {
          name = "主线",
          variants = {
            {
              map = { "@.e.$#..h..", ".###.#.###.", "...v...w.w>", "###########", "###########", "###########", "###########" },
              intelPick = {
                cell = 3,
                mustFight = false
              }
            }
          }
        }
      }
    },
    {
      params = {
        gem = 2,
        smallPotion = 40,
        bigPotion = 100,
        gold = 25,
        bloodCost = 80,
        rent = 120,
        name = "第 9 层 · 收租口",
        hint = "出口要交井租。血门近路省战力，多打一场能凑金币。"
      },
      layouts = {
        {
          name = "主线",
          variants = {
            {
              map = { "@..f..$..g.", ".#####.###.", ".B.......#.", ".#.#####.#.", ".#..$..c.#.", ".#######.#.", "...w.w...$>" },
              intelPick = {
                cell = 52,
                mustFight = false
              }
            }
          }
        }
      }
    },
    {
      params = {
        gem = 2,
        smallPotion = 50,
        bigPotion = 120,
        gold = 30,
        bloodCost = 100,
        eliteReward = true,
        name = "第 10 层 · 断绞盘",
        hint = "石鳞守卫身边站着一只骸骨祭司。先拆祭司，还是直接打被庇护的守卫？"
      },
      layouts = {
        {
          name = "主线",
          variants = {
            {
              map = { "@..b.#..h..", ".###.#.###.", ".#h..e...#.", ".#.#####.#.", ".c...up..#.", ".#####G.##.", "######>####" },
              intelPick = {
                cell = 62,
                mustFight = true
              }
            }
          }
        }
      }
    },
    {
      params = {
        gem = 2,
        smallPotion = 50,
        bigPotion = 120,
        gold = 30,
        bloodCost = 100,
        name = "第 11 层 · 旧泵室",
        hint = "一台井中轮，一个补给摊。钱换属性，还是赌一把武器？",
        stall = {
          {
            id = "hp",
            amount = 150,
            price = 40
          },
          {
            id = "atk",
            amount = 3,
            price = 70
          },
          {
            id = "def",
            amount = 3,
            price = 70
          }
        }
      },
      layouts = {
        {
          name = "主线",
          variants = {
            {
              map = { "@...$.....>", ".##S#M##.#.", ".....e..h..", "###########", "###########", "###########", "###########" },
              intelPick = {
                cell = 28,
                mustFight = false
              }
            }
          }
        }
      }
    },
    {
      params = {
        gem = 2,
        smallPotion = 50,
        bigPotion = 120,
        gold = 30,
        bloodCost = 100,
        name = "第 12 层 · 双井道",
        hint = "下一层的契约押得更多，给得也更多。"
      },
      layouts = {
        {
          name = "主线",
          variants = {
            {
              map = { "@.w..#..x.h", ".#w#.#.###.", ".#r#...g...", ".#.#####.#.", ".v...k...#.", ".#####D###.", "h....u....>" },
              intelPick = {
                cell = 46,
                mustFight = false
              }
            }
          }
        }
      }
    },
    {
      params = {
        gem = 2,
        smallPotion = 50,
        bigPotion = 120,
        gold = 30,
        bloodCost = 100,
        name = "第 13 层 · 蓄水窖",
        hint = "如果签了契约：喝下任何一瓶血瓶都会毁约。"
      },
      layouts = {
        {
          name = "主线",
          variants = {
            {
              map = { "@.H.u.h...>", ".####.####.", ".x..g..w.w.", ".#########.", ".b..m..$...", "###########", "###########" },
              contract = {
                condition = "noPotion",
                deposit = 120,
                atk = 5,
                def = 0,
                refund = 150,
                gold = 30
              },
              intel = "下一层的近路上有三瓶血瓶。"
            }
          }
        }
      }
    },
    {
      params = {
        gem = 2,
        smallPotion = 50,
        bigPotion = 120,
        gold = 30,
        bloodCost = 100,
        name = "第 14 层 · 锈栅",
        hint = "用骨钥绕开被庇护的蛞蝓，还是先拆掉祭司？"
      },
      layouts = {
        {
          name = "主线",
          variants = {
            {
              map = { "@..k.#.p.$.", ".###.#.u##.", ".#$.D......", ".#.#####.#.", ".w.w...g.#.", ".#####.###.", ".....h...x>" },
              intelPick = {
                cell = 52,
                mustFight = false
              }
            }
          }
        }
      }
    },
    {
      params = {
        gem = 2,
        smallPotion = 60,
        bigPotion = 150,
        gold = 40,
        bloodCost = 120,
        name = "第 15 层 · 裂石廊",
        hint = "（落石教学还没做，这一层先是一条短廊。）"
      },
      layouts = {
        {
          name = "主线",
          variants = {
            {
              map = { "@...r...w.>", ".#########.", "...h...u...", "###########", "###########", "###########", "###########" },
              intelPick = {
                cell = 9,
                mustFight = false
              }
            }
          }
        }
      }
    },
    {
      params = {
        gem = 2,
        smallPotion = 60,
        bigPotion = 150,
        gold = 40,
        bloodCost = 120,
        name = "第 16 层 · 回声库",
        hint = "下一层的出口要交第二次井租。"
      },
      layouts = {
        {
          name = "主线",
          variants = {
            {
              map = { "@..g..$.$..", ".#########.", ".k.D..x..h.", ".#########.", "..u..b..w.w", "##########.", "##########>" },
              intelPick = {
                cell = 55,
                mustFight = true
              }
            }
          }
        }
      }
    },
    {
      params = {
        gem = 2,
        smallPotion = 60,
        bigPotion = 150,
        gold = 40,
        bloodCost = 120,
        rent = 250,
        name = "第 17 层 · 抵押厅",
        hint = "出口要交第二次井租。"
      },
      layouts = {
        {
          name = "主线",
          variants = {
            {
              map = { "@..x...u..$", ".#####.###.", ".h..p.g...$", ".#.#####.#.", ".w...r...#.", ".#.#####.#.", ".....$...u>" },
              intelPick = {
                cell = 29,
                mustFight = false
              }
            }
          }
        }
      }
    },
    {
      params = {
        gem = 2,
        smallPotion = 60,
        bigPotion = 150,
        gold = 40,
        bloodCost = 120,
        name = "第 18 层 · 井底营火",
        hint = "最后一个补给摊。下一层是守门人和两只骸骨祭司。",
        stall = {
          {
            id = "hp",
            amount = 200,
            price = 50
          },
          {
            id = "atk",
            amount = 4,
            price = 100
          },
          {
            id = "def",
            amount = 4,
            price = 100
          }
        }
      },
      layouts = {
        {
          name = "主线",
          variants = {
            {
              map = { "@...h...H..", ".###M###...", "..........>", "###########", "###########", "###########", "###########" }
            }
          }
        }
      }
    },
    {
      params = {
        gem = 2,
        smallPotion = 60,
        bigPotion = 150,
        gold = 40,
        bloodCost = 120,
        eliteReward = true,
        name = "第 19 层 · 守门",
        hint = "守门人两边各一只骸骨祭司（庇护不叠加）。先拆祭司，还是直接挑战？"
      },
      layouts = {
        {
          name = "主线",
          variants = {
            {
              map = { "@..r..b..h.", ".#########.", ".u..w.w..u.", ".###...###.", ".###pKp###.", "#####.#####", "#####>#####" },
              intelPick = {
                cell = 49,
                mustFight = false
              }
            }
          }
        }
      }
    },
    {
      params = {
        gem = 2,
        smallPotion = 60,
        bigPotion = 150,
        gold = 40,
        bloodCost = 120,
        name = "第 20 层 · 井底之眼",
        hint = "（Boss 站位战还没做，先是一场确定的战斗。）"
      },
      layouts = {
        {
          name = "主线",
          variants = {
            {
              map = { "@...h.h...b", ".#########.", ".g.r.E.r.g.", ".####.####.", ".####>####.", "###########", "###########" },
              intelPick = {
                cell = 28,
                mustFight = true
              }
            }
          }
        }
      }
    }
  }
}
