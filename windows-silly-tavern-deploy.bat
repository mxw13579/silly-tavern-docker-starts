@echo off
chcp 65001 >nul
title SillyTavern Windows 国内加速安装脚本
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
set "INSTALLER_NPMRC=%INSTALLER_DIR%\npmrc"

set "GIT_VERSION=2.54.0"
set "GIT_RELEASE_VERSION=%GIT_VERSION%.windows.1"
set "NODE_VERSION=24.16.0"
set "GIT_URL=https://npmmirror.com/mirrors/git-for-windows/v%GIT_RELEASE_VERSION%/Git-%GIT_VERSION%-64-bit.exe"
set "NODE_URL=https://npmmirror.com/mirrors/node/v%NODE_VERSION%/node-v%NODE_VERSION%-x64.msi"
set "NPM_REGISTRY=https://registry.npmmirror.com"

set "ST_GIT_URL=https://github.com/SillyTavern/SillyTavern.git"
set "ST_RELEASE_HEAD_API=https://api.github.com/repos/SillyTavern/SillyTavern/git/ref/heads/release"
set "ST_GIT_URL_PROXY_1=https://gh-proxy.com/https://github.com/SillyTavern/SillyTavern.git"
set "ST_GIT_URL_PROXY_2=https://hubp.llkk.cc/https://github.com/SillyTavern/SillyTavern.git"

set "ST_ZIP_URL=https://github.com/SillyTavern/SillyTavern/archive/refs/heads/release.zip"
set "ST_ZIP_URL_PROXY_1=https://gh-proxy.com/https://github.com/SillyTavern/SillyTavern/archive/refs/heads/release.zip"
set "ST_ZIP_URL_PROXY_2=https://gh.llkk.cc/https://github.com/SillyTavern/SillyTavern/archive/refs/heads/release.zip"

if not defined ALLOW_THIRD_PARTY_PROXY set "ALLOW_THIRD_PARTY_PROXY=ASK"
if not defined REQUIRE_PROXY_COMMIT_VERIFY set "REQUIRE_PROXY_COMMIT_VERIFY=1"
if not defined REQUIRE_INSTALLER_SHA256 set "REQUIRE_INSTALLER_SHA256=0"
if not defined NO_INTERACTIVE set "NO_INTERACTIVE=0"
if not defined EXPECTED_ST_RELEASE_HEAD set "EXPECTED_ST_RELEASE_HEAD="

if not defined GIT_INSTALLER_SHA256 set "GIT_INSTALLER_SHA256="
if not defined NODE_INSTALLER_SHA256 set "NODE_INSTALLER_SHA256="
if not defined GIT_SIGNER_THUMBPRINTS set "GIT_SIGNER_THUMBPRINTS="
if not defined NODE_SIGNER_THUMBPRINTS set "NODE_SIGNER_THUMBPRINTS="

set "THIRD_PARTY_PROXY_CONFIRMED=0"
set "THIRD_PARTY_PROXY_PROMPTED=0"
set "OFFICIAL_RELEASE_HEAD="
set "FETCH_SOURCE_USED="
set "PROJECT_SOURCE_USED=未确定"

set "GIT_LOW_SPEED_LIMIT=1"
set "GIT_LOW_SPEED_TIME=120"

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
echo SillyTavern Windows 国内加速安装日志 >> "%LOG_FILE%"
echo 本酒馆安装脚本由FuFu提供 >> "%LOG_FILE%"
echo 交流反馈群 | 878941467 >> "%LOG_FILE%"
echo 时间: %date% %time% >> "%LOG_FILE%"
echo 当前目录: "%CURRENT_DIR%" >> "%LOG_FILE%"
echo 安装包目录: "%INSTALLER_DIR%" >> "%LOG_FILE%"
echo ALLOW_THIRD_PARTY_PROXY=%ALLOW_THIRD_PARTY_PROXY% >> "%LOG_FILE%"
echo REQUIRE_PROXY_COMMIT_VERIFY=%REQUIRE_PROXY_COMMIT_VERIFY% >> "%LOG_FILE%"
echo REQUIRE_INSTALLER_SHA256=%REQUIRE_INSTALLER_SHA256% >> "%LOG_FILE%"
echo NO_INTERACTIVE=%NO_INTERACTIVE% >> "%LOG_FILE%"
echo EXPECTED_ST_RELEASE_HEAD=%EXPECTED_ST_RELEASE_HEAD% >> "%LOG_FILE%"
echo ================================================== >> "%LOG_FILE%"
echo. >> "%LOG_FILE%"

call :RepairPath
call :FindTools

echo 当前工作目录: "%CURRENT_DIR%"
echo 日志文件: "%LOG_FILE%"
echo 本酒馆安装脚本由FuFu提供
echo 交流反馈群 | 878941467
echo PowerShell: "%POWERSHELL_EXE%"
echo curl: "%CURL_EXE%"
echo.
echo 警告：第三方 GitHub 代理不是官方服务，仅建议用于公开仓库。
echo 若 REQUIRE_PROXY_COMMIT_VERIFY=1，代理 clone 必须和官方 release HEAD 校验一致。
echo GitHub 不可达但需要代理校验时，可预设 EXPECTED_ST_RELEASE_HEAD。
echo 无人值守禁用代理：set ALLOW_THIRD_PARTY_PROXY=0
echo 无人值守启用代理：set ALLOW_THIRD_PARTY_PROXY=1
echo.

echo 当前工作目录: "%CURRENT_DIR%" >> "%LOG_FILE%"
echo PowerShell: "%POWERSHELL_EXE%" >> "%LOG_FILE%"
echo curl: "%CURL_EXE%" >> "%LOG_FILE%"

