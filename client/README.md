zan Gold Miner — 黄金矿工（模板版）
====================================

玩法
----
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

操作
----
- 鼠标点击 / 空格 / ↓ / 回车 / 触屏点按   放钩、QTE 节拍点
- Q / E                 使用（消耗）炸药：钩住重物拉不动时直接炸掉
- Esc                   结算画面退出（存档）；关窗即存档退出

手机上玩
--------
```bash
pwsh -File client/tools/build.ps1 -ZancArgs '--publish','--target','android-arm64','--emit-apk','goldminer.apk','--apk-package','com.example.goldminer','--apk-label','黄金矿工'
```
`--publish` 会把 assets/ 内嵌进 libmain.so（磁盘优先、内嵌兜底的加载
逻辑不变），APK 直装手机即可；横竖屏都能玩——设计分辨率 960×720 经
等比铺满，竖屏上下留黑边，点按屏幕任意位置即放钩。

界面架构
--------
GuiHost 版（Game.Foundation.Gui）：窗口/事件/呈现由 packages/Zan.Gui/src/Gui 原生
外壳承担，不依赖 SDL。全部画面走 Canvas 直绘：

- 场景层（src/main.zan 的 DrawAll）：背景、矿工、抓钩（手绘美术 + 离线
  烘焙的方向帧）、物品、粒子、飘字、QTE 圈，经 Game.Kit 的
  CDraw/CText 绘制；
- HUD 层（DrawFallbackHud）：顶栏（关卡、金币进度、厘秒倒计时、连击、
  炸药）与拆弹面板，面板一律**美术底板 + 九宫格自切**
  （src/GoldminerPaint.zan），文字带描边，压在亮岩层上也读得清；
- 皮肤包（assets/skins/goldminer/skin.css）：结算页的标准库控件
  （按钮/文本）走皮肤，不留系统默认外观；启动时
  `UseSkin("dark")` → `UseSkin("goldminer")`（src/Scenes/MnRouter.zan）；
  控件基线与 dark 底座由编译器自动内嵌，磁盘上不再手工拷；
- 音频：System.Audio 原生驱动（AudioClip）；打开失败自动哑火，
  不影响运行。

朝向
----
引擎运行时转不了图（Canvas.BlitImage 只有源矩形，没有旋转也没有水平
翻转），所以钩子的 12 个方向帧与矿工的左右两帧都是**离线烘焙**好的
精灵表，运行时按摆角取帧（纯函数 `src/GoldminerFacing.zan`）。钩头
方向、矿工朝向、抓取判定点、绳头位置四处用的是同一套几何口径
（详见 [ASSETS.md](ASSETS.md)）。

构建
----
根目录下（公共包在 zan-lang 仓库的 packages/ 下，编译要带 --package-project）：

    pwsh -File client/tools/build.ps1

`--package-project` 默认指**主仓库** `D:\project\zan-lang`（只读）；要换用
别的包根就显式传 `-PackageProject <路径>`。**不要为公共包建 git worktree
副本**——副本停在旧 commit 上，公共包一改就跟不上（曾经因此白干一轮）。

产物在 build/goldminer/，运行所需 DLL 与 assets/ 一并落在同目录。
手动编译（同样在根目录下）：

    $env:ZAN_HOME/build/zanc.exe client/src/main.zan --auto-stdlib --package-project $env:ZAN_HOME -o build/goldminer/GoldMiner.exe

独立 exe 发布（单文件、免第三方 DLL、双击无控制台窗口）
------------------------------------------------
加 `--publish --link-mode static --subsystem windows`，并设为 GUI
子系统（不弹控制台）；`--subsystem windows` 必须显式给，zanc 命令行
默认 console 子系统（IDE 会对 GUI 项目自动加，CLI 不探测）：

    $env:ZAN_HOME/build/zanc.exe client/src/main.zan --auto-stdlib --package-project $env:ZAN_HOME --publish --link-mode static --subsystem windows -o build/goldminer/GoldMiner.exe

