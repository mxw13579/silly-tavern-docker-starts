@echo off
chcp 65001 >nul
title SillyTavern Windows 安装脚本
setlocal EnableExtensions DisableDelayedExpansion

if /i not "%~1"=="--inner" (
    cmd /k ""%~f0" --inner"
    exit /b
)

set "CURRENT_DIR=%~dp0"
cd /d "%CURRENT_DIR%"
set "CURRENT_DIR=%cd%"
set "PROJECT_DIR=%CURRENT_DIR%\SillyTavern"
set "INSTALLER_DIR=%CURRENT_DIR%\_installers"
set "LOG_FILE=%CURRENT_DIR%\sillytavern-windows-install.log"

set "GIT_URL=https://github.com/git-for-windows/git/releases/download/v2.45.2.windows.1/Git-2.45.2-64-bit.exe"
set "NODE_URL=https://nodejs.org/dist/v20.11.1/node-v20.11.1-x64.msi"
set "ST_ZIP_URL=https://github.com/SillyTavern/SillyTavern/archive/refs/heads/release.zip"

set "GIT_INSTALLER=%INSTALLER_DIR%\Git-Setup.exe"
set "NODE_INSTALLER=%INSTALLER_DIR%\NodeJS-Setup.msi"
set "ST_ZIP=%INSTALLER_DIR%\SillyTavern.zip"
set "ST_ZIP_DIR=%INSTALLER_DIR%\SillyTavern_zip"

set "GIT_STATUS=未检测"
set "NODE_STATUS=未检测"
set "NPM_STATUS=未检测"
set "NODE_EXE="
set "NODE_DIR="
set "NPM_CMD="
set "POWERSHELL_EXE="
set "CURL_EXE="

if not exist "%INSTALLER_DIR%" mkdir "%INSTALLER_DIR%" >nul 2>&1

echo ================================================== > "%LOG_FILE%"
echo SillyTavern Windows 安装日志 >> "%LOG_FILE%"
echo 时间: %date% %time% >> "%LOG_FILE%"
echo 当前目录: "%CURRENT_DIR%" >> "%LOG_FILE%"
echo 安装包目录: "%INSTALLER_DIR%" >> "%LOG_FILE%"
echo ================================================== >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"

call :RepairPath
call :FindTools

echo 当前工作目录: "%CURRENT_DIR%"
echo 日志文件: "%LOG_FILE%"
echo PowerShell: "%POWERSHELL_EXE%"
echo curl: "%CURL_EXE%"
echo.

echo 当前工作目录: "%CURRENT_DIR%" >> "%LOG_FILE%"
echo PowerShell: "%POWERSHELL_EXE%" >> "%LOG_FILE%"
echo curl: "%CURL_EXE%" >> "%LOG_FILE%"

net session >nul 2>&1
if errorlevel 1 call :Fail "请右键此脚本，选择【以管理员身份运行】。"

echo 已获取管理员权限。
echo 已获取管理员权限。>> "%LOG_FILE%"
echo.

echo -----------------------------------
echo [1/4] 检测 Git 环境...
echo [1/4] 检测 Git 环境...>> "%LOG_FILE%"
call :EnsureGit
if errorlevel 1 call :Fail "Git 安装或检测失败。"
echo Git 状态: %GIT_STATUS%
echo Git 状态: %GIT_STATUS%>> "%LOG_FILE%"
echo.

echo -----------------------------------
echo [2/4] 检测 Node.js 环境...
echo [2/4] 检测 Node.js 环境...>> "%LOG_FILE%"
call :EnsureNode
if errorlevel 1 call :Fail "Node.js 安装或检测失败。"
echo Node.js 状态: %NODE_STATUS%
echo Node.js 状态: %NODE_STATUS%>> "%LOG_FILE%"
echo.

echo -----------------------------------
echo [3/4] 检测 npm 环境...
echo [3/4] 检测 npm 环境...>> "%LOG_FILE%"
call :EnsureNpm
if errorlevel 1 call :Fail "npm 不可用，请重新安装 Node.js。"
echo npm 状态: %NPM_STATUS%
echo npm 状态: %NPM_STATUS%>> "%LOG_FILE%"
echo.

echo -----------------------------------
echo [4/4] 下载 / 更新 SillyTavern...
echo [4/4] 下载 / 更新 SillyTavern...>> "%LOG_FILE%"
call :SetupProject
if errorlevel 1 call :Fail "项目下载或更新失败。"
echo.

call :StartProject
if errorlevel 1 call :Fail "项目启动失败。"

echo.
echo 操作完成。
echo 操作完成。>> "%LOG_FILE%"
echo 日志文件: "%LOG_FILE%"
pause
exit /b 0


:RepairPath
set "PATH=%SystemRoot%\System32;%SystemRoot%;%SystemRoot%\System32\Wbem;%SystemRoot%\System32\WindowsPowerShell\v1.0;%LOCALAPPDATA%\Microsoft\WindowsApps;%ProgramFiles%\Git\cmd;%ProgramFiles%\nodejs;%LOCALAPPDATA%\Programs\nodejs;%APPDATA%\npm;%PATH%"
exit /b 0


:FindTools
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "POWERSHELL_EXE=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
if not defined POWERSHELL_EXE if exist "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" set "POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

if exist "%SystemRoot%\Sysnative\curl.exe" set "CURL_EXE=%SystemRoot%\Sysnative\curl.exe"
if not defined CURL_EXE if exist "%SystemRoot%\System32\curl.exe" set "CURL_EXE=%SystemRoot%\System32\curl.exe"

if not defined CURL_EXE (
    for /f "tokens=*" %%i in ('where curl 2^>nul') do (
        if not defined CURL_EXE set "CURL_EXE=%%i"
    )
)

exit /b 0


:Fail
echo.
echo 错误: %~1
echo 错误: %~1>> "%LOG_FILE%"
echo.
echo ---------------- 日志最后 80 行 ----------------
call :TailLog
echo -------------------------------------------------
echo.
goto :Abort


:Abort
echo 脚本已停止。
echo 请优先检查：
echo 1. Windows PowerShell 是否存在。
echo 2. 系统 PATH 是否损坏。
echo 3. 杀毒软件是否拦截 Git / Node / clone。
echo 4. 网络是否能访问 GitHub / nodejs.org。
echo 5. 如果 Node.js 反复 1603，请先卸载 Node.js 并重启。
echo.
pause
exit /b 1


:TailLog
if defined POWERSHELL_EXE (
    "%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -LiteralPath '%LOG_FILE%' -Tail 80 -Encoding UTF8" 2>nul
) else (
    type "%LOG_FILE%"
)
exit /b 0


:RefreshPath
call :RepairPath

set "MACHINE_PATH="
set "USER_PATH="

for /f "tokens=2,*" %%A in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul') do set "MACHINE_PATH=%%B"
for /f "tokens=2,*" %%A in ('reg query "HKCU\Environment" /v Path 2^>nul') do set "USER_PATH=%%B"

if defined MACHINE_PATH set "PATH=%SystemRoot%\System32;%SystemRoot%;%SystemRoot%\System32\Wbem;%SystemRoot%\System32\WindowsPowerShell\v1.0;%MACHINE_PATH%;%USER_PATH%"
if exist "%ProgramFiles%\Git\cmd\git.exe" set "PATH=%ProgramFiles%\Git\cmd;%PATH%"
if exist "%ProgramFiles%\nodejs\node.exe" set "PATH=%ProgramFiles%\nodejs;%PATH%"
if exist "%LOCALAPPDATA%\Programs\nodejs\node.exe" set "PATH=%LOCALAPPDATA%\Programs\nodejs;%PATH%"
if exist "%APPDATA%\npm\npm.cmd" set "PATH=%APPDATA%\npm;%PATH%"
if exist "%LOCALAPPDATA%\Microsoft\WindowsApps\winget.exe" set "PATH=%LOCALAPPDATA%\Microsoft\WindowsApps;%PATH%"

exit /b 0


:DownloadFile
set "DOWNLOAD_URL=%~1"
set "DOWNLOAD_OUT=%~2"

if exist "%DOWNLOAD_OUT%" del /f /q "%DOWNLOAD_OUT%" >nul 2>&1