if /i "%REQUIRE_INSTALLER_SHA256%"=="0" (
    echo 警告：REQUIRE_INSTALLER_SHA256=0，安装包未启用固定 SHA256 校验。
    echo 建议设置 GIT_INSTALLER_SHA256 / NODE_INSTALLER_SHA256 并启用 REQUIRE_INSTALLER_SHA256=1。
    echo.
    echo 警告：REQUIRE_INSTALLER_SHA256=0，安装包未启用固定 SHA256 校验。>> "%LOG_FILE%"
    echo 建议设置 GIT_INSTALLER_SHA256 / NODE_INSTALLER_SHA256 并启用 REQUIRE_INSTALLER_SHA256=1。>> "%LOG_FILE%"
)

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
call :WriteInstallerNpmrc
if errorlevel 1 call :Fail "npm 镜像配置文件写入失败。"
echo npm 状态: %NPM_STATUS%
echo npm 状态: %NPM_STATUS%>> "%LOG_FILE%"
echo.

echo -----------------------------------
echo [4/4] 下载 / 更新 SillyTavern...
echo [4/4] 下载 / 更新 SillyTavern...>> "%LOG_FILE%"
call :SetupProject
if errorlevel 1 call :Fail "项目下载或更新失败。"

echo 最终项目来源: %PROJECT_SOURCE_USED%
echo 最终项目来源: %PROJECT_SOURCE_USED%>> "%LOG_FILE%"

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
echo 4. 网络是否能访问 GitHub / npmmirror.com。
echo 5. 如果 Node.js 反复 1603，请先卸载 Node.js 并重启。
echo 6. 如果代理被拒绝，可设置 ALLOW_THIRD_PARTY_PROXY=1，并自行承担风险。
echo 7. 如果 GitHub 不可达但要校验代理 clone，可设置 EXPECTED_ST_RELEASE_HEAD。
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
            del /f /q "%DOWNLOAD_OUT%" >nul 2>&1
            exit /b 1
        )
    )

    exit /b 0
)

echo 未找到 PowerShell 或 curl，无法自动下载。>> "%LOG_FILE%"
exit /b 1


:VerifyPackage
set "VERIFY_FILE=%~1"
set "VERIFY_NAME=%~2"
set "EXPECTED_SHA256=%~3"
set "SIGNER_HINTS=%~4"
set "SIGNER_THUMBPRINTS=%~5"

if not exist "%VERIFY_FILE%" (
    echo 待校验文件不存在: "%VERIFY_FILE%"
    echo 待校验文件不存在: "%VERIFY_FILE%">> "%LOG_FILE%"
    exit /b 1
)

if /i "%REQUIRE_INSTALLER_SHA256%"=="1" (
    if not defined EXPECTED_SHA256 (
        echo 已启用 REQUIRE_INSTALLER_SHA256=1，但 %VERIFY_NAME% 未提供 SHA256。
        echo 已启用 REQUIRE_INSTALLER_SHA256=1，但 %VERIFY_NAME% 未提供 SHA256。>> "%LOG_FILE%"
        exit /b 1
    )
)

if not defined POWERSHELL_EXE (
    echo 未找到 PowerShell，无法校验 %VERIFY_NAME%。
    echo 未找到 PowerShell，无法校验 %VERIFY_NAME%。>> "%LOG_FILE%"
    exit /b 1
)

echo 正在校验 %VERIFY_NAME% 签名 / 发布者 / Thumbprint / SHA256...
echo 正在校验 %VERIFY_NAME% 签名 / 发布者 / Thumbprint / SHA256...>> "%LOG_FILE%"

"%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$file=$env:VERIFY_FILE;" ^
  "$expected=$env:EXPECTED_SHA256;" ^
  "$hints=$env:SIGNER_HINTS;" ^
  "$thumbprints=$env:SIGNER_THUMBPRINTS;" ^
  "$sig=Get-AuthenticodeSignature -LiteralPath $file;" ^
  "Write-Host ('签名状态: ' + $sig.Status);" ^
  "$subject='';$issuer='';$thumb='';" ^
  "if($sig.SignerCertificate){$subject=$sig.SignerCertificate.Subject;$issuer=$sig.SignerCertificate.Issuer;$thumb=$sig.SignerCertificate.Thumbprint;Write-Host ('签名者: ' + $subject);Write-Host ('颁发者: ' + $issuer);Write-Host ('Thumbprint: ' + $thumb)};" ^
  "if($sig.Status -ne 'Valid'){throw ('签名无效: ' + $sig.Status)};" ^
  "if($thumbprints){" ^
  "  $thumbOk=$false;" ^
  "  foreach($t in ($thumbprints -split '\|')){if($t -and ($thumb -ieq $t.Trim())){$thumbOk=$true}};" ^
  "  if(!$thumbOk){throw ('证书 Thumbprint 不在白名单: ' + $thumb)};" ^
  "}else{" ^
  "  $ok=$false;" ^
  "  foreach($h in ($hints -split '\|')){if($h -and (($subject -like ('*' + $h + '*')) -or ($issuer -like ('*' + $h + '*')))){$ok=$true}};" ^
  "  if(!$ok){throw ('签名者不匹配预期发布者关键字: ' + $hints)};" ^
  "}" ^
  "$actual=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToUpperInvariant();" ^
  "Write-Host ('SHA256: ' + $actual);" ^
  "if($expected -and ($actual -ne $expected.ToUpperInvariant())){throw ('SHA256 不匹配，期望: ' + $expected + ' 实际: ' + $actual)};" >> "%LOG_FILE%" 2>&1

