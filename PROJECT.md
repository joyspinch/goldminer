# goldminer —— 独立项目

本项目从 zan-lang 仓库的 `templates/game/goldminer` 导出（导出日期：2026-10-20）。
该模板已搬出语言仓库（体量超出示例级模板位），历史版本在 `archive/goldminer-2026-10-20` 标签上；公共包（Game.Kit / Game.Foundation.Gui / Gui）仍由 zan-lang 仓库提供。
语言仓库只放 SDK、公共包与**示例级**模板；产品级游戏在这里自己演进。

## 目录

    goldminer/
      client/      客户端：src/ assets/ data/ tools/


所有命令都在**项目根**下执行（路径一律相对项目根）。

## 编译

```powershell
$env:ZAN_HOME = 'D:/path/to/zan-lang'   # 编译器与 stdlib 同源
pwsh -File client/tools/build.ps1
```

ZAN_HOME 指向 zan-lang 仓库时用它的 `build/zanc.exe` 与 `stdlib/`；
不设则用 PATH 上的 `zanc`。stdlib 也可用 ZAN_STDLIB 单独指定。

## 公共包

包从三处解析：`<项目根>/packages/`、`<项目根>/.zan-packages/`、
全局 `%LOCALAPPDATA%\Zan\packages`。需要某个包时：

```powershell
Copy-Item -Recurse <zan-lang>/packages/<Name> packages/<Name>
```

或编译时加 `--package-project <zan-lang>`（直接吃仓库里的 packages/）。

## 测试

```powershell
pwsh -File client/tools/test.ps1     # 客户端用例
```

三段全绿才算过：`goldminer_test_OK`（玩法断言用例，纯逻辑）、
`goldminer_SAVE_OK runs=1 -> runs=2`（存档两遍，新进程读回上一遍的档）、
`goldminer_SMOKE_OK`（无头冒烟）。用例源码在 `client/tests/goldminer_test.zan`，
`build.ps1` 会把它编成 `build/goldminer/tests/goldminer_test.exe`。
