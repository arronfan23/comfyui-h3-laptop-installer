# =============================================================
#  ComfyUI + H3 模型 在线一键安装器
#  双击「一键安装.bat」运行；全部内容联网下载，无需安装包
# =============================================================
param(
    [string]$InstallDir = "",
    [switch]$SkipModels,          # 跳过模型下载（测试用）
    [switch]$UseMirror,           # 强制使用 hf-mirror.com 下载模型（国内推荐）
    [switch]$NoStart,             # 装完不自动启动 ComfyUI
    [string]$CodexConfigPath = "" # 默认 %USERPROFILE%\.codex\config.toml
)

$ErrorActionPreference = "Stop"
$InstallerDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PkgRoot      = Split-Path -Parent $InstallerDir

try { Start-Transcript -Path (Join-Path $InstallerDir "install.log") -Force | Out-Null } catch {}

function Info($msg)  { Write-Host "[安装] $msg" -ForegroundColor Cyan }
function Ok($msg)    { Write-Host "[完成] $msg" -ForegroundColor Green }
function Warn($msg)  { Write-Host "[注意] $msg" -ForegroundColor Yellow }
function Fail($msg)  { Write-Host "[失败] $msg" -ForegroundColor Red; throw $msg }

# ComfyUI 版本（含 MiniMax H3 支持、与锁定依赖兼容的官方 master 提交）
$ComfyUICommit = "34744cd29eacea9bbdec17e628a81c2ce0737d16"

# H3 模型清单（笔记本版）：int8 主模型 + 4B 文本编码器（不带 32B，省 15GB 显存/下载）
$Models = @(
    @{ Repo = "Comfy-Org/MiniMax-H3"; File = "diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors"; Size = 20970379616 },
    @{ Repo = "Comfy-Org/MiniMax-H3"; File = "diffusion_models/minimax_h3_fl2va_pruned_int8_convrot.safetensors"; Size = 20970379616 },
    @{ Repo = "Comfy-Org/Qwen3-VL";   File = "text_encoders/qwen3vl_4b_fp8_scaled.safetensors";                     Size = 5242467968  },
    @{ Repo = "Comfy-Org/MiniMax-H3"; File = "vae/minimax_h3_video_vae_fp16.safetensors";                           Size = 5207808496  },
    @{ Repo = "Comfy-Org/MiniMax-H3"; File = "vae/minimax_h3_audio_vae_fp32.safetensors";                           Size = 605254808   }
)

function Download-File($url, $dest, [long]$expectSize = -1) {
    New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null
    # 已完成则跳过
    if ((Test-Path $dest) -and ($expectSize -lt 0 -or (Get-Item $dest).Length -eq $expectSize)) { return $true }
    & curl.exe -fL --retry 5 --retry-delay 5 --retry-all-errors --connect-timeout 30 -C - -o "$dest" "$url"
    if ($LASTEXITCODE -ne 0) { return $false }
    if ($expectSize -ge 0 -and (Get-Item $dest).Length -ne $expectSize) {
        Warn "文件大小不符，重新下载: $(Split-Path $dest -Leaf)"
        Remove-Item $dest -Force
        & curl.exe -fL --retry 5 --retry-delay 5 --retry-all-errors --connect-timeout 30 -o "$dest" "$url"
        if ($LASTEXITCODE -ne 0) { return $false }
        if ((Get-Item $dest).Length -ne $expectSize) { return $false }
    }
    return $true
}