echo 下载地址: %DOWNLOAD_URL%
echo 输出文件: %DOWNLOAD_OUT%
echo 下载地址: %DOWNLOAD_URL%>> "%LOG_FILE%"
echo 输出文件: %DOWNLOAD_OUT%>> "%LOG_FILE%"

if defined POWERSHELL_EXE (
    echo 正在使用 PowerShell 下载...
    echo 正在使用 PowerShell 下载...>> "%LOG_FILE%"

    "%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -Command ^
      "$ErrorActionPreference='Stop';" ^
      "$ProgressPreference='SilentlyContinue';" ^
      "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;" ^
      "$url=$env:DOWNLOAD_URL;" ^
      "$out=$env:DOWNLOAD_OUT;" ^
      "$dir=Split-Path -Parent $out;" ^
      "if(!(Test-Path -LiteralPath $dir)){New-Item -ItemType Directory -Path $dir -Force | Out-Null};" ^
      "$wc=New-Object Net.WebClient;" ^
      "$wc.Headers.Add('User-Agent','Mozilla/5.0');" ^
      "$wc.DownloadFile($url,$out);" ^
      "if(!(Test-Path -LiteralPath $out)){throw '下载失败，文件不存在'};" ^
      "$len=(Get-Item -LiteralPath $out).Length;" ^
      "if($len -lt 1048576){throw ('下载文件过小，大小: ' + $len)};" ^
      "Write-Host ('下载成功，大小: ' + $len)" >> "%LOG_FILE%" 2>&1

    if not errorlevel 1 (
        if exist "%DOWNLOAD_OUT%" exit /b 0
    )
)

if defined CURL_EXE (
    echo PowerShell 下载失败或不可用，尝试 curl...
    echo PowerShell 下载失败或不可用，尝试 curl...>> "%LOG_FILE%"

    if exist "%DOWNLOAD_OUT%" del /f /q "%DOWNLOAD_OUT%" >nul 2>&1

    "%CURL_EXE%" -L --fail --retry 3 --retry-delay 2 --connect-timeout 30 --output "%DOWNLOAD_OUT%" "%DOWNLOAD_URL%" >> "%LOG_FILE%" 2>&1
    if errorlevel 1 exit /b 1

    if not exist "%DOWNLOAD_OUT%" exit /b 1

    for %%F in ("%DOWNLOAD_OUT%") do (
        if %%~zF LSS 1048576 (
            echo 下载文件过小，可能是错误页面。>> "%LOG_FILE%"
            exit /b 1
        )
    )

    exit /b 0
)

echo 未找到 PowerShell 或 curl，无法自动下载。>> "%LOG_FILE%"
exit /b 1


:InstallByWinget
set "WINGET_ID=%~1"

call :RefreshPath

where winget >nul 2>&1
if errorlevel 1 (
    echo 未检测到 winget。>> "%LOG_FILE%"
    exit /b 1
)

echo 使用 winget 安装: %WINGET_ID%
echo 使用 winget 安装: %WINGET_ID%>> "%LOG_FILE%"

winget install --id "%WINGET_ID%" -e --silent --accept-package-agreements --accept-source-agreements >> "%LOG_FILE%" 2>&1
exit /b %ERRORLEVEL%


:EnsureGit
call :RefreshPath

where git >nul 2>&1
if not errorlevel 1 (
    for /f "tokens=*" %%i in ('git --version 2^>nul') do set "GIT_STATUS=%%i"
    exit /b 0
)

echo 未检测到 Git，尝试 winget 安装...
echo 未检测到 Git，尝试 winget 安装...>> "%LOG_FILE%"

call :InstallByWinget "Git.Git"
if errorlevel 1 (
    echo winget 安装 Git 失败，改用安装包方式。
    echo winget 安装 Git 失败，改用安装包方式。>> "%LOG_FILE%"

    if exist "%CURRENT_DIR%\Git-Setup.exe" (
        copy /y "%CURRENT_DIR%\Git-Setup.exe" "%GIT_INSTALLER%" >nul
    ) else if exist "%CURRENT_DIR%\Git-2.45.2-64-bit.exe" (
        copy /y "%CURRENT_DIR%\Git-2.45.2-64-bit.exe" "%GIT_INSTALLER%" >nul
    ) else (
        call :DownloadFile "%GIT_URL%" "%GIT_INSTALLER%"
        if errorlevel 1 exit /b 1
    )

    echo 正在静默安装 Git...
    echo 正在静默安装 Git...>> "%LOG_FILE%"
    start /wait "" "%GIT_INSTALLER%" /VERYSILENT /NORESTART /NOCANCEL /SP- >> "%LOG_FILE%" 2>&1
)