if errorlevel 1 (
    echo %VERIFY_NAME% 校验失败，拒绝继续安装。
    echo %VERIFY_NAME% 校验失败，拒绝继续安装。>> "%LOG_FILE%"
    exit /b 1
)

echo %VERIFY_NAME% 校验通过。
echo %VERIFY_NAME% 校验通过。>> "%LOG_FILE%"
exit /b 0


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
    echo winget 安装 Git 失败，改用 npmmirror 安装包方式。
    echo winget 安装 Git 失败，改用 npmmirror 安装包方式。>> "%LOG_FILE%"

    if exist "%CURRENT_DIR%\Git-Setup.exe" (
        copy /y "%CURRENT_DIR%\Git-Setup.exe" "%GIT_INSTALLER%" >nul
    ) else if exist "%CURRENT_DIR%\Git-%GIT_VERSION%-64-bit.exe" (
        copy /y "%CURRENT_DIR%\Git-%GIT_VERSION%-64-bit.exe" "%GIT_INSTALLER%" >nul
    ) else (
        call :DownloadFile "%GIT_URL%" "%GIT_INSTALLER%"
        if errorlevel 1 exit /b 1
    )

    call :VerifyPackage "%GIT_INSTALLER%" "Git for Windows 安装包" "%GIT_INSTALLER_SHA256%" "Johannes Schindelin|GitHub|Open Source Developer" "%GIT_SIGNER_THUMBPRINTS%"
    if errorlevel 1 exit /b 1

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
    echo 请先卸载 Node.js，重启 Windows 后重新运行脚本。
    echo.
    echo 系统里已有 Node.js 安装记录或残留，但脚本找不到可用 node.exe。>> "%LOG_FILE%"
    echo 请卸载 Node.js 后重启，再重新运行脚本。>> "%LOG_FILE%"
    exit /b 1
)

echo 未检测到 Node.js，尝试 winget 安装...
echo 未检测到 Node.js，尝试 winget 安装...>> "%LOG_FILE%"

call :InstallByWinget "OpenJS.NodeJS.LTS"
set "WINGET_EXIT_CODE=%ERRORLEVEL%"

echo winget 安装命令返回码: %WINGET_EXIT_CODE%
echo winget 安装命令返回码: %WINGET_EXIT_CODE%>> "%LOG_FILE%"

call :RefreshPath
call :DetectNode
set "NODE_DETECT_CODE=%ERRORLEVEL%"

if "%NODE_DETECT_CODE%"=="0" exit /b 0

if "%NODE_DETECT_CODE%"=="2" (
    echo winget 后检测到 Node.js 安装记录，但 node.exe 不可用。
    echo 请卸载 Node.js，重启 Windows 后重新运行脚本。
    echo winget 后检测到 Node.js 安装记录，但 node.exe 不可用。>> "%LOG_FILE%"
    exit /b 1
)

echo winget 后仍未检测到 Node.js，改用 npmmirror MSI 安装包方式。
echo winget 后仍未检测到 Node.js，改用 npmmirror MSI 安装包方式。>> "%LOG_FILE%"

if exist "%CURRENT_DIR%\NodeJS-Setup.msi" (
    copy /y "%CURRENT_DIR%\NodeJS-Setup.msi" "%NODE_INSTALLER%" >nul
) else if exist "%CURRENT_DIR%\node-v%NODE_VERSION%-x64.msi" (
    copy /y "%CURRENT_DIR%\node-v%NODE_VERSION%-x64.msi" "%NODE_INSTALLER%" >nul
) else (
    call :DownloadFile "%NODE_URL%" "%NODE_INSTALLER%"
    if errorlevel 1 exit /b 1
)

call :VerifyPackage "%NODE_INSTALLER%" "Node.js MSI 安装包" "%NODE_INSTALLER_SHA256%" "OpenJS Foundation|Node.js Foundation|Node.js" "%NODE_SIGNER_THUMBPRINTS%"
if errorlevel 1 exit /b 1

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
    if "%MSI_EXIT_CODE%"=="1603" (
        echo 1603 通常与旧版本残留、降级冲突、权限或 Windows Installer 状态异常有关。
        echo 1603 通常与旧版本残留、降级冲突、权限或 Windows Installer 状态异常有关。>> "%LOG_FILE%"
    )
    echo 请卸载 Node.js，重启 Windows 后重新运行脚本。
    echo 请卸载 Node.js，重启 Windows 后重新运行脚本。>> "%LOG_FILE%"
    exit /b 1
)

call :RefreshPath
call :DetectNode
if not errorlevel 1 exit /b 0

echo MSI 安装后仍未检测到 node.exe。
echo MSI 安装后仍未检测到 node.exe。>> "%LOG_FILE%"
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


:WriteInstallerNpmrc
echo 正在写入脚本私有 npmrc，不修改项目 .npmrc / 用户全局 .npmrc...
echo 正在写入脚本私有 npmrc，不修改项目 .npmrc / 用户全局 .npmrc...>> "%LOG_FILE%"

(
    echo registry=%NPM_REGISTRY%
    echo disturl=https://npmmirror.com/mirrors/node
    echo electron_mirror=https://npmmirror.com/mirrors/electron/
    echo sharp_binary_host=https://npmmirror.com/mirrors/sharp
    echo sharp_libvips_binary_host=https://npmmirror.com/mirrors/sharp-libvips
) > "%INSTALLER_NPMRC%"

if errorlevel 1 (
    echo npm 私有配置文件写入失败: "%INSTALLER_NPMRC%"
    echo 请检查目录权限、磁盘空间或杀毒软件拦截。
    echo npm 私有配置文件写入失败: "%INSTALLER_NPMRC%">> "%LOG_FILE%"
    echo 请检查目录权限、磁盘空间或杀毒软件拦截。>> "%LOG_FILE%"
    exit /b 1
)

