<#
.SYNOPSIS
  推送当前独立仓到 origin，再同步合仓镜像中对应目录。
#>
param(
    [ValidateSet('client', 'server')]
    [string]$Part,
    [switch]$NoPushIndependent,
    [switch]$NoPushMono
)

$ErrorActionPreference = 'Stop'

# 本脚本在独立仓 scripts/ 下；合仓默认与独立仓同级
$RepoRoot = Split-Path -Parent $PSScriptRoot
$MonoRoot = Join-Path (Split-Path -Parent $RepoRoot) 'AI_tool_server_and_client'
$SyncScript = Join-Path $MonoRoot 'scripts\sync-to-monorepo.ps1'

if (-not (Test-Path $SyncScript)) {
    throw "找不到合仓同步脚本: $SyncScript`n请确认合仓在 $MonoRoot ，或改本脚本里的路径。"
}

if (-not $Part) {
    $leaf = Split-Path -Leaf $RepoRoot
    if ($leaf -match 'console_ui|client') { $Part = 'client' }
    elseif ($leaf -match 'picture_prompt|server') { $Part = 'server' }
    else {
        throw '请用 -Part client 或 -Part server'
    }
}

Push-Location $RepoRoot
try {
    if (-not $NoPushIndependent) {
        $status = git status --porcelain
        if (-not [string]::IsNullOrWhiteSpace($status)) {
            Write-Warning '工作区有未提交改动。将只推送已有提交；未提交内容不会进合仓。'
        }
        Write-Host ">> git push 独立仓 ($Part) ..."
        git push -u origin HEAD
        if ($LASTEXITCODE -ne 0) { throw '独立仓 push 失败' }
    }
}
finally {
    Pop-Location
}

$syncArgs = @{ Only = $Part }
if ($NoPushMono) { $syncArgs.NoPush = $true }

Write-Host ">> 同步合仓 $Part ..."
& $SyncScript @syncArgs
