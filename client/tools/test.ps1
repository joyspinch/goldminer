# 黄金矿工 测试：三段全绿才算过。
#
#   1) goldminer_test_OK            玩法断言用例（纯逻辑，不开窗口/音频）
#   2) goldminer_SAVE_OK runs=1 -> runs=2   存档两遍：新进程读回上一遍写的档
#   3) goldminer_SMOKE_OK           无头冒烟：UiDriver 跑几帧后自行退出
#
# 判据：每段都有明确标记输出；任何一段缺标记即判失败。
# 断言用例跑在 build/goldminer/tests/ 下，存档落在自己目录，不碰玩家存档。
param(
    [string]$Compiler = $env:ZANC,
    [string]$PackageProject = ''
)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$repo = Split-Path -Parent $project
. (Join-Path $PSScriptRoot 'zanc.ps1')
if (-not $PackageProject) { if ($env:ZAN_HOME) { $PackageProject = $env:ZAN_HOME } else { throw '需要 -PackageProject 指向 zan-lang 仓库（公共包在它的 packages/ 下）' } }
if (-not $Compiler) { $Compiler = Resolve-ZanCompiler -PackageProject $PackageProject }
$out = Join-Path $repo 'build/goldminer'
& (Join-Path $PSScriptRoot 'build.ps1') -Compiler $Compiler -PackageProject $PackageProject -Output $out
$exe = Join-Path $out 'GoldMiner.exe'
if (-not (Test-Path $exe)) { throw "缺少可执行文件：$exe" }

# --- 第一段：玩法断言用例 ---
# build.ps1 已经把用例编成 <out>/tests/goldminer_test.exe（纯逻辑核心 + 用例自身）。
$caseExe = Join-Path $out 'tests/goldminer_test.exe'
if (-not (Test-Path $caseExe)) { throw "缺少用例可执行文件：$caseExe" }
$caseOut = & $caseExe 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "玩法断言用例失败：goldminer_test`n$caseOut" }
if ($caseOut -notmatch 'goldminer_test OK') { throw "玩法断言用例输出不对：goldminer_test`n$caseOut" }
if ($caseOut -notmatch 'goldminer_test checks=\d+ failures=0') {
    throw "玩法断言用例没有全绿：goldminer_test`n$caseOut"
}
Write-Host $caseOut.Trim()
Write-Host "goldminer_test_OK"

# --- 第二段：存档两遍 ---
# 存档落在用例 exe 自己的目录（build/goldminer/tests/），不碰玩家存档。
$saveFile = Join-Path $out 'tests/goldminer_save.txt'
if (Test-Path $saveFile) { Remove-Item $saveFile -Force }
$saveOut1 = & $caseExe save 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "存档第一遍失败`n$saveOut1" }
if ($saveOut1 -notmatch 'runs=1') { throw "第一遍存档没写成局数 1：$saveOut1" }
if (-not (Test-Path $saveFile)) { throw "存档文件没落盘：$saveFile" }
$saveOut2 = & $caseExe save 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "存档第二遍失败`n$saveOut2" }
if ($saveOut2 -notmatch 'runs=2') { throw "第二遍没读回上一遍的存档（期望 runs=2）：$saveOut2" }
if ($saveOut2 -notmatch 'bestLevel=3' -or $saveOut2 -notmatch 'bestGold=250' -or $saveOut2 -notmatch 'totalGold=900') {
    throw "第二遍没读回上一遍写的档内容：$saveOut2"
}
Write-Host "goldminer_SAVE_OK runs=1 -> runs=2"

# --- 第三段：无头冒烟 ---
# demo 标记：进对局自弈场景（比停在主菜单多跑一层玩法渲染）
[IO.File]::WriteAllText((Join-Path $out 'goldminer_demo.txt'), 'demo', [Text.UTF8Encoding]::new($false))
# UiDriver 脚本：等几帧 → dump → 退出（无头，不弹窗口）
$script = Join-Path $out 'ui.script'
[IO.File]::WriteAllText($script, "wait 300`ndump tree tree.txt`nquit`n", [Text.UTF8Encoding]::new($false))
$uidir = Join-Path $out 'uidrv'
$env:ZAN_UI_SCRIPT = $script
$env:ZAN_UI_OUT = $uidir
$proc = Start-Process -FilePath $exe -WorkingDirectory $out -PassThru -WindowStyle Hidden
if (-not $proc.WaitForExit(60000)) {
    $proc.Kill()
    throw '无头冒烟超时：应用没按 UiDriver 脚本退出'
}
if ($proc.ExitCode -ne 0) { throw "无头冒烟失败：exit=$($proc.ExitCode)" }
$log = Join-Path $uidir 'results.log'
if (-not (Test-Path $log)) { throw 'UiDriver 会话没有产出 results.log' }
if (-not (Select-String -Path $log -Pattern 'DONE' -Quiet)) { throw "UiDriver 会话未收尾：$log" }
Write-Host "goldminer_SMOKE_OK"