call :RefreshPath

where git >nul 2>&1
if errorlevel 1 exit /b 1

for /f "tokens=*" %%i in ('git --version 2^>nul') do set "GIT_STATUS=%%i"
exit /b 0


:DetectNode
set "NODE_STATUS="
set "NODE_EXE="
set "NODE_DIR="
set "NODE_REGISTERED_INFO="
set "NODE_DETECT_FILE=%INSTALLER_DIR%\node-detect.txt"

if exist "%NODE_DETECT_FILE%" del /f /q "%NODE_DETECT_FILE%" >nul 2>&1

for /f "delims=" %%i in ('where node 2^>nul') do (
    if not defined NODE_EXE set "NODE_EXE=%%i"
)

if not defined NODE_EXE if exist "%ProgramFiles%\nodejs\node.exe" set "NODE_EXE=%ProgramFiles%\nodejs\node.exe"
if not defined NODE_EXE if exist "%ProgramFiles(x86)%\nodejs\node.exe" set "NODE_EXE=%ProgramFiles(x86)%\nodejs\node.exe"
if not defined NODE_EXE if exist "%LOCALAPPDATA%\Programs\nodejs\node.exe" set "NODE_EXE=%LOCALAPPDATA%\Programs\nodejs\node.exe"

if defined NODE_EXE goto :VerifyNodeExe

if not defined POWERSHELL_EXE goto :NodeNoPowerShellDetect

"%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='SilentlyContinue';" ^
  "$out=$env:NODE_DETECT_FILE;" ^
  "$candidates=@();" ^
  "$cmd=Get-Command node -ErrorAction SilentlyContinue;" ^
  "if($cmd){$candidates += $cmd.Source};" ^
  "$pf=[Environment]::GetEnvironmentVariable('ProgramFiles');" ^
  "$pf86=[Environment]::GetEnvironmentVariable('ProgramFiles(x86)');" ^
  "$la=[Environment]::GetEnvironmentVariable('LOCALAPPDATA');" ^
  "if($pf){$candidates += Join-Path $pf 'nodejs\node.exe'};" ^
  "if($pf86){$candidates += Join-Path $pf86 'nodejs\node.exe'};" ^
  "if($la){$candidates += Join-Path $la 'Programs\nodejs\node.exe'};" ^
  "$roots=@('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*');" ^
  "$apps=Get-ItemProperty $roots | Where-Object { $_.DisplayName -like '*Node.js*' -or $_.Publisher -like '*OpenJS*' };" ^
  "foreach($a in $apps){ if($a.InstallLocation){ $candidates += Join-Path $a.InstallLocation 'node.exe' } };" ^
  "$exe=$candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1;" ^
  "if($exe){ Set-Content -LiteralPath $out -Value ('EXE=' + $exe) -Encoding ASCII; exit 0 };" ^
  "if($apps){ $a=$apps | Select-Object -First 1; Set-Content -LiteralPath $out -Value ('REGISTERED=' + $a.DisplayName + ' ' + $a.DisplayVersion + ' InstallLocation=' + $a.InstallLocation) -Encoding ASCII; exit 2 };" ^
  "exit 1" >nul 2>&1

if exist "%NODE_DETECT_FILE%" (
    for /f "usebackq tokens=1,* delims==" %%A in ("%NODE_DETECT_FILE%") do (
        if /i "%%A"=="EXE" set "NODE_EXE=%%B"
        if /i "%%A"=="REGISTERED" set "NODE_REGISTERED_INFO=%%B"
    )
)

:NodeNoPowerShellDetect
if defined NODE_EXE goto :VerifyNodeExe

