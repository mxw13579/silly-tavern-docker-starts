@echo off
chcp 65001 >nul
title 酒馆安装脚本
setlocal enabledelayedexpansion

:: 切换到脚本所在目录
cd /d "%~dp0"
:: 保存当前目录路径
set "CURRENT_DIR=%cd%"
echo 当前工作目录: %CURRENT_DIR%

echo git 与 nodejs 一键安装脚本开始
echo.

:: 检查管理员权限
net session >nul 2>&1
if %errorLevel% == 0 (
    echo 已获取管理员权限
) else (
    echo 请以管理员身份运行此脚本！
    pause
    exit /b 1
)



:: 获取IP地址和地理位置信息
echo.
echo 正在获取网络信息...
for /f "tokens=*" %%i in ('curl -s ifconfig.me') do set IP_ADDRESS=%%i
echo 当前IP地址: %IP_ADDRESS%
echo -----------------------------------

echo.
echo 正在获取地理位置信息...
curl -s ipinfo.io/%IP_ADDRESS%
echo.
echo -----------------------------------


:: 设置初始状态
set "GIT_STATUS=未检测"
set "NODE_STATUS=未检测"
set "NPM_STATUS=未检测"

:: 检查Git
echo.
echo [1/3] 检测Git环境...
git --version >nul 2>&1
if !errorLevel! == 0 (
    for /f "tokens=*" %%i in ('git --version') do set "GIT_STATUS=%%i"
    echo √ 检测到已安装Git，版本：!GIT_STATUS!
) else (
    echo × Git未安装，测试连接github.com...
    ping github.com -n 1 -w 3000 >nul
    if !errorLevel! == 0 (
        echo √ 连接github.com成功，准备下载安装...
        powershell -Command "& {Invoke-WebRequest -Uri 'https://github.com/git-for-windows/git/releases/download/v2.43.0.windows.1/Git-2.43.0-64-bit.exe' -OutFile 'Git-Setup.exe'}"
        if exist Git-Setup.exe (
            echo 开始安装Git...
            start /wait Git-Setup.exe /VERYSILENT /NORESTART
            del Git-Setup.exe
            echo Git安装完成！
            for /f "tokens=*" %%i in ('git --version') do set "GIT_STATUS=%%i"
        ) else (
            set "GIT_STATUS=[错误] Git下载失败"
            echo × !GIT_STATUS!
            pause
            exit /b 1
        )
    ) else (
        echo × 无法连接到github.com，安装失败，请检查您的网络环境
        pause
        exit /b 1
    )
)

:: 检查Node.js
echo.
echo [2/3] 检测Node.js环境...
node --version >nul 2>&1
if !errorLevel! == 0 (
    for /f "tokens=*" %%i in ('node --version') do set "NODE_STATUS=%%i"
    echo √ 检测到已安装Node.js，版本：!NODE_STATUS!
) else (
    echo × Node.js未安装，测试连接nodejs.org...
    ping nodejs.org -n 1 -w 3000 >nul
    if !errorLevel! == 0 (
        echo √ 连接nodejs.org成功，准备下载安装...
        powershell -Command "& {Invoke-WebRequest -Uri 'https://nodejs.org/dist/v20.11.1/node-v20.11.1-x64.msi' -OutFile 'NodeJS-Setup.msi'}"
        if exist NodeJS-Setup.msi (
            echo 开始安装Node.js...
            start /wait msiexec /i NodeJS-Setup.msi /qn
            del NodeJS-Setup.msi
            echo Node.js安装完成！
            for /f "tokens=*" %%i in ('node --version') do set "NODE_STATUS=%%i"
        ) else (
            set "NODE_STATUS=[错误] Node.js下载失败"
            echo × !NODE_STATUS!
            pause
            exit /b 1
        )
    ) else (
        echo × 无法连接到nodejs.org，安装失败，请检查您的网络环境
        pause
        exit /b 1
    )
)

:: 检查npm
echo.
echo [3/3] 检测npm环境...
call npm --version >nul 2>&1
if !errorLevel! == 0 (
    for /f "tokens=*" %%i in ('npm --version') do set "NPM_STATUS=%%i"
    echo √ npm版本：!NPM_STATUS!
) else (
    echo × npm测试连接npmjs.com...
    ping npmjs.com -n 1 -w 3000 >nul
    if !errorLevel! == 0 (
        set "NPM_STATUS=需要重新安装Node.js"
        echo × !NPM_STATUS!
    ) else (
        echo × 无法连接到npmjs.com，安装失败，请检查您的网络环境
        pause
        exit /b 1
    )
)

:: 显示最终验证结果
echo.
echo -----------------------------------
echo          环境检查结果
echo -----------------------------------
echo Git 状态：!GIT_STATUS!
echo.
echo Node.js 状态：!NODE_STATUS!
echo.
echo npm 状态：!NPM_STATUS!
echo -----------------------------------
echo.
echo 检查完成！



echo.
echo -----------------------------------
echo          下载并启动项目
echo -----------------------------------
echo 准备下载项目...

:: 确保在当前目录
cd /d "%CURRENT_DIR%"
echo 正在下载到目录: %CURRENT_DIR%


:: 检查项目是否已存在
if exist "%CURRENT_DIR%\SillyTavern" (
    echo 检测到已存在项目文件夹
    choice /c YN /m "是否更新项目？(Y=是, N=否)"
    if !errorLevel! == 1 (
        echo 正在更新项目...
        cd /d "%CURRENT_DIR%\SillyTavern"
        git pull
        if !errorLevel! == 0 (
            echo √ 项目更新成功
        ) else (
            echo × 项目更新失败
        )
    ) else (
        echo 跳过更新
    )

    :: 启动项目
    cd /d "%CURRENT_DIR%\SillyTavern"
    if exist "start.bat" (
        start "" "start.bat"
        echo √ 已启动项目
    ) else (
        echo × 未找到start.bat文件
    )
) else (
    echo 项目不存在，准备下载...

    :: 克隆项目
    echo 正在下载项目...
    git clone "https://github.com/SillyTavern/SillyTavern.git" "%CURRENT_DIR%\SillyTavern"
    if !errorLevel! == 0 (
        echo √ 项目下载成功
        cd /d "%CURRENT_DIR%\SillyTavern"

        echo 正在启动项目...
        if exist "start.bat" (
            start "" "start.bat"
            echo √ 已启动项目
        ) else (
            echo × 未找到start.bat文件，正在检查文件列表...
            dir /b
        )
    ) else (
        echo × 项目下载失败，请检查网络连接或Git配置
    )
)

cd /d "%CURRENT_DIR%"
echo.
echo 操作完成！按任意键退出...
pause >nul
endlocal