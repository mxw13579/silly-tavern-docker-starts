@echo off
chcp 65001 >nul
title SillyTavern Windows 安装脚本
setlocal EnableExtensions DisableDelayedExpansion

REM -----------------------------------------------------------------------------
REM 防闪退：双击运行时，强制套一层 cmd /k，脚本异常退出后窗口仍保留
REM -----------------------------------------------------------------------------
if /i not "%~1"=="--inner" (
    cmd /k ""%~f0" --inner"
    exit /b
)

set "CURRENT_DIR=%~dp0"
cd /d "%CURRENT_DIR%"
set "CURRENT_DIR=%cd%"
set "PROJECT_DIR=%CURRENT_DIR%\SillyTavern"

set "LOG_FILE=%CURRENT_DIR%\sillytavern-windows-install.log"

set "GIT_FALLBACK_URL=https://github.com/git-for-windows/git/releases/download/v2.45.2.windows.1/Git-2.45.2-64-bit.exe"
set "NODE_FALLBACK_URL=https://nodejs.org/dist/v20.11.1/node-v20.11.1-x64.msi"

set "GIT_INSTALLER=%TEMP%\Git-Setup.exe"
set "NODE_INSTALLER=%TEMP%\NodeJS-Setup.msi"

set "GIT_STATUS=未检测"
set "NODE_STATUS=未检测"
set "NPM_STATUS=未检测"

echo ================================================== > "%LOG_FILE%"
echo SillyTavern Windows 安装日志 >> "%LOG_FILE%"
echo 时间: %date% %time% >> "%LOG_FILE%"
echo 当前目录: "%CURRENT_DIR%" >> "%LOG_FILE%"
echo ================================================== >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"

echo 当前工作目录: "%CURRENT_DIR%"
echo 日志文件: "%LOG_FILE%"
echo.

REM -----------------------------------------------------------------------------
REM 管理员权限检查
REM -----------------------------------------------------------------------------
net session >nul 2>&1
if errorlevel 1 (
    call :Fail "请以管理员身份运行此脚本。"
)

echo 已获取管理员权限。
echo 已获取管理员权限。>> "%LOG_FILE%"
echo.

REM -----------------------------------------------------------------------------
REM PowerShell 检查
REM -----------------------------------------------------------------------------
where powershell >nul 2>&1
if errorlevel 1 (
    call :Fail "未找到 PowerShell，无法继续。"
)

REM -----------------------------------------------------------------------------
REM x64 检查
REM -----------------------------------------------------------------------------
if /i not "%PROCESSOR_ARCHITECTURE%"=="AMD64" (
    if /i not "%PROCESSOR_ARCHITEW6432%"=="AMD64" (
        call :Fail "当前脚本仅提供 x64 Git / Node.js 安装包。"
    )
)

REM -----------------------------------------------------------------------------
REM 网络信息
REM -----------------------------------------------------------------------------
echo 正在获取网络信息...
echo 正在获取网络信息...>> "%LOG_FILE%"
call :GetPublicInfo
echo.

REM -----------------------------------------------------------------------------
REM 安装 / 检查 Git
REM -----------------------------------------------------------------------------
echo -----------------------------------
echo [1/3] 检测 Git 环境...
echo [1/3] 检测 Git 环境...>> "%LOG_FILE%"
call :EnsureGit
if errorlevel 1 (
    call :Fail "Git 安装或检测失败。"
)
echo Git 状态: %GIT_STATUS%
echo Git 状态: %GIT_STATUS%>> "%LOG_FILE%"
echo.

REM -----------------------------------------------------------------------------
REM 安装 / 检查 Node.js
REM -----------------------------------------------------------------------------
echo -----------------------------------
echo [2/3] 检测 Node.js 环境...
echo [2/3] 检测 Node.js 环境...>> "%LOG_FILE%"
call :EnsureNode
if errorlevel 1 (
    call :Fail "Node.js 安装或检测失败。"
)
echo Node.js 状态: %NODE_STATUS%
echo Node.js 状态: %NODE_STATUS%>> "%LOG_FILE%"
echo.