echo npm 私有配置文件: "%INSTALLER_NPMRC%"
echo npm 私有配置文件: "%INSTALLER_NPMRC%">> "%LOG_FILE%"
exit /b 0


:ConfirmThirdPartyProxy
if /i "%ALLOW_THIRD_PARTY_PROXY%"=="1" (
    set "THIRD_PARTY_PROXY_CONFIRMED=1"
    exit /b 0
)

if /i "%ALLOW_THIRD_PARTY_PROXY%"=="0" (
    echo 已禁用第三方 GitHub 代理。
    echo 已禁用第三方 GitHub 代理。>> "%LOG_FILE%"
    exit /b 1
)

if "%THIRD_PARTY_PROXY_PROMPTED%"=="1" (
    if "%THIRD_PARTY_PROXY_CONFIRMED%"=="1" exit /b 0
    exit /b 1
)

if /i "%NO_INTERACTIVE%"=="1" (
    echo NO_INTERACTIVE=1 且 ALLOW_THIRD_PARTY_PROXY=ASK，跳过第三方代理以避免阻塞。
    echo NO_INTERACTIVE=1 且 ALLOW_THIRD_PARTY_PROXY=ASK，跳过第三方代理以避免阻塞。>> "%LOG_FILE%"
    echo 如需无人值守启用代理，请预先设置 ALLOW_THIRD_PARTY_PROXY=1。
    echo 如需无人值守禁用代理，请预先设置 ALLOW_THIRD_PARTY_PROXY=0。
    exit /b 1
)

set "THIRD_PARTY_PROXY_PROMPTED=1"

echo.
echo ==================================================
echo 警告：即将使用第三方 GitHub 代理。
echo 这些代理不是 GitHub 官方服务，可能存在缓存、替换、污染或失效风险。
echo 如果 REQUIRE_PROXY_COMMIT_VERIFY=1，代理 clone 必须和官方或预置 release HEAD 一致。
echo 如果 GitHub 不可达，可预设 EXPECTED_ST_RELEASE_HEAD。
echo 无人值守场景请设置 ALLOW_THIRD_PARTY_PROXY=0 或 1。
echo ==================================================
echo.
echo 如果确认继续使用第三方代理，请输入 YES。
echo 其他输入将跳过代理。
echo.

set "PROXY_CONFIRM="
set /p "PROXY_CONFIRM=请输入 YES 继续使用第三方代理: "

if /i "%PROXY_CONFIRM%"=="YES" (
    set "THIRD_PARTY_PROXY_CONFIRMED=1"
    echo 用户已确认启用第三方 GitHub 代理。
    echo 用户已确认启用第三方 GitHub 代理。>> "%LOG_FILE%"
    exit /b 0
)

echo 用户未确认第三方代理，跳过代理 fallback。
echo 用户未确认第三方代理，跳过代理 fallback。>> "%LOG_FILE%"
exit /b 1


:FetchOfficialReleaseHead
set "OFFICIAL_RELEASE_HEAD="
set "OFFICIAL_HEAD_FILE=%INSTALLER_DIR%\official-release-head.txt"
set "OFFICIAL_HEAD_JSON=%INSTALLER_DIR%\official-release-head.json"

if defined EXPECTED_ST_RELEASE_HEAD (
    set "OFFICIAL_RELEASE_HEAD=%EXPECTED_ST_RELEASE_HEAD%"
    echo 使用预置 release HEAD: %OFFICIAL_RELEASE_HEAD%
    echo 使用预置 release HEAD: %OFFICIAL_RELEASE_HEAD%>> "%LOG_FILE%"
    exit /b 0
)

if exist "%OFFICIAL_HEAD_FILE%" del /f /q "%OFFICIAL_HEAD_FILE%" >nul 2>&1
if exist "%OFFICIAL_HEAD_JSON%" del /f /q "%OFFICIAL_HEAD_JSON%" >nul 2>&1

echo 正在获取官方 release HEAD 用于代理完整性校验...
echo 正在获取官方 release HEAD 用于代理完整性校验...>> "%LOG_FILE%"

call :FetchOfficialReleaseHeadByApi
if not errorlevel 1 exit /b 0

echo GitHub API 获取 release HEAD 失败，尝试 git ls-remote 官方仓库...
echo GitHub API 获取 release HEAD 失败，尝试 git ls-remote 官方仓库...>> "%LOG_FILE%"

git ^
  -c http.version=HTTP/1.1 ^
  -c http.lowSpeedLimit=%GIT_LOW_SPEED_LIMIT% ^
  -c http.lowSpeedTime=30 ^
  ls-remote --heads "%ST_GIT_URL%" release > "%OFFICIAL_HEAD_FILE%" 2>> "%LOG_FILE%"

if errorlevel 1 (
    echo 无法获取官方 release HEAD。
    echo 无法获取官方 release HEAD。>> "%LOG_FILE%"
    echo 可预先设置 EXPECTED_ST_RELEASE_HEAD 后再运行，以便在 GitHub 不可达时校验代理 clone。
    echo 可预先设置 EXPECTED_ST_RELEASE_HEAD 后再运行，以便在 GitHub 不可达时校验代理 clone。>> "%LOG_FILE%"
    exit /b 1
)

for /f "usebackq tokens=1" %%A in ("%OFFICIAL_HEAD_FILE%") do (
    if not defined OFFICIAL_RELEASE_HEAD set "OFFICIAL_RELEASE_HEAD=%%A"
)

if not defined OFFICIAL_RELEASE_HEAD (
    echo 官方 release HEAD 为空。
    echo 官方 release HEAD 为空。>> "%LOG_FILE%"
    echo 可预先设置 EXPECTED_ST_RELEASE_HEAD 后再运行。
    echo 可预先设置 EXPECTED_ST_RELEASE_HEAD 后再运行。>> "%LOG_FILE%"
    exit /b 1
)

echo 官方 release HEAD: %OFFICIAL_RELEASE_HEAD%
echo 官方 release HEAD: %OFFICIAL_RELEASE_HEAD%>> "%LOG_FILE%"
exit /b 0


:FetchOfficialReleaseHeadByApi
if not defined POWERSHELL_EXE exit /b 1

"%POWERSHELL_EXE%" -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$ProgressPreference='SilentlyContinue';" ^
  "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;" ^
  "$url=$env:ST_RELEASE_HEAD_API;" ^
  "$out=$env:OFFICIAL_HEAD_JSON;" ^
  "$json=Invoke-RestMethod -Uri $url -Headers @{ 'User-Agent'='silly-tavern-windows-installer' } -TimeoutSec 20;" ^
  "$json | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $out -Encoding UTF8;" ^
  "$sha=$json.object.sha;" ^
  "if(!$sha -or $sha.Length -ne 40){throw 'GitHub API release HEAD 无效'};" ^
  "Set-Content -LiteralPath $env:OFFICIAL_HEAD_FILE -Value $sha -Encoding ASCII;" >> "%LOG_FILE%" 2>&1

if errorlevel 1 exit /b 1

for /f "usebackq tokens=1" %%A in ("%OFFICIAL_HEAD_FILE%") do (
    if not defined OFFICIAL_RELEASE_HEAD set "OFFICIAL_RELEASE_HEAD=%%A"
)

if not defined OFFICIAL_RELEASE_HEAD exit /b 1

echo 官方 release HEAD(API): %OFFICIAL_RELEASE_HEAD%
echo 官方 release HEAD(API): %OFFICIAL_RELEASE_HEAD%>> "%LOG_FILE%"
exit /b 0


:VerifyProxyCloneHead
set "CLONED_HEAD="

for /f "tokens=*" %%H in ('git -C "%PROJECT_DIR%" rev-parse HEAD 2^>nul') do set "CLONED_HEAD=%%H"

echo 代理 clone HEAD: %CLONED_HEAD%
echo 代理 clone HEAD: %CLONED_HEAD%>> "%LOG_FILE%"

if not defined CLONED_HEAD (
    echo 无法读取代理 clone HEAD。
    echo 无法读取代理 clone HEAD。>> "%LOG_FILE%"
    exit /b 1
)

if not defined OFFICIAL_RELEASE_HEAD (
    if /i "%REQUIRE_PROXY_COMMIT_VERIFY%"=="1" (
        echo 缺少官方或预置 release HEAD，拒绝未验证的代理 clone。
        echo 缺少官方或预置 release HEAD，拒绝未验证的代理 clone。>> "%LOG_FILE%"
        exit /b 1
    )
    exit /b 0
)

if /i not "%CLONED_HEAD%"=="%OFFICIAL_RELEASE_HEAD%" (
    echo 代理 clone HEAD 与官方或预置 release HEAD 不一致，拒绝使用。
    echo 代理 clone HEAD 与官方或预置 release HEAD 不一致，拒绝使用。>> "%LOG_FILE%"
    exit /b 1
)

exit /b 0


:TryClone
set "CLONE_URL=%~1"
set "CLONE_NAME=%~2"
set "CLONE_NEEDS_VERIFY=%~3"

if exist "%PROJECT_DIR%" rmdir /s /q "%PROJECT_DIR%" >> "%LOG_FILE%" 2>&1

echo 尝试 clone：%CLONE_NAME%
echo clone 地址: %CLONE_URL%
echo 尝试 clone：%CLONE_NAME%>> "%LOG_FILE%"
echo clone 地址: %CLONE_URL%>> "%LOG_FILE%"

git ^
  -c http.version=HTTP/1.1 ^
  -c http.lowSpeedLimit=%GIT_LOW_SPEED_LIMIT% ^
  -c http.lowSpeedTime=%GIT_LOW_SPEED_TIME% ^
  clone --depth 1 --branch release "%CLONE_URL%" "%PROJECT_DIR%" >> "%LOG_FILE%" 2>&1

if errorlevel 1 (
    if exist "%PROJECT_DIR%" rmdir /s /q "%PROJECT_DIR%" >> "%LOG_FILE%" 2>&1
    exit /b 1
)

if not exist "%PROJECT_DIR%\start.bat" (
    echo clone 结果缺少 start.bat。
    echo clone 结果缺少 start.bat。>> "%LOG_FILE%"
    if exist "%PROJECT_DIR%" rmdir /s /q "%PROJECT_DIR%" >> "%LOG_FILE%" 2>&1
    exit /b 1
)

if /i "%CLONE_NEEDS_VERIFY%"=="1" (
    call :VerifyProxyCloneHead
    if errorlevel 1 (
        if exist "%PROJECT_DIR%" rmdir /s /q "%PROJECT_DIR%" >> "%LOG_FILE%" 2>&1
        exit /b 1
    )
)

git -C "%PROJECT_DIR%" remote set-url origin "%ST_GIT_URL%" >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo 警告：无法将 origin 重置为官方 GitHub 地址。
    echo 警告：无法将 origin 重置为官方 GitHub 地址。>> "%LOG_FILE%"
)

set "PROJECT_SOURCE_USED=%CLONE_NAME%"
exit /b 0


