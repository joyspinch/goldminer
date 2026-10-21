# 黄金矿工 构建：编译 src/ 下全部 .zan → 可执行文件。
#
# 公共包（Game.Kit / Game.Foundation.Gui / Gui）住在 zan-lang 仓库的 packages/ 下，
# 编译要带 --package-project 指向包根：仓库内 = 仓库根；项目搬到仓库外后 =
# zan-lang 仓库，由 $ZAN_HOME 或 -PackageProject 指定。
# assets/ 由 zanc 自动内嵌进 exe（入口源文件带目录前缀时才会定位到），
# 这里再在 exe 旁留一份磁盘副本——运行时磁盘优先，换图即生效。
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
if (-not $PackageProject) { if ($env:ZAN_HOME) { $PackageProject = $env:ZAN_HOME } else { throw '需要 -PackageProject 指向 zan-lang 仓库（公共包在它的 packages/ 下）' } }
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
# 皮肤包必须与 exe 同级：build/goldminer/skins/goldminer/skin.css
# （Gui.Styling.Skin.Roots 查的是 exe 同级 skins/ 与 assets/skins/）。
# 一并拷公共包的两样东西：
#   base.css  —— 控件基线（skin.css 里的 var(--radius-*) 等度量要靠它展开）
#   dark/     —— 底座皮肤（UseSkin("dark") 先铺底，再 UseSkin("goldminer")）
# 少了任何一个，UseSkin("goldminer") 之后的控件就退回默认外观。
$skinSrc = Join-Path $assets 'skins/goldminer'
if (Test-Path $skinSrc) {
    $skinDst = Join-Path $Output 'skins/goldminer'
    New-Item -ItemType Directory -Force -Path $skinDst | Out-Null
    Copy-Item (Join-Path $skinSrc '*') $skinDst -Recurse -Force
}
$guiSkins = Join-Path $PackageProject 'packages/Zan.Gui/src/Gui/skins'
if (Test-Path (Join-Path $guiSkins 'base.css')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $Output 'skins') | Out-Null
    Copy-Item (Join-Path $guiSkins 'base.css') (Join-Path $Output 'skins/base.css') -Force
}
if (Test-Path (Join-Path $guiSkins 'dark')) {
    $darkDst = Join-Path $Output 'skins/dark'
    New-Item -ItemType Directory -Force -Path $darkDst | Out-Null
    Copy-Item (Join-Path $guiSkins 'dark/*') $darkDst -Recurse -Force
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