if defined NODE_REGISTERED_INFO (
    echo 检测到 Node.js 安装记录，但未找到可用 node.exe。
    echo 检测到 Node.js 安装记录，但未找到可用 node.exe。>> "%LOG_FILE%"
    echo 安装记录: %NODE_REGISTERED_INFO%
    echo 安装记录: %NODE_REGISTERED_INFO%>> "%LOG_FILE%"
    exit /b 2
)

exit /b 1


:VerifyNodeExe
for %%F in ("%NODE_EXE%") do set "NODE_DIR=%%~dpF"

if defined NODE_DIR set "PATH=%NODE_DIR%;%NODE_DIR%node_modules\npm\bin;%APPDATA%\npm;%PATH%"

for /f "tokens=*" %%i in ('"%NODE_EXE%" --version 2^>nul') do set "NODE_STATUS=%%i"

if not defined NODE_STATUS (
    echo 找到 node.exe，但无法执行: %NODE_EXE%
    echo 找到 node.exe，但无法执行: %NODE_EXE%>> "%LOG_FILE%"
    exit /b 1
)

echo 检测到 Node.js: %NODE_EXE%
echo 检测到 Node.js: %NODE_EXE%>> "%LOG_FILE%"
echo Node.js 版本: %NODE_STATUS%
echo Node.js 版本: %NODE_STATUS%>> "%LOG_FILE%"

exit /b 0


:EnsureNode
call :RefreshPath

call :DetectNode
set "NODE_DETECT_CODE=%ERRORLEVEL%"

if "%NODE_DETECT_CODE%"=="0" exit /b 0

if "%NODE_DETECT_CODE%"=="2" (
    echo.
    echo 系统里已有 Node.js 安装记录或残留，但脚本找不到可用 node.exe。
    echo 所以继续安装会反复触发 1603。
    echo.
    echo 请先清理 Node.js 后重新运行脚本：
    echo 1. 设置 - 应用 - 已安装的应用 - 卸载 Node.js
    echo 2. 或 控制面板 - 程序和功能 - 卸载 Node.js
    echo 3. 或 管理员终端执行：winget uninstall --id OpenJS.NodeJS.LTS -e
    echo.
    echo 清理后建议重启 Windows。
    echo.
    echo 系统里已有 Node.js 安装记录或残留，但脚本找不到可用 node.exe。>> "%LOG_FILE%"
    echo 继续安装会反复触发 1603。>> "%LOG_FILE%"
    echo 请卸载 Node.js 后重启，再重新运行脚本。>> "%LOG_FILE%"
    exit /b 1
)

echo 未检测到 Node.js，尝试 winget 安装...
echo 未检测到 Node.js，尝试 winget 安装...>> "%LOG_FILE%"

call :InstallByWinget "OpenJS.NodeJS.LTS"
set "WINGET_EXIT_CODE=%ERRORLEVEL%"

echo winget 安装命令返回码: %WINGET_EXIT_CODE%
echo winget 安装命令返回码: %WINGET_EXIT_CODE%>> "%LOG_FILE%"

echo winget 安装结束，重新检测 Node.js...
echo winget 安装结束，重新检测 Node.js...>> "%LOG_FILE%"

call :RefreshPath

call :DetectNode
set "NODE_DETECT_CODE=%ERRORLEVEL%"

if "%NODE_DETECT_CODE%"=="0" exit /b 0

if "%NODE_DETECT_CODE%"=="2" (
    echo.
    echo winget 后检测到 Node.js 安装记录，但 node.exe 不可用。
    echo 为避免继续触发 1603，脚本不会再尝试 MSI 安装。
    echo 请卸载 Node.js，重启 Windows 后重新运行脚本。
    echo.
    echo winget 后检测到 Node.js 安装记录，但 node.exe 不可用。>> "%LOG_FILE%"
    echo 为避免继续触发 1603，跳过 MSI fallback。>> "%LOG_FILE%"
    exit /b 1
)

echo winget 后仍未检测到 Node.js，改用 MSI 安装包方式。
echo winget 后仍未检测到 Node.js，改用 MSI 安装包方式。>> "%LOG_FILE%"