:CloneSillyTavernWithFallback
call :TryClone "%ST_GIT_URL%" "GitHub 官方直连 clone" "0"
if not errorlevel 1 exit /b 0

call :ConfirmThirdPartyProxy
if errorlevel 1 exit /b 1

call :FetchOfficialReleaseHead
if errorlevel 1 (
    if /i "%REQUIRE_PROXY_COMMIT_VERIFY%"=="1" (
        echo REQUIRE_PROXY_COMMIT_VERIFY=1，无法校验代理 clone，跳过代理。
        echo REQUIRE_PROXY_COMMIT_VERIFY=1，无法校验代理 clone，跳过代理。>> "%LOG_FILE%"
        exit /b 1
    )
)

call :TryClone "%ST_GIT_URL_PROXY_1%" "第三方代理 clone 1 gh-proxy.com" "1"
if not errorlevel 1 exit /b 0

call :TryClone "%ST_GIT_URL_PROXY_2%" "第三方代理 clone 2 hubp.llkk.cc" "1"
if not errorlevel 1 exit /b 0

exit /b 1


:ValidateExtractedProject
if not exist "%PROJECT_DIR%\start.bat" exit /b 1
if not exist "%PROJECT_DIR%\package.json" exit /b 1
exit /b 0


:DownloadSillyTavernZipWithFallback
if exist "%ST_ZIP%" del /f /q "%ST_ZIP%" >> "%LOG_FILE%" 2>&1

echo 尝试直连 GitHub ZIP...
echo 尝试直连 GitHub ZIP...>> "%LOG_FILE%"
call :DownloadFile "%ST_ZIP_URL%" "%ST_ZIP%"
if not errorlevel 1 (
    set "PROJECT_SOURCE_USED=GitHub 官方直连 ZIP"
    exit /b 0
)

call :ConfirmThirdPartyProxy
if errorlevel 1 exit /b 1

if /i "%REQUIRE_PROXY_COMMIT_VERIFY%"=="1" (
    echo REQUIRE_PROXY_COMMIT_VERIFY=1，ZIP 代理无法进行 commit 校验，拒绝代理 ZIP。
    echo 如需允许代理 ZIP，请在运行前设置：set REQUIRE_PROXY_COMMIT_VERIFY=0
    echo REQUIRE_PROXY_COMMIT_VERIFY=1，ZIP 代理无法进行 commit 校验，拒绝代理 ZIP。>> "%LOG_FILE%"
    echo 如需允许代理 ZIP，请在运行前设置：set REQUIRE_PROXY_COMMIT_VERIFY=0>> "%LOG_FILE%"
    exit /b 1
)

if exist "%ST_ZIP%" del /f /q "%ST_ZIP%" >> "%LOG_FILE%" 2>&1
echo 尝试第三方代理 ZIP 1...
echo 尝试第三方代理 ZIP 1...>> "%LOG_FILE%"
call :DownloadFile "%ST_ZIP_URL_PROXY_1%" "%ST_ZIP%"
if not errorlevel 1 (
    set "PROJECT_SOURCE_USED=第三方代理 ZIP 1 gh-proxy.com"
    exit /b 0
)

if exist "%ST_ZIP%" del /f /q "%ST_ZIP%" >> "%LOG_FILE%" 2>&1
echo 尝试第三方代理 ZIP 2...
echo 尝试第三方代理 ZIP 2...>> "%LOG_FILE%"
call :DownloadFile "%ST_ZIP_URL_PROXY_2%" "%ST_ZIP%"
if not errorlevel 1 (
    set "PROJECT_SOURCE_USED=第三方代理 ZIP 2 gh.llkk.cc"
    exit /b 0
)

if exist "%ST_ZIP%" del /f /q "%ST_ZIP%" >> "%LOG_FILE%" 2>&1
exit /b 1


:TryFetchRelease
set "FETCH_URL=%~1"
set "FETCH_NAME=%~2"
set "FETCH_NEEDS_VERIFY=%~3"
set "FETCHED_HEAD="

echo 尝试 fetch：%FETCH_NAME%
echo fetch 地址: %FETCH_URL%
echo 尝试 fetch：%FETCH_NAME%>> "%LOG_FILE%"
echo fetch 地址: %FETCH_URL%>> "%LOG_FILE%"

git ^
  -c http.version=HTTP/1.1 ^
  -c http.lowSpeedLimit=%GIT_LOW_SPEED_LIMIT% ^
  -c http.lowSpeedTime=%GIT_LOW_SPEED_TIME% ^
  -C "%PROJECT_DIR%" fetch "%FETCH_URL%" release --depth 1 >> "%LOG_FILE%" 2>&1

if errorlevel 1 exit /b 1

for /f "tokens=*" %%H in ('git -C "%PROJECT_DIR%" rev-parse FETCH_HEAD 2^>nul') do set "FETCHED_HEAD=%%H"

if /i "%FETCH_NEEDS_VERIFY%"=="1" (
    if not defined FETCHED_HEAD (
        echo 无法读取代理 fetch HEAD。
        echo 无法读取代理 fetch HEAD。>> "%LOG_FILE%"
        exit /b 1
    )

    echo 代理 fetch HEAD: %FETCHED_HEAD%
    echo 代理 fetch HEAD: %FETCHED_HEAD%>> "%LOG_FILE%"

    if not defined OFFICIAL_RELEASE_HEAD (
        if /i "%REQUIRE_PROXY_COMMIT_VERIFY%"=="1" (
            echo 缺少官方或预置 release HEAD，拒绝未验证的代理 fetch。
            echo 缺少官方或预置 release HEAD，拒绝未验证的代理 fetch。>> "%LOG_FILE%"
            exit /b 1
        )
    ) else if /i not "%FETCHED_HEAD%"=="%OFFICIAL_RELEASE_HEAD%" (
        echo 代理 fetch HEAD 与官方或预置 release HEAD 不一致，拒绝使用。
        echo 代理 fetch HEAD 与官方或预置 release HEAD 不一致，拒绝使用。>> "%LOG_FILE%"
        exit /b 1
    )
)

