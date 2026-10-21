# 黄金矿工 构建：编译 src/ 下全部 .zan → 可执行文件。
#
# 公共包（Game.Kit / Game.Foundation.Gui / Gui）住在 zan-lang 仓库的 packages/ 下，
# 编译要带 --package-project 指向包根：**直接指主仓库 zan-lang**（只读），
# 由 $ZAN_HOME 或 -PackageProject 指定。不要为它建 git worktree 副本——
# 副本停在旧 commit 上，公共包一改就跟不上（曾经因此白干一轮）。
#
# assets/ 由 zanc 自动内嵌进 exe（入口源文件带目录前缀时才会定位到），
# 这里再在 exe 旁留一份磁盘副本——运行时磁盘优先，换图即生效。
#
# 皮肤：控件基线 base.css 与 dark 底座由编译器**自动内嵌**
# （zanc 见 Gui/skins=skins 的自动内嵌，见 zan-lang docs/ZANC_CLI.md --embed），
# 磁盘上不必再放一份。本游戏自己的皮肤包用 --embed 按「单文件规格」烤进 exe
# （名字 skins/goldminer/skin.css），所以单文件发布也带着皮肤；磁盘上再留一份
# 只是为了改 CSS 不用重编（运行时磁盘优先，会盖住内嵌副本）。
param(
    [string]$Compiler = $env:ZANC,
    [string]$Stdlib = $env:ZAN_STDLIB,
    [string]$Output = '',
    [string]$PackageProject = '',
    # 透传给 zanc 的额外参数（如 --publish --target android-arm64 ...）
    [string[]]$ZancArgs = @(),
    # 是否顺带编译玩法断言用例（client/tests/*.zan → <Output>/tests/*.exe）
    [bool]$BuildTests = $true
)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$repo = Split-Path -Parent $project
. (Join-Path $PSScriptRoot 'zanc.ps1')
if (-not $PackageProject) { if ($env:ZAN_HOME) { $PackageProject = $env:ZAN_HOME } else { $PackageProject = 'D:\project\zan-lang' } }
if (-not $Compiler) { $Compiler = Resolve-ZanCompiler -PackageProject $PackageProject }
if (-not $Output) { $Output = Join-Path $repo 'build/goldminer' }
$Output = [IO.Path]::GetFullPath($Output)
New-Item -ItemType Directory -Force -Path $Output | Out-Null
# 入口 main.zan 必须排第一：zanc 只把 Main() 给第一个编译输入
# （genrun.c 的 emitMain=paths[0]）。其余 .zan 递归枚举——zanc 不会自动
# 带上同目录的其它文件，少传一个就是 "undefined type"。
$entry = Join-Path $project 'src/main.zan'
$sources = @()
if (Test-Path $entry) { $sources += $entry }
$sources += @(Get-ChildItem (Join-Path $project 'src') -Recurse -File -Filter *.zan |
    Where-Object { $_.FullName -ne $entry } | Sort-Object FullName | ForEach-Object { $_.FullName })
$zargs = @($sources) + @('--auto-stdlib', '--package-project', $PackageProject)
if ($Stdlib) { $zargs += @('--stdlib-path', $Stdlib) }
# 皮肤包按「单文件规格」烤进 exe：资源名 skins/goldminer/skin.css，
# 运行时 Gui.Styling.Skin.Load 找不到磁盘副本时就从内嵌里读，单文件发布也带着皮肤。
# 为什么不用目录规格（assets/skins=skins）：编译器对 skins 规格有白名单过滤
# （只放行 dark/light + zan.proj 的 skinlist 声明过的包），而 zan.proj 在公共包根
# （zan-lang），不是本项目——目录规格会把本游戏这一包直接滤掉并报
# "matched no readable file"。
$skinPack = Join-Path $project 'assets/skins/goldminer/skin.css'
if (Test-Path $skinPack) {
    $zargs += @('--embed', ($skinPack + '=skins/goldminer/skin.css'))
}
if ($ZancArgs) { $zargs += $ZancArgs }
$exe = Join-Path $Output 'GoldMiner.exe'
$zargs += @('-o', $exe)
& $Compiler @zargs
if ($LASTEXITCODE -ne 0) { throw "zanc failed ($LASTEXITCODE)" }
$assets = Join-Path $project 'assets'
# 先清掉上一版残留（素材改过名时，老文件留着只会误导，也会撑大发布包），
# 再整份拷过去。
$outAssets = Join-Path $Output 'assets'
if (Test-Path $outAssets) { Remove-Item $outAssets -Recurse -Force }
if (Test-Path $assets) { Copy-Item $assets $Output -Recurse -Force }
# 皮肤：exe 旁只留**本游戏这一份**皮肤包（改 CSS 不用重编，运行时磁盘优先）。
# 控件基线 base.css 与 dark 底座由编译器自动内嵌，磁盘上不再放——
# 放了就会"磁盘副本盖住内嵌基线"，那条兜底路径永远测不到。
$skinSrc = Join-Path $assets 'skins/goldminer'
$skinRoot = Join-Path $Output 'skins'
if (Test-Path $skinRoot) { Remove-Item $skinRoot -Recurse -Force }
if (Test-Path $skinSrc) {
    $skinDst = Join-Path $skinRoot 'goldminer'
    New-Item -ItemType Directory -Force -Path $skinDst | Out-Null
    Copy-Item (Join-Path $skinSrc '*') $skinDst -Recurse -Force
}
Write-Host "Built $exe"

# --- 玩法断言用例：单独编一个测试 exe ---
# 用例只吃纯逻辑核心（World + Entities）：MinerApp/Scenes 带游戏的 Main 与窗口
# 依赖，用例自己的 Main 才是入口，所以排除掉。
# 测试 exe 放在 <Output>/tests/ 下：存档路径 Data.SavePath() = exe 同级目录，
# 用例的存档落在自己目录里，不碰玩家存档（build/goldminer/goldminer_save.txt）。
if ($BuildTests) {
    $testDir = Join-Path $Output 'tests'
    New-Item -ItemType Directory -Force -Path $testDir | Out-Null
    $coreSources = @(Get-ChildItem (Join-Path $project 'src') -Recurse -File -Filter *.zan |
        Where-Object { $_.Name -ne 'MinerApp.zan' -and $_.FullName -notmatch '[\\/]Scenes[\\/]' } |
        Sort-Object FullName | ForEach-Object { $_.FullName })
    $testExe = Join-Path $testDir 'goldminer_test.exe'
    $tzargs = @((Join-Path $project 'tests/goldminer_test.zan')) + $coreSources +
        @('--auto-stdlib', '--package-project', $PackageProject)
    if ($Stdlib) { $tzargs += @('--stdlib-path', $Stdlib) }
    $tzargs += @('-o', $testExe)
    & $Compiler @tzargs
    if ($LASTEXITCODE -ne 0) { throw "zanc failed (用例 exe, $LASTEXITCODE)" }
    Write-Host "Built $testExe"
}