if exist "%CURRENT_DIR%\NodeJS-Setup.msi" (
    copy /y "%CURRENT_DIR%\NodeJS-Setup.msi" "%NODE_INSTALLER%" >nul
) else if exist "%CURRENT_DIR%\node-v20.11.1-x64.msi" (
    copy /y "%CURRENT_DIR%\node-v20.11.1-x64.msi" "%NODE_INSTALLER%" >nul
) else (
    call :DownloadFile "%NODE_URL%" "%NODE_INSTALLER%"
    if errorlevel 1 exit /b 1
)

echo 正在静默安装 Node.js MSI...
echo 正在静默安装 Node.js MSI...>> "%LOG_FILE%"

msiexec /i "%NODE_INSTALLER%" /qn /norestart ADDLOCAL=ALL >> "%LOG_FILE%" 2>&1
set "MSI_EXIT_CODE=%ERRORLEVEL%"

echo Node.js MSI 安装返回码: %MSI_EXIT_CODE%
echo Node.js MSI 安装返回码: %MSI_EXIT_CODE%>> "%LOG_FILE%"

if "%MSI_EXIT_CODE%"=="3010" (
    echo Node.js MSI 安装成功，但系统提示需要重启。
    echo Node.js MSI 安装成功，但系统提示需要重启。>> "%LOG_FILE%"
) else if not "%MSI_EXIT_CODE%"=="0" (
    echo Node.js MSI 安装失败，返回码: %MSI_EXIT_CODE%
    echo Node.js MSI 安装失败，返回码: %MSI_EXIT_CODE%>> "%LOG_FILE%"
    echo 如果返回码是 1603，通常表示系统存在 Node.js 旧安装、残留安装记录、降级冲突或 Windows Installer 状态异常。
    echo 如果返回码是 1603，通常表示系统存在 Node.js 旧安装、残留安装记录、降级冲突或 Windows Installer 状态异常。>> "%LOG_FILE%"
    echo 请卸载 Node.js，重启 Windows 后重新运行脚本。
    echo 请卸载 Node.js，重启 Windows 后重新运行脚本。>> "%LOG_FILE%"
    exit /b 1
)

call :RefreshPath

call :DetectNode
if not errorlevel 1 exit /b 0

echo MSI 安装后仍未检测到 node.exe。
echo MSI 安装后仍未检测到 node.exe。>> "%LOG_FILE%"
echo 请重启 Windows 后重新运行脚本。
echo 请重启 Windows 后重新运行脚本。>> "%LOG_FILE%"

exit /b 1


:DetectNpm
set "NPM_STATUS="
set "NPM_CMD="

for /f "delims=" %%i in ('where npm.cmd 2^>nul') do (
    if not defined NPM_CMD set "NPM_CMD=%%i"
)

if not defined NPM_CMD if defined NODE_DIR if exist "%NODE_DIR%npm.cmd" set "NPM_CMD=%NODE_DIR%npm.cmd"
if not defined NPM_CMD if exist "%ProgramFiles%\nodejs\npm.cmd" set "NPM_CMD=%ProgramFiles%\nodejs\npm.cmd"
if not defined NPM_CMD if exist "%ProgramFiles(x86)%\nodejs\npm.cmd" set "NPM_CMD=%ProgramFiles(x86)%\nodejs\npm.cmd"
if not defined NPM_CMD if exist "%LOCALAPPDATA%\Programs\nodejs\npm.cmd" set "NPM_CMD=%LOCALAPPDATA%\Programs\nodejs\npm.cmd"

if not defined NPM_CMD exit /b 1

for /f "tokens=*" %%i in ('call "%NPM_CMD%" --version 2^>nul') do set "NPM_STATUS=%%i"

if not defined NPM_STATUS exit /b 1

echo 检测到 npm: %NPM_CMD%
echo 检测到 npm: %NPM_CMD%>> "%LOG_FILE%"
echo npm 版本: %NPM_STATUS%
echo npm 版本: %NPM_STATUS%>> "%LOG_FILE%"

exit /b 0


:EnsureNpm
call :RefreshPath

call :DetectNode
if errorlevel 1 exit /b 1

call :DetectNpm
if errorlevel 1 exit /b 1

exit /b 0