set "FETCH_SOURCE_USED=%FETCH_NAME%"
exit /b 0


:FetchReleaseWithFallback
set "FETCH_SOURCE_USED="

call :TryFetchRelease "%ST_GIT_URL%" "GitHub 官方直连 fetch" "0"
if not errorlevel 1 exit /b 0

call :ConfirmThirdPartyProxy
if errorlevel 1 exit /b 1

call :FetchOfficialReleaseHead
if errorlevel 1 (
    if /i "%REQUIRE_PROXY_COMMIT_VERIFY%"=="1" (
        echo REQUIRE_PROXY_COMMIT_VERIFY=1，无法校验代理 fetch，跳过代理。
        echo REQUIRE_PROXY_COMMIT_VERIFY=1，无法校验代理 fetch，跳过代理。>> "%LOG_FILE%"
        exit /b 1
    )
)

call :TryFetchRelease "%ST_GIT_URL_PROXY_1%" "第三方代理 fetch 1 gh-proxy.com" "1"
if not errorlevel 1 exit /b 0

call :TryFetchRelease "%ST_GIT_URL_PROXY_2%" "第三方代理 fetch 2 hubp.llkk.cc" "1"
if not errorlevel 1 exit /b 0

exit /b 1


:UpdateExistingGitProject
set "STATUS_FILE=%INSTALLER_DIR%\git-status.txt"
set "GIT_DIRTY=0"

if exist "%STATUS_FILE%" del /f /q "%STATUS_FILE%" >nul 2>&1

git -C "%PROJECT_DIR%" status --porcelain > "%STATUS_FILE%" 2>> "%LOG_FILE%"
if errorlevel 1 exit /b 1

for %%F in ("%STATUS_FILE%") do (
    if %%~zF GTR 0 set "GIT_DIRTY=1"
)

if "%GIT_DIRTY%"=="1" (
    echo Git 工作区存在本地修改，跳过自动切换/更新 release 分支。
    echo Git 工作区存在本地修改，跳过自动切换/更新 release 分支。>> "%LOG_FILE%"
    set "PROJECT_SOURCE_USED=已有 Git 项目，本地有修改，跳过更新"
    exit /b 0
)

echo 正在更新 release 分支，官方 GitHub 失败后可按配置使用已校验代理。
echo 正在更新 release 分支，官方 GitHub 失败后可按配置使用已校验代理。>> "%LOG_FILE%"

call :FetchReleaseWithFallback
if errorlevel 1 (
    echo release fetch 失败，跳过更新，继续使用现有项目。
    echo release fetch 失败，跳过更新，继续使用现有项目。>> "%LOG_FILE%"
    set "PROJECT_SOURCE_USED=已有 Git 项目，fetch 失败，跳过更新"
    exit /b 0
)

git -C "%PROJECT_DIR%" checkout release >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo 无法切换到 release 分支，跳过更新。
    echo 无法切换到 release 分支，跳过更新。>> "%LOG_FILE%"
    set "PROJECT_SOURCE_USED=已有 Git 项目，无法切换 release"
    exit /b 0
)

git -C "%PROJECT_DIR%" merge --ff-only FETCH_HEAD >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    call :ReportGitUpdateSkipped "release 分支无法快进合并（merge --ff-only FETCH_HEAD 失败）"
    set "PROJECT_SOURCE_USED=已有 Git 项目，未更新（无法快进，仍在旧版本）"
    exit /b 0
)

git -C "%PROJECT_DIR%" remote set-url origin "%ST_GIT_URL%" >> "%LOG_FILE%" 2>&1
if errorlevel 1 (
    echo 警告：无法将 origin 重置为官方 GitHub 地址。
    echo 警告：无法将 origin 重置为官方 GitHub 地址。>> "%LOG_FILE%"
)

set "PROJECT_SOURCE_USED=已有 Git 项目，已更新 release（%FETCH_SOURCE_USED%）"
exit /b 0


:ReportGitUpdateSkipped
set "UPDATE_SKIP_REASON=%~1"
set "UPDATE_SKIP_STATUS_FILE_CREATED=0"
if not defined STATUS_FILE (
    set "STATUS_FILE=%TEMP%\sillytavern_git_status_%RANDOM%.tmp"
    set "UPDATE_SKIP_STATUS_FILE_CREATED=1"
)
set "CURRENT_HEAD="
set "TARGET_HEAD="

for /f "tokens=*" %%H in ('git -C "%PROJECT_DIR%" rev-parse HEAD 2^>nul') do set "CURRENT_HEAD=%%H"
for /f "tokens=*" %%H in ('git -C "%PROJECT_DIR%" rev-parse FETCH_HEAD 2^>nul') do set "TARGET_HEAD=%%H"

if not defined CURRENT_HEAD set "CURRENT_HEAD=无法读取"
if not defined TARGET_HEAD set "TARGET_HEAD=无法读取"