REM -----------------------------------------------------------------------------
REM 检查 npm
REM -----------------------------------------------------------------------------
echo -----------------------------------
echo [3/3] 检测 npm 环境...
echo [3/3] 检测 npm 环境...>> "%LOG_FILE%"
call :EnsureNpm
if errorlevel 1 (
    call :Fail "npm 不可用，请重新安装 Node.js。"
)
echo npm 状态: %NPM_STATUS%
echo npm 状态: %NPM_STATUS%>> "%LOG_FILE%"
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
echo 项目目录: "%PROJECT_DIR%">> "%LOG_FILE%"
echo.

call :SetupProject
if errorlevel 1 (
    call :Fail "项目下载或更新失败。"
)

call :StartProject
if errorlevel 1 (
    call :Fail "项目启动失败。"
)

echo.
echo 操作完成。
echo 操作完成。>> "%LOG_FILE%"
echo 日志文件: "%LOG_FILE%"
pause
exit /b 0

REM =============================================================================
REM 函数区
REM =============================================================================

:Fail
echo.
echo 错误: %~1
echo 错误: %~1>> "%LOG_FILE%"
echo.
echo 日志文件: "%LOG_FILE%"
echo 请把日志文件中的最后 50 行发出来，方便定位具体闪退原因。
echo.
pause
exit /b 1

:GetPublicInfo
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='SilentlyContinue';" ^
  "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;" ^
  "$ip=(New-Object Net.WebClient).DownloadString('https://api.ipify.org');" ^
  "if($ip){Write-Host ('当前公网 IP: ' + $ip)}else{Write-Host '当前公网 IP: 获取失败'}" >> "%LOG_FILE%" 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='SilentlyContinue';" ^
  "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;" ^
  "$ip=(New-Object Net.WebClient).DownloadString('https://api.ipify.org');" ^
  "if($ip){Write-Host ('当前公网 IP: ' + $ip)}else{Write-Host '当前公网 IP: 获取失败'}"

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

echo 下载地址: %DOWNLOAD_URL%
echo 输出文件: %DOWNLOAD_OUT%
echo 下载地址: %DOWNLOAD_URL%>> "%LOG_FILE%"
echo 输出文件: %DOWNLOAD_OUT%>> "%LOG_FILE%"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;" ^
  "$wc=New-Object Net.WebClient;" ^
  "$wc.DownloadFile('%DOWNLOAD_URL%', '%DOWNLOAD_OUT%');" >> "%LOG_FILE%" 2>&1

if errorlevel 1 exit /b 1
if not exist "%DOWNLOAD_OUT%" exit /b 1
exit /b 0

:InstallByWinget
set "WINGET_ID=%~1"

where winget >nul 2>&1
if errorlevel 1 (
    echo 未检测到 winget。>> "%LOG_FILE%"
    exit /b 1
)

echo 使用 winget 安装: %WINGET_ID%
echo 使用 winget 安装: %WINGET_ID%>> "%LOG_FILE%"

winget install --id "%WINGET_ID%" -e --silent --accept-package-agreements --accept-source-agreements >> "%LOG_FILE%" 2>&1
if errorlevel 1 exit /b 1

exit /b 0

:EnsureGit
call :RefreshPath

where git >nul 2>&1
if not errorlevel 1 (
    for /f "tokens=*" %%i in ('git --version 2^>nul') do set "GIT_STATUS=%%i"
    exit /b 0
)

echo 未检测到 Git，尝试使用 winget 安装...
echo 未检测到 Git，尝试使用 winget 安装...>> "%LOG_FILE%"

call :InstallByWinget "Git.Git"
if errorlevel 1 (
    echo winget 安装 Git 失败，改用安装包方式。
    echo winget 安装 Git 失败，改用安装包方式。>> "%LOG_FILE%"

    if exist "%GIT_INSTALLER%" del /f /q "%GIT_INSTALLER%" >nul 2>&1

    echo 正在下载 Git 安装包...
    call :DownloadFile "%GIT_FALLBACK_URL%" "%GIT_INSTALLER%"
    if errorlevel 1 exit /b 1

    echo 正在静默安装 Git...
    echo 正在静默安装 Git...>> "%LOG_FILE%"
    start /wait "" "%GIT_INSTALLER%" /VERYSILENT /NORESTART /NOCANCEL /SP- >> "%LOG_FILE%" 2>&1
    if errorlevel 1 exit /b 1

    del /f /q "%GIT_INSTALLER%" >nul 2>&1
)