:SetupProject
cd /d "%CURRENT_DIR%"

if exist "%PROJECT_DIR%" (
    if not exist "%PROJECT_DIR%\start.bat" (
        echo 检测到不完整的 SillyTavern 目录，正在备份旧目录...
        echo 检测到不完整的 SillyTavern 目录，正在备份旧目录...>> "%LOG_FILE%"
        ren "%PROJECT_DIR%" "SillyTavern_broken_%RANDOM%" >> "%LOG_FILE%" 2>&1
    )
)

if exist "%PROJECT_DIR%\start.bat" (
    if exist "%PROJECT_DIR%\.git" (
        echo 检测到已存在 Git 项目，尝试更新...
        echo 检测到已存在 Git 项目，尝试更新...>> "%LOG_FILE%"

        git -C "%PROJECT_DIR%" pull --ff-only >> "%LOG_FILE%" 2>&1
        if errorlevel 1 (
            echo 更新失败，跳过更新，继续启动现有项目。
            echo 更新失败，跳过更新，继续启动现有项目。>> "%LOG_FILE%"
        )
    ) else (
        echo 检测到 ZIP 版项目，跳过 Git 更新。
        echo 检测到 ZIP 版项目，跳过 Git 更新。>> "%LOG_FILE%"
    )
    exit /b 0
)

echo 配置 Git 网络参数...
echo 配置 Git 网络参数...>> "%LOG_FILE%"

git config --global http.version HTTP/1.1 >> "%LOG_FILE%" 2>&1
git config --global core.compression 0 >> "%LOG_FILE%" 2>&1
git config --global http.postBuffer 524288000 >> "%LOG_FILE%" 2>&1

echo 开始克隆 SillyTavern...
echo 开始克隆 SillyTavern...>> "%LOG_FILE%"

git clone --depth 1 "https://github.com/SillyTavern/SillyTavern.git" "%PROJECT_DIR%" >> "%LOG_FILE%" 2>&1
if not errorlevel 1 (
    if exist "%PROJECT_DIR%\start.bat" exit /b 0
)

echo Git 克隆失败，删除半成品并尝试 ZIP 下载...
echo Git 克隆失败，删除半成品并尝试 ZIP 下载...>> "%LOG_FILE%"

if exist "%PROJECT_DIR%" rmdir /s /q "%PROJECT_DIR%" >> "%LOG_FILE%" 2>&1

call :DownloadFile "%ST_ZIP_URL%" "%ST_ZIP%"
if errorlevel 1 exit /b 1

if not defined POWERSHELL_EXE (
    echo 无 PowerShell，无法解压 ZIP。>> "%LOG_FILE%"
    exit /b 1
)

if exist "%ST_ZIP_DIR%" rmdir /s /q "%ST_ZIP_DIR%" >> "%LOG_FILE%" 2>&1

"%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$zip=$env:ST_ZIP;" ^
  "$out=$env:ST_ZIP_DIR;" ^
  "$dst=$env:PROJECT_DIR;" ^
  "Expand-Archive -LiteralPath $zip -DestinationPath $out -Force;" ^
  "$src=Get-ChildItem -LiteralPath $out -Directory | Select-Object -First 1;" ^
  "if(!$src){throw 'ZIP 解压后未找到项目目录'};" ^
  "Move-Item -LiteralPath $src.FullName -Destination $dst -Force;" >> "%LOG_FILE%" 2>&1

if errorlevel 1 exit /b 1
if not exist "%PROJECT_DIR%\start.bat" exit /b 1

exit /b 0


:StartProject
if not exist "%PROJECT_DIR%\start.bat" (
    echo 未找到 "%PROJECT_DIR%\start.bat"。>> "%LOG_FILE%"
    exit /b 1
)

echo 正在启动 SillyTavern...
echo 正在启动 SillyTavern...>> "%LOG_FILE%"

start "SillyTavern" cmd /k "cd /d ""%PROJECT_DIR%"" && call start.bat & echo. & echo SillyTavern 已退出或启动失败，请查看上方错误。 & echo. & pause"

echo 已启动 SillyTavern。
echo 已启动 SillyTavern。>> "%LOG_FILE%"
exit /b 0