function Install-ZipFromUrl($url, $destDir, $innerPrefix) {
    # 下载 GitHub zip 并把内部顶层目录内容放进 $destDir
    $tmpZip = Join-Path $env:TEMP ([guid]::NewGuid().ToString() + ".zip")
    $tmpDir = Join-Path $env:TEMP ([guid]::NewGuid().ToString())
    try {
        $got = Download-File $url $tmpZip
        if (-not $got -and $url -like "https://github.com/*") {
            Warn "github.com 直连失败，尝试 gh-proxy 镜像..."
            $got = Download-File "https://gh-proxy.com/$url" $tmpZip
        }
        if (-not $got) { Fail "下载失败: $url" }
        Expand-Archive $tmpZip -DestinationPath $tmpDir -Force
        $inner = Get-ChildItem $tmpDir -Directory | Select-Object -First 1
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        robocopy $inner.FullName $destDir /E /MOVE /NFL /NDL /NJH /NJS /NP | Out-Null
        $global:LASTEXITCODE = 0
    } finally {
        Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
        Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   三猫云 SanMaoCloud" -ForegroundColor Cyan
Write-Host "   ComfyUI + H3 一键安装（笔记本版）"
Write-Host "   适配 RTX 3080 Laptop 16GB / 32GB 内存"
Write-Host "   全程联网下载（约 55GB），请保持网络畅通"
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# ---------- 0. 安装目录 ----------
if (-not $InstallDir) {
    $InstallDir = Join-Path (Split-Path -Parent $PkgRoot) "ComfyUI"
}
$InstallDir = [System.IO.Path]::GetFullPath($InstallDir)
Info "安装目录: $InstallDir"

# ---------- 1. 环境检查 ----------
$gpu = $null
try { $gpu = (nvidia-smi --query-gpu=name --format=csv,noheader 2>$null | Select-Object -First 1) } catch {}
if ($gpu) { Ok "检测到显卡: $gpu" } else { Warn "未检测到 NVIDIA 显卡！ComfyUI 将无法用 GPU 推理。" }

# 驱动版本检查（PyTorch cu130 需要 580+ 驱动）
$drv = $null
try { $drv = (nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>$null | Select-Object -First 1).Trim() } catch {}
if ($drv -and ([int]($drv.Split('.')[0]) -lt 580)) {
    Warn "显卡驱动版本 $drv 过旧，PyTorch cu130 需要 580 或更新版本"
    Warn "请到 NVIDIA 官网下载最新驱动: https://www.nvidia.cn/Download/index.aspx?lang=cn"
}

$needGB = if ($SkipModels) { 10 } else { 60 }
$drive = New-Object System.IO.DriveInfo($InstallDir.Substring(0,1))
if ($drive.AvailableFreeSpace -lt $needGB * 1GB) {
    Fail "磁盘 $($drive.Name) 剩余空间不足（需要约 ${needGB}GB，当前 $([math]::Round($drive.AvailableFreeSpace/1GB))GB）"
}

# ---------- 2. ComfyUI 主程序 ----------
if (Test-Path (Join-Path $InstallDir "main.py")) {
    Ok "ComfyUI 主程序已存在，跳过下载"
} else {
    Info "下载 ComfyUI 主程序（提交 $ComfyUICommit）..."
    Install-ZipFromUrl "https://github.com/comfyanonymous/ComfyUI/archive/$ComfyUICommit.zip" $InstallDir "ComfyUI-"
    Ok "主程序就绪"
}

# ---------- 3. 自定义节点 / MCP / 用户配置 ----------
if (Test-Path (Join-Path $InstallDir "custom_nodes\ComfyUI-Manager\__init__.py")) {
    Ok "ComfyUI-Manager 已存在，跳过"
} else {
    Info "下载 ComfyUI-Manager ..."
    Install-ZipFromUrl "https://github.com/ltdrdata/ComfyUI-Manager/archive/refs/heads/main.zip" (Join-Path $InstallDir "custom_nodes\ComfyUI-Manager") "ComfyUI-Manager-"
}
if (Test-Path (Join-Path $InstallDir "custom_nodes\AIGODLIKE-ComfyUI-Translation\__init__.py")) {
    Ok "中文翻译节点已存在，跳过"
} else {
    Info "下载界面中文翻译节点 ..."
    Install-ZipFromUrl "https://github.com/AIGODLIKE/AIGODLIKE-ComfyUI-Translation/archive/refs/heads/main.zip" (Join-Path $InstallDir "custom_nodes\AIGODLIKE-ComfyUI-Translation") "AIGODLIKE-"
}

Info "安装 comfyui-mcp (Codex 控制接口)..."
Expand-Archive (Join-Path $InstallerDir "comfyui-mcp.zip") -DestinationPath (Join-Path $InstallDir "comfyui-mcp") -Force

$ud = Join-Path $InstallDir "user\default"
New-Item -ItemType Directory -Path $ud -Force | Out-Null
Copy-Item (Join-Path $InstallerDir "comfy.settings.json") $ud -Force -ErrorAction SilentlyContinue
Ok "组件安装完成"

# ---------- 4. H3 模型 ----------
if ($SkipModels) {
    Warn "按参数跳过模型下载"
} else {
    $totalGB = [math]::Round(($Models | ForEach-Object { $_.Size } | Measure-Object -Sum).Sum / 1GB, 1)
    Info "下载 H3 模型（共 ${totalGB}GB，支持断点续传）..."
    foreach ($m in $Models) {
        $dest = Join-Path $InstallDir ("models\" + ($m.File -replace '/', '\'))
        if ((Test-Path $dest) -and (Get-Item $dest).Length -eq $m.Size) {
            Ok "已存在: $($m.File)"
            continue
        }
        Info "  -> $($m.File)  ($([math]::Round($m.Size/1GB,1)) GB)"
        $done = $false
        if (-not $UseMirror) {
            $done = Download-File "https://huggingface.co/$($m.Repo)/resolve/main/$($m.File)" $dest $m.Size
            if (-not $done) { Warn "HuggingFace 直连失败，切换 hf-mirror.com 镜像..." }
        }
        if (-not $done) {
            $done = Download-File "https://hf-mirror.com/$($m.Repo)/resolve/main/$($m.File)" $dest $m.Size
        }
        if (-not $done) { Fail "模型下载失败: $($m.File)。请检查网络后重跑本脚本（已下载部分会续传）" }
    }
    Ok "模型下载完成"
}

# ---------- 5. Python 3.12 ----------
function Test-Python312($exe, $argPrefix) {
    try {
        $v = & $exe $argPrefix -c "import sys;print('%d.%d'%sys.version_info[:2])" 2>$null
        return ($v -eq "3.12")
    } catch { return $false }
}

$pyExe = $null; $pyArgs = @()
foreach ($cand in @(
    @{ exe = "py";     args = @("-3.12") },
    @{ exe = "python"; args = @() }
)) {
    if (Get-Command $cand.exe -ErrorAction SilentlyContinue) {
        if (Test-Python312 $cand.exe $cand.args) { $pyExe = $cand.exe; $pyArgs = $cand.args; break }
    }
}
$bundledPy = Join-Path $env:LOCALAPPDATA "Programs\Python\Python312\python.exe"
if (-not $pyExe -and (Test-Path $bundledPy)) { $pyExe = $bundledPy; $pyArgs = @() }

if (-not $pyExe) {
    Info "未找到 Python 3.12，自动下载安装（当前用户，无需管理员）..."
    $pyInstaller = Join-Path $env:TEMP "python-3.12.10-amd64.exe"
    $got = Download-File "https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe" $pyInstaller
    if (-not $got) {
        Warn "python.org 下载失败，切换华为云镜像..."
        $got = Download-File "https://mirrors.huaweicloud.com/python/3.12.10/python-3.12.10-amd64.exe" $pyInstaller
    }
    if (-not $got) { Fail "Python 下载失败，请手动安装 Python 3.12 后重跑" }
    & $pyInstaller /quiet InstallAllUsers=0 PrependPath=0 Include_test=0 AssociateFiles=0 Shortcuts=0 | Out-Null
    if (Test-Path $bundledPy) { $pyExe = $bundledPy } else { Fail "Python 3.12 安装失败，请手动安装后重跑本脚本" }
    Ok "Python 3.12 安装完成"
} else {
    Ok "使用已有 Python 3.12: $pyExe"
}

# ---------- 6. 虚拟环境 + 依赖 ----------
$venvPy = Join-Path $InstallDir "venv\Scripts\python.exe"
if (-not (Test-Path $venvPy)) {
    Info "创建虚拟环境 venv..."
    & $pyExe @pyArgs -m venv (Join-Path $InstallDir "venv")
}
Info "安装依赖（torch 2.11 + cu130 等，约 4-5GB 下载，请耐心等待）..."
& $venvPy -m pip install --upgrade pip
$pipIndexArgs = @()
if ($UseMirror) { $pipIndexArgs = @("-i", "https://pypi.tuna.tsinghua.edu.cn/simple") }
$pipOk = $false
for ($i = 1; $i -le 3 -and -not $pipOk; $i++) {
    if ($i -gt 1) { Warn "pip 网络中断，第 $i 次重试（已下载的包会自动复用）..." }
    & $venvPy -m pip install -r (Join-Path $InstallerDir "requirements-freeze.txt") @pipIndexArgs --extra-index-url https://download.pytorch.org/whl/cu130 --retries 10 --timeout 120
    $pipOk = ($LASTEXITCODE -eq 0)
}
if (-not $pipOk) { Fail "pip 依赖安装失败，详见上方输出与 install.log；重跑本脚本可继续" }
Get-ChildItem (Join-Path $InstallDir "custom_nodes") -Directory | ForEach-Object {
    $req = Join-Path $_.FullName "requirements.txt"
    if (Test-Path $req) { & $venvPy -m pip install -r $req @pipIndexArgs --extra-index-url https://download.pytorch.org/whl/cu130 --retries 10 --timeout 120 }
}
Ok "Python 依赖安装完成"

# ---------- 7. Node.js 便携版（供 MCP 使用）----------
$nodeDir = Join-Path $InstallDir "runtime\node"
$nodeExe = Join-Path $nodeDir "node.exe"
if (-not (Test-Path $nodeExe)) {
    Info "下载 Node.js LTS 便携版..."
    $idx = Invoke-RestMethod "https://nodejs.org/dist/index.json"
    $lts = $idx | Where-Object { $_.lts -and $_.version -like "v22.*" } | Select-Object -First 1
    if (-not $lts) { $lts = $idx | Where-Object { $_.lts } | Select-Object -First 1 }
    $zip = Join-Path $env:TEMP "node-$($lts.version)-win-x64.zip"
    $got = Download-File "https://nodejs.org/dist/$($lts.version)/node-$($lts.version)-win-x64.zip" $zip
    if (-not $got) {
        Warn "nodejs.org 下载失败，切换 npmmirror 镜像..."
        $got = Download-File "https://npmmirror.com/mirrors/node/$($lts.version)/node-$($lts.version)-win-x64.zip" $zip
    }
    if (-not $got) { Fail "Node.js 下载失败" }
    New-Item -ItemType Directory -Path (Join-Path $InstallDir "runtime") -Force | Out-Null
    Expand-Archive $zip -DestinationPath (Join-Path $InstallDir "runtime") -Force
    Rename-Item (Join-Path $InstallDir "runtime\node-$($lts.version)-win-x64") $nodeDir
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
}
& $nodeExe -v | Out-Null
Ok "Node.js 就绪: $(& $nodeExe -v)"

# ---------- 8. 启动脚本 ----------
$bat = @"
@echo off
chcp 65001 >nul
title 三猫云 SanMaoCloud - ComfyUI
cd /d %~dp0
echo ========================================
echo   三猫云 SanMaoCloud
echo   ComfyUI 启动中（笔记本低显存模式 --lowvram）...
echo   浏览器访问: http://127.0.0.1:8188
echo   关闭此窗口即停止服务
echo ========================================
call venv\Scripts\activate.bat
python main.py --lowvram
pause
"@
# 写为 CRLF，避免 cmd 解析 LF-only 批处理出错
[System.IO.File]::WriteAllText((Join-Path $InstallDir "启动ComfyUI.bat"), ($bat -replace "`n", "`r`n"), [System.Text.Encoding]::UTF8)

# ---------- 9. 写入 Codex MCP 配置 ----------
if (-not $CodexConfigPath) { $CodexConfigPath = Join-Path $env:USERPROFILE ".codex\config.toml" }
$serverJs = Join-Path $InstallDir "comfyui-mcp\server.js"
$mcpBlock = @"

[mcp_servers.comfyui]
command = '$nodeExe'
args = ['$serverJs']
startup_timeout_sec = 30

[mcp_servers.comfyui.env]
COMFYUI_URL = "http://127.0.0.1:8188"
"@
try {
    New-Item -ItemType Directory -Path (Split-Path $CodexConfigPath) -Force | Out-Null
    $existing = if (Test-Path $CodexConfigPath) { Get-Content $CodexConfigPath -Raw } else { "" }
    if ($existing -match "\[mcp_servers\.comfyui\]") {
        Ok "Codex MCP 配置已存在，跳过"
    } else {
        Add-Content -Path $CodexConfigPath -Value $mcpBlock -Encoding UTF8
        Ok "已写入 Codex MCP 配置: $CodexConfigPath（重启 Codex 后生效）"
    }
} catch { Warn "写入 Codex 配置失败（不影响 ComfyUI 本身）: $_" }

# ---------- 10. 冒烟测试 ----------
Info "验证 PyTorch CUDA ..."
$cudaOk = & $venvPy -c "import torch;print(torch.cuda.is_available())"
if ($cudaOk -eq "True") { Ok "PyTorch CUDA 可用" } else { Warn "torch.cuda.is_available() = $cudaOk，请检查显卡驱动" }

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "   安装完成！"
Write-Host "   启动: $InstallDir\启动ComfyUI.bat"
Write-Host "   Codex 中即可通过 comfyui MCP 操控"
Write-Host "   三猫云 SanMaoCloud 出品" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green

if (-not $NoStart) {
    Info "正在启动 ComfyUI ..."
    Start-Process -FilePath (Join-Path $InstallDir "启动ComfyUI.bat")
    Start-Sleep 15
    Start-Process "http://127.0.0.1:8188"
}

try { Stop-Transcript | Out-Null } catch {}
exit 0
