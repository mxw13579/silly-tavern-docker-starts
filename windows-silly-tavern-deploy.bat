@echo off
chcp 65001 >nul
title SillyTavern Windows 安装脚本
setlocal EnableExtensions DisableDelayedExpansion

set "CURRENT_DIR=%~dp0"
cd /d "%CURRENT_DIR%"
set "CURRENT_DIR=%cd%"
set "PROJECT_DIR=%CURRENT_DIR%\SillyTavern"

set "GIT_FALLBACK_URL=https://github.com/git-for-windows/git/releases/download/v2.45.2.windows.1/Git-2.45.2-64-bit.exe"
set "NODE_FALLBACK_URL=https://nodejs.org/dist/v20.11.1/node-v20.11.1-x64.msi"

set "GIT_INSTALLER=%TEMP%\Git-Setup.exe"
set "NODE_INSTALLER=%TEMP%\NodeJS-Setup.msi"

set "GIT_STATUS=未检测"
set "NODE_STATUS=未检测"
set "NPM_STATUS=未检测"

echo 当前工作目录: "%CURRENT_DIR%"
echo.

REM -----------------------------------------------------------------------------
REM 管理员权限检查
REM -----------------------------------------------------------------------------
net session >nul 2>&1
if errorlevel 1 (
    echo 错误: 请以管理员身份运行此脚本。
    pause
    exit /b 1
)

echo 已获取管理员权限。
echo.

REM -----------------------------------------------------------------------------
REM PowerShell 检查
REM -----------------------------------------------------------------------------
where powershell >nul 2>&1
if errorlevel 1 (
    echo 错误: 未找到 PowerShell，无法继续。
    pause
    exit /b 1
)

REM -----------------------------------------------------------------------------
REM x64 检查
REM -----------------------------------------------------------------------------
if /i not "%PROCESSOR_ARCHITECTURE%"=="AMD64" (
    if /i not "%PROCESSOR_ARCHITEW6432%"=="AMD64" (
        echo 错误: 当前脚本仅提供 x64 Git / Node.js 安装包。
        pause
        exit /b 1
    )
)

REM -----------------------------------------------------------------------------
REM 网络信息
REM -----------------------------------------------------------------------------
echo 正在获取网络信息...
call :GetPublicInfo
echo.

REM -----------------------------------------------------------------------------
REM 安装 / 检查 Git
REM -----------------------------------------------------------------------------
echo -----------------------------------
echo [1/3] 检测 Git 环境...
call :EnsureGit
if errorlevel 1 (
    echo 错误: Git 安装或检测失败。
    pause
    exit /b 1
)
echo Git 状态: %GIT_STATUS%
echo.

REM -----------------------------------------------------------------------------
REM 安装 / 检查 Node.js
REM -----------------------------------------------------------------------------
echo -----------------------------------
echo [2/3] 检测 Node.js 环境...
call :EnsureNode
if errorlevel 1 (
    echo 错误: Node.js 安装或检测失败。
    pause
    exit /b 1
)
echo Node.js 状态: %NODE_STATUS%
echo.

REM -----------------------------------------------------------------------------
REM 检查 npm
REM -----------------------------------------------------------------------------
echo -----------------------------------
echo [3/3] 检测 npm 环境...
call :EnsureNpm
if errorlevel 1 (
    echo 错误: npm 不可用，请重新安装 Node.js。
    pause
    exit /b 1
)
echo npm 状态: %NPM_STATUS%
echo.

REM -----------------------------------------------------------------------------
REM 环境汇总
REM -----------------------------------------------------------------------------
echo -----------------------------------
echo          环境检查结果
echo -----------------------------------
echo Git     : %GIT_STATUS%
echo Node.js : %NODE_STATUS%
echo npm     : %NPM_STATUS%
echo -----------------------------------
echo.

REM -----------------------------------------------------------------------------
REM 下载 / 更新项目
REM -----------------------------------------------------------------------------
echo -----------------------------------
echo          下载并启动项目
echo -----------------------------------
echo 项目目录: "%PROJECT_DIR%"
echo.

call :SetupProject
if errorlevel 1 (
    echo 错误: 项目下载或更新失败。
    pause
    exit /b 1
)

call :StartProject
if errorlevel 1 (
    echo 错误: 项目启动失败。
    pause
    exit /b 1
)

echo.
echo 操作完成。
pause
exit /b 0

REM =============================================================================
REM 函数区
REM =============================================================================

:GetPublicInfo
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='SilentlyContinue';" ^
  "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;" ^
  "$ip=(Invoke-WebRequest -UseBasicParsing -TimeoutSec 10 'https://api.ipify.org').Content;" ^
  "if($ip){Write-Host ('当前公网 IP: ' + $ip)}else{Write-Host '当前公网 IP: 获取失败'};" ^
  "try{Invoke-WebRequest -UseBasicParsing -TimeoutSec 10 ('https://ipinfo.io/' + $ip)}catch{}"
exit /b 0

:RefreshPath
set "MACHINE_PATH="
set "USER_PATH="

for /f "tokens=2,*" %%A in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul') do set "MACHINE_PATH=%%B"
for /f "tokens=2,*" %%A in ('reg query "HKCU\Environment" /v Path 2^>nul') do set "USER_PATH=%%B"

if defined MACHINE_PATH set "PATH=%MACHINE_PATH%;%USER_PATH%"

if exist "%ProgramFiles%\Git\cmd\git.exe" set "PATH=%ProgramFiles%\Git\cmd;%PATH%"
if exist "%ProgramFiles%\nodejs\node.exe" set "PATH=%ProgramFiles%\nodejs;%PATH%"

exit /b 0

:DownloadFile
set "DOWNLOAD_URL=%~1"
set "DOWNLOAD_OUT=%~2"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$ProgressPreference='Continue';" ^
  "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;" ^
  "Invoke-WebRequest -UseBasicParsing -Uri '%DOWNLOAD_URL%' -OutFile '%DOWNLOAD_OUT%'"

if errorlevel 1 exit /b 1
if not exist "%DOWNLOAD_OUT%" exit /b 1
exit /b 0

:InstallByWinget
set "WINGET_ID=%~1"

where winget >nul 2>&1
if errorlevel 1 exit /b 1

winget install --id "%WINGET_ID%" -e --silent --accept-package-agreements --accept-source-agreements
if errorlevel 1 exit /b 1

exit /b 0

:EnsureGit
where git >nul 2>&1
if not errorlevel 1 (
    for /f "tokens=*" %%i in ('git --version 2^>nul') do set "GIT_STATUS=%%i"
    exit /b 0
)

echo 未检测到 Git，尝试使用 winget 安装...
call :InstallByWinget "Git.Git"
if errorlevel 1 (
    echo winget 安装 Git 失败，改用安装包方式。

    if exist "%GIT_INSTALLER%" del /f /q "%GIT_INSTALLER%" >nul 2>&1

    echo 正在下载 Git 安装包...
    call :DownloadFile "%GIT_FALLBACK_URL%" "%GIT_INSTALLER%"
    if errorlevel 1 exit /b 1

    echo 正在静默安装 Git...
    start /wait "" "%GIT_INSTALLER%" /VERYSILENT /NORESTART /NOCANCEL /SP-
    if errorlevel 1 exit /b 1

    del /f /q "%GIT_INSTALLER%" >nul 2>&1
)

call :RefreshPath

where git >nul 2>&1
if errorlevel 1 exit /b 1

for /f "tokens=*" %%i in ('git --version 2^>nul') do set "GIT_STATUS=%%i"
exit /b 0

:EnsureNode
where node >nul 2>&1
if not errorlevel 1 (
    for /f "tokens=*" %%i in ('node --version 2^>nul') do set "NODE_STATUS=%%i"
    exit /b 0
)

echo 未检测到 Node.js，尝试使用 winget 安装...
call :InstallByWinget "OpenJS.NodeJS.LTS"
if errorlevel 1 (
    echo winget 安装 Node.js 失败，改用 MSI 安装包方式。

    if exist "%NODE_INSTALLER%" del /f /q "%NODE_INSTALLER%" >nul 2>&1

    echo 正在下载 Node.js 安装包...
    call :DownloadFile "%NODE_FALLBACK_URL%" "%NODE_INSTALLER%"
    if errorlevel 1 exit /b 1

    echo 正在静默安装 Node.js...
    start /wait msiexec /i "%NODE_INSTALLER%" /qn /norestart
    if errorlevel 1 exit /b 1

    del /f /q "%NODE_INSTALLER%" >nul 2>&1
)

call :RefreshPath

where node >nul 2>&1
if errorlevel 1 exit /b 1

for /f "tokens=*" %%i in ('node --version 2^>nul') do set "NODE_STATUS=%%i"
exit /b 0

:EnsureNpm
call :RefreshPath

where npm >nul 2>&1
if errorlevel 1 exit /b 1

for /f "tokens=*" %%i in ('call npm --version 2^>nul') do set "NPM_STATUS=%%i"

if "%NPM_STATUS%"=="" exit /b 1
exit /b 0

:SetupProject
cd /d "%CURRENT_DIR%"

if not exist "%PROJECT_DIR%" (
    echo 未检测到 SillyTavern，开始克隆项目...
    git clone "https://github.com/SillyTavern/SillyTavern.git" "%PROJECT_DIR%"
    if errorlevel 1 exit /b 1
    echo 项目克隆成功。
    exit /b 0
)

if not exist "%PROJECT_DIR%\.git" (
    echo 错误: 已存在 "%PROJECT_DIR%"，但它不是 Git 仓库。
    echo 为避免覆盖用户文件，请手动处理该目录后重新运行脚本。
    exit /b 1
)

echo 检测到已存在 SillyTavern 项目。
choice /c YN /m "是否更新项目？Y=更新，N=跳过"
if errorlevel 2 (
    echo 已跳过项目更新。
    exit /b 0
)

echo 正在更新项目...
git -C "%PROJECT_DIR%" pull --ff-only
if errorlevel 1 (
    echo 项目更新失败。可能存在本地修改或网络问题。
    exit /b 1
)

echo 项目更新成功。
exit /b 0

:StartProject
if not exist "%PROJECT_DIR%\start.bat" (
    echo 错误: 未找到 "%PROJECT_DIR%\start.bat"。
    exit /b 1
)

echo 正在启动 SillyTavern...
pushd "%PROJECT_DIR%"
start "SillyTavern" cmd /k call start.bat
popd

echo 已启动 SillyTavern。
exit /b 0
