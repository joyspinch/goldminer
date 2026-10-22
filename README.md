# 黄金矿工 · GOLDMINER

> 钩子自动摆动，点击放钩；规定时间内挖满目标金额即过关，关卡目标逐关递增。

用 [Zan](https://github.com/joyspinch/zan-lang) 语言写的独立游戏项目（仓库根自带 git 仓库）。完整设计与实现说明见 [`PROJECT.md`](PROJECT.md)。

## 玩法

- 钩子自动摆动，点击 / 空格 / 下键 / 触屏点按 放钩
- 规定时间内挖满目标金额即过关，关卡目标逐关递增
- 刺激机制：
  * 连击 FEVER：3 秒内连续回收有价物，倍率 x1.1 → 最高 x2，抓到垃圾清零
  * 收线 QTE：拉重物时出现白圈，白圈缩到金圈时点击 = 立即加速（连击有奖励）
  * 抓到炸弹：环形倒计时内连点炸药图标（中心变大爆炸清屏，失败炸自己 -100）
  * TNT 连锁：炸掉周围物品，收益归零，屏幕震动
  * 最后 10 秒：红字警报 + 心跳音 + 边框闪烁
- 物品：金块大中小 / 钻石 / 宝箱 / 神秘袋（开出随机物）/ 石头 / 骷髅
  / TNT / 炸弹 / 金币袋

- 鼠标点击 / 空格 / ↓ / 回车 / 触屏点按   放钩、QTE 节拍点
- Q / E                 使用（消耗）炸药：钩住重物拉不动时直接炸掉
- Esc                   结算画面退出（存档）；关窗即存档退出

## 构建

需要 [zan-lang](https://github.com/joyspinch/zan-lang) 仓库（`zanc` 编译器、公共包与 stdlib 都在里面）：

```powershell
git clone https://github.com/joyspinch/zan-lang.git
$env:ZAN_HOME = 'D:/path/to/zan-lang'   # 指到刚克隆的 zan-lang 仓库根

pwsh -File client/tools/build.ps1
```

产物：`build/goldminer/GoldMiner.exe`（运行目录要带上它旁边的 `assets/` 与 `skins/`）。

## 运行

```powershell
cd build/goldminer
.\GoldMiner.exe
```

## 测试

```powershell
pwsh -File client/tools/test.ps1
```

## 目录结构

```
goldminer/
client/
  src/      # 游戏源码（.zan 源码 + HTML 界面设计稿）
  assets/   # 位图 / 音频素材
  tests/    # 玩法断言用例
  tools/    # 构建与测试脚本
PROJECT.md
```

## 素材与授权

- 素材清单与授权说明见 [`client/ASSETS.md`](client/ASSETS.md)。

## 许可

本仓库采用 [MIT 许可](LICENSE)。依赖的 zan-lang 仓库采用 ZCSL（Zan Community Source License 1.0）。

## 更多文档

- [`PROJECT.md`](PROJECT.md) —— 完整设计与实现说明
- [`client/README.md`](client/README.md) —— 客户端侧说明
- [`client/ASSETS.md`](client/ASSETS.md) —— 素材清单