echo.
echo 警告：SillyTavern 未更新，仍在旧版本。
echo 原因：%UPDATE_SKIP_REASON%
echo Fetch 来源: %FETCH_SOURCE_USED%
echo 当前 commit: %CURRENT_HEAD%
echo 目标 FETCH_HEAD: %TARGET_HEAD%
echo Git 状态摘要:
echo.
echo 警告：SillyTavern 未更新，仍在旧版本。>> "%LOG_FILE%"
echo 原因：%UPDATE_SKIP_REASON%>> "%LOG_FILE%"
echo Fetch 来源: %FETCH_SOURCE_USED%>> "%LOG_FILE%"
echo 当前 commit: %CURRENT_HEAD%>> "%LOG_FILE%"
echo 目标 FETCH_HEAD: %TARGET_HEAD%>> "%LOG_FILE%"
echo Git 状态摘要:>> "%LOG_FILE%"

git -C "%PROJECT_DIR%" status --short --branch > "%STATUS_FILE%" 2>> "%LOG_FILE%"
if errorlevel 1 (
    echo   无法读取 git status 摘要。
    echo   无法读取 git status 摘要。>> "%LOG_FILE%"
) else (
    type "%STATUS_FILE%"
    type "%STATUS_FILE%" >> "%LOG_FILE%"
)

echo.
echo 处理建议:
echo 1. 如果你有本地修改或本地提交，请先备份，再手动处理分支差异。
echo 2. 如果你只想使用官方 release，请重新下载到空目录，或确认备份后手动执行：
echo    git fetch origin release
echo    git checkout -B release FETCH_HEAD
echo    git remote set-url origin "%ST_GIT_URL%"
echo.
echo 处理建议:>> "%LOG_FILE%"
echo 1. 如果你有本地修改或本地提交，请先备份，再手动处理分支差异。>> "%LOG_FILE%"
echo 2. 如果你只想使用官方 release，请重新下载到空目录，或确认备份后手动执行：>> "%LOG_FILE%"
echo    git fetch origin release>> "%LOG_FILE%"
echo    git checkout -B release FETCH_HEAD>> "%LOG_FILE%"
echo    git remote set-url origin "%ST_GIT_URL%">> "%LOG_FILE%"
if "%UPDATE_SKIP_STATUS_FILE_CREATED%"=="1" if exist "%STATUS_FILE%" del /f /q "%STATUS_FILE%" >nul 2>&1
exit /b 0


:SetupProject
cd /d "%CURRENT_DIR%"

if exist "%PROJECT_DIR%" (
    if not exist "%PROJECT_DIR%\start.bat" (
        echo 检测到不完整的 SillyTavern 目录，正在备份旧目录...
        echo 检测到不完整的 SillyTavern 目录，正在备份旧目录...>> "%LOG_FILE%"
        ren "%PROJECT_DIR%" "SillyTavern_broken_%RANDOM%%RANDOM%" >> "%LOG_FILE%" 2>&1
        if errorlevel 1 (
            echo 无法备份不完整目录，请手动删除: "%PROJECT_DIR%"
            echo 无法备份不完整目录，请手动删除: "%PROJECT_DIR%">> "%LOG_FILE%"
            exit /b 1
        )
    )
)

if exist "%PROJECT_DIR%\start.bat" (
    if exist "%PROJECT_DIR%\.git" (
        call :UpdateExistingGitProject
        exit /b 0
    ) else (
        echo 检测到已有 ZIP/非 Git 版项目，start.bat 存在，跳过下载。
        echo 检测到已有 ZIP/非 Git 版项目，start.bat 存在，跳过下载。>> "%LOG_FILE%"
        set "PROJECT_SOURCE_USED=已有 ZIP/非 Git 项目"
        exit /b 0
    )
)

echo 开始克隆 SillyTavern...
echo 开始克隆 SillyTavern...>> "%LOG_FILE%"

call :CloneSillyTavernWithFallback
if not errorlevel 1 (
    if exist "%PROJECT_DIR%\start.bat" exit /b 0
)

echo Git 克隆失败，尝试 ZIP 下载...
echo Git 克隆失败，尝试 ZIP 下载...>> "%LOG_FILE%"

if exist "%PROJECT_DIR%" rmdir /s /q "%PROJECT_DIR%" >> "%LOG_FILE%" 2>&1

call :DownloadSillyTavernZipWithFallback
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
  "if(Test-Path -LiteralPath $out){Remove-Item -LiteralPath $out -Recurse -Force};" ^
  "Expand-Archive -LiteralPath $zip -DestinationPath $out -Force;" ^
  "$src=Get-ChildItem -LiteralPath $out -Directory | Select-Object -First 1;" ^
  "if(!$src){throw 'ZIP 解压后未找到项目目录'};" ^
  "if(Test-Path -LiteralPath $dst){Remove-Item -LiteralPath $dst -Recurse -Force};" ^
  "Move-Item -LiteralPath $src.FullName -Destination $dst -Force;" >> "%LOG_FILE%" 2>&1

if errorlevel 1 exit /b 1

call :ValidateExtractedProject
if errorlevel 1 (
    echo 解压后的项目缺少关键文件。
    echo 解压后的项目缺少关键文件。>> "%LOG_FILE%"
    exit /b 1
)

exit /b 0


:StartProject
if not exist "%PROJECT_DIR%\start.bat" (
    echo 未找到 "%PROJECT_DIR%\start.bat"。>> "%LOG_FILE%"
    exit /b 1
)

echo 正在启动 SillyTavern...
echo 正在启动 SillyTavern...>> "%LOG_FILE%"

start "SillyTavern" cmd /k "cd /d ""%PROJECT_DIR%"" && set ""NPM_CONFIG_USERCONFIG=%INSTALLER_NPMRC%"" && call start.bat & echo. & echo SillyTavern 已退出或启动失败，请查看上方错误。 & echo. & pause"

echo 已启动 SillyTavern。
echo 已启动 SillyTavern。>> "%LOG_FILE%"
exit /b 0