call :RefreshPath

where git >nul 2>&1
if errorlevel 1 exit /b 1

for /f "tokens=*" %%i in ('git --version 2^>nul') do set "GIT_STATUS=%%i"
exit /b 0

:EnsureNode
call :RefreshPath

where node >nul 2>&1
if not errorlevel 1 (
    for /f "tokens=*" %%i in ('node --version 2^>nul') do set "NODE_STATUS=%%i"
    exit /b 0
)

echo 未检测到 Node.js，尝试使用 winget 安装...
echo 未检测到 Node.js，尝试使用 winget 安装...>> "%LOG_FILE%"

call :InstallByWinget "OpenJS.NodeJS.LTS"
if errorlevel 1 (
    echo winget 安装 Node.js 失败，改用 MSI 安装包方式。
    echo winget 安装 Node.js 失败，改用 MSI 安装包方式。>> "%LOG_FILE%"

    if exist "%NODE_INSTALLER%" del /f /q "%NODE_INSTALLER%" >nul 2>&1

    echo 正在下载 Node.js 安装包...
    call :DownloadFile "%NODE_FALLBACK_URL%" "%NODE_INSTALLER%"
    if errorlevel 1 exit /b 1

    echo 正在静默安装 Node.js...
    echo 正在静默安装 Node.js...>> "%LOG_FILE%"
    start /wait msiexec /i "%NODE_INSTALLER%" /qn /norestart >> "%LOG_FILE%" 2>&1
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
    echo 未检测到 SillyTavern，开始克隆项目...>> "%LOG_FILE%"
    git clone "https://github.com/SillyTavern/SillyTavern.git" "%PROJECT_DIR%" >> "%LOG_FILE%" 2>&1
    if errorlevel 1 exit /b 1
    echo 项目克隆成功。
    echo 项目克隆成功。>> "%LOG_FILE%"
    exit /b 0
)

if not exist "%PROJECT_DIR%\.git" (
    echo 错误: 已存在 "%PROJECT_DIR%"，但它不是 Git 仓库。
    echo 为避免覆盖用户文件，请手动处理该目录后重新运行脚本。
    echo 错误: 已存在 "%PROJECT_DIR%"，但它不是 Git 仓库。>> "%LOG_FILE%"
    exit /b 1
)

echo 检测到已存在 SillyTavern 项目。
choice /c YN /m "是否更新项目？Y=更新，N=跳过"
if errorlevel 2 (
    echo 已跳过项目更新。
    echo 已跳过项目更新。>> "%LOG_FILE%"
    exit /b 0
)

echo 正在更新项目...
echo 正在更新项目...>> "%LOG_FILE%"
git -C "%PROJECT_DIR%" pull --ff-only >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo 项目更新失败。可能存在本地修改或网络问题。
    echo 项目更新失败。可能存在本地修改或网络问题。>> "%LOG_FILE%"
    exit /b 1
)

echo 项目更新成功。
echo 项目更新成功。>> "%LOG_FILE%"
exit /b 0

:StartProject
if not exist "%PROJECT_DIR%\start.bat" (
    echo 错误: 未找到 "%PROJECT_DIR%\start.bat"。
    echo 错误: 未找到 "%PROJECT_DIR%\start.bat"。>> "%LOG_FILE%"
    exit /b 1
)

echo 正在启动 SillyTavern...
echo 正在启动 SillyTavern...>> "%LOG_FILE%"

start "SillyTavern" cmd /k "cd /d "%PROJECT_DIR%" && cmd /c call start.bat & echo. & echo SillyTavern 已退出或启动失败，请查看上方错误。 & echo. & pause"

echo 已启动 SillyTavern。
echo 已启动 SillyTavern。>> "%LOG_FILE%"
exit /b 0
