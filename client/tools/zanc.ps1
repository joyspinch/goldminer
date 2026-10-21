# 共用：定位 zanc 编译器（build.ps1 与 test.ps1 都用它）。
#
# 查找顺序：显式参数 → $env:ZANC → $env:ZAN_HOME → 包仓库自带的 build/ →
# 包仓库同级目录里的 zan* 兄弟仓库 → PATH 上的 zanc。
function Resolve-ZanCompiler {
    param(
        [string]$Compiler = '',
        [string]$PackageProject = ''
    )
    if ($Compiler) { return $Compiler }
    if ($env:ZANC -and (Test-Path $env:ZANC)) { return $env:ZANC }
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($env:ZAN_HOME) { $candidates.Add((Join-Path $env:ZAN_HOME 'build/zanc.exe')) }
    if ($PackageProject) {
        $candidates.Add((Join-Path $PackageProject 'build/zanc.exe'))
        $parent = Split-Path -Parent $PackageProject
        if ($parent) {
            Get-ChildItem -Path $parent -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like 'zan*' } |
                ForEach-Object { $candidates.Add((Join-Path $_.FullName 'build/zanc.exe')) }
        }
    }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    $onPath = Get-Command zanc -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    throw '找不到 zanc 编译器：用 -Compiler 指定，或设 $env:ZAN_HOME / $env:ZANC'
}