素材
----
assets/ 下全部 PNG/JPG/WAV 均可替换；编译时整个目录自动内嵌进
exe。运行时先读 exe 旁的 assets/（磁盘优先，替换即生效），没有
磁盘副本就直接从 exe 镜像里读内嵌字节进内存（File.ReadAllBytes →
LoadImageFromMem / LoadWavFromMem），全程不落盘，单文件分发也
出声出图。
IDE「新建项目」复制本模板后 assets/ 与 src/ 同级，同样自动内嵌，
无需额外参数。
注意：自动内嵌靠"入口源文件的目录"定位 assets/，所以命令行里要
写带目录的入口路径（如上）；在项目根目录下裸写 `zanc main.zan`
时编译器只能看到 `.`，会定位不到 assets/——换绝对路径或带
`src\` 前缀即可。

素材的**统一命名 / 缩放 / 量化 / 朝向帧烘焙**由
`client/tools/bake_assets.py` 负责（总量 589.6 KB）；原图不入库，
管线与尺寸口径见 [ASSETS.md](ASSETS.md)。

皮肤：控件基线 `base.css` 与 `dark` 底座由**编译器自动内嵌**（磁盘上不再
手工拷——`Skin.BaseCss()` 是磁盘优先、内嵌兜底）；本游戏的皮肤包由构建脚本
按单文件规格 `--embed` 烤成 `skins/goldminer/skin.css`（单文件发布也带着
皮肤），同时在 `build/goldminer/skins/goldminer/` 留一份磁盘副本供改 CSS
不用重编。自检跑 `GoldMiner.exe skin-probe`。

文件
----
- src/main.zan    入口 + 场景渲染/输入/兜底 HUD/无头自测
                  （MINER_SIM=1 平衡仿真，不建窗口）
- src/World.zan    核心玩法：摆钩、抓取、物品表、连击/QTE/炸弹、关卡与存档
- src/GoldminerFacing.zan  朝向纯函数：摆角 → 精灵表帧号
- src/GoldminerPaint.zan    画布美术底板（九宫格自切）+ 描边文字
- src/GoldminerPalette.zan  项目色板（与皮肤包令牌一一对应）
- src/Scenes/MnRouter.zan   场景路由（启动时套皮肤包）
- tools/bake_assets.py      素材流水线（统一命名/瘦身/朝向帧/UI 底板）
- tests/goldminer_test.zan  玩法断言用例（纯逻辑，不建窗口/不开音频）
- zan.proj        IDE 项目文件（IDE「新建项目 → 游戏」可直接套用）；
                  type = gui——这是窗口程序，IDE 按 gui 工程给窗口子系统与驱动路径
                  （写成 console 的话 IDE 侧当控制台程序处理，窗口与皮肤都不对）

测试
----
```powershell
pwsh -File client/tools/test.ps1
```

四段全绿才算过：

- `goldminer_test_OK` —— 玩法断言用例：摆钩限位、放钩速度、抓取判定半径、
  重量→收线 QTE、连击倍率与超时、神秘袋开袋表、炸弹拆弹、TNT 连锁、炸药
  道具、关卡时间与推进、得分与结算、朝向纯函数、皮肤与素材布局、存档往返
  （用例 exe 跑在 `build/goldminer/tests/` 下，存档落在自己目录，不碰玩家存档）；
- `goldminer_SAVE_OK runs=1 -> runs=2` —— 存档两遍：第二遍是新进程，读回
  第一遍写的档；
- `goldminer_SMOKE_OK` —— 无头冒烟：UiDriver 跑几帧后自行退出（顺带断言
  换肤真的生效：stdout 里应有 `SKIN applied=goldminer`）；
- `goldminer_SKIN_OK` —— 皮肤资源自检：基线 `base.css`、底座 `dark/`、
  本游戏皮肤包都在 exe 内嵌里（`GoldMiner.exe skin-probe` 打印实际状态），
  且磁盘上**没有**手工拷的基线。

`build.ps1` 会把用例编成 `build/goldminer/tests/goldminer_test.exe`
（`-BuildTests:$false` 可跳过）。

调试开关
--------
- `MINER_SIM=1`（可配 `MINER_SIM_SEED`）—— 无头平衡仿真，打 8 关并校验经济曲线；
- `MINER_SCENE=over` —— 直接开结算页（视觉自检用：截图判"像不像"，
  判不了"换没换成功"，后者走断言）；
- `MINER_SKIN_PROBE=1` —— 启动后打出实际生效的皮肤名。
