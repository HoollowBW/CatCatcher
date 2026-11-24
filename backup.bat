@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo ============================================
echo   CatCatcher 自动备份
echo ============================================
echo.

git --version >nul 2>&1
if errorlevel 1 (
    echo [错误] 找不到 git 命令。
    echo        请先安装 Git 并勾选 "Git from the command line and also from 3rd-party software"，
    echo        装完后重开本窗口再试。
    echo.
    pause
    exit /b 1
)

echo 正在暂存改动...
git add .
if errorlevel 1 (
    echo [错误] git add 失败，请查看上方输出。
    echo.
    pause
    exit /b 1
)

git diff --cached --quiet
if errorlevel 1 (
    echo 正在提交...
    git commit -m "自动备份 - %date% %time%"
    if errorlevel 1 (
        echo.
        echo [失败] 提交未成功，请查看上方 git 输出。
        echo.
        pause
        exit /b 1
    )
    echo.
    echo 备份成功
) else (
    echo.
    echo 没有新改动
)

rem ===== 推送到 GitHub（网络不稳，最多重试 3 次）=====
git remote get-url origin >nul 2>&1
if errorlevel 1 (
    echo.
    echo [跳过] 未配置 GitHub 远程仓库，仅本地备份。
    goto :endpush
)

set PUSHTRY=0
:pushtry
set /a PUSHTRY+=1
echo.
echo 正在推送到 GitHub（第 %PUSHTRY%/3 次）...
git push --progress origin main
if not errorlevel 1 goto :pushok
if %PUSHTRY% geq 3 goto :pushfail
ping -n 6 127.0.0.1 >nul
goto :pushtry

:pushok
echo.
echo 已同步到 GitHub
goto :endpush

:pushfail
echo.
echo [提示] 推送到 GitHub 失败，本地备份已完成，不影响。网络恢复后手动执行 git push 即可。
:endpush

echo.
pause
