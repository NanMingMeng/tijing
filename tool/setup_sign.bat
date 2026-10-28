@echo off
REM ============================================================
REM 题镜 · 一键生成正式签名（Windows）
REM 跑一次即可；生成的 tijing-release.jks 和 key.properties
REM 必须自己备份好，丢了就再也无法发布更新。
REM ============================================================
setlocal enabledelayedexpansion
cd /d "%~dp0.."

set KS=android\app\tijing-release.jks
set KP=android\key.properties

if exist "%KS%" (
  echo [跳过] 已存在 %KS%
  goto writeprops
)

echo 正在生成 keystore...
echo 请依次输入：一个密码（记牢）、姓名、组织、城市、省份、国家代码
echo.
keytool -genkeypair -v ^
  -keystore "%KS%" ^
  -alias tijing ^
  -keyalg RSA -keysize 2048 -validity 10000 ^
  -storetype JKS

if errorlevel 1 (
  echo.
  echo [失败] keytool 未找到或执行出错。
  echo 请确认已安装 JDK 17，并把它加入 PATH。
  pause
  exit /b 1
)

:writeprops
echo.
set /p STOREPASS=请输入刚才设置的 keystore 密码:
> "%KP%" echo storePassword=!STOREPASS!
>> "%KP%" echo keyPassword=!STOREPASS!
>> "%KP%" echo keyAlias=tijing
>> "%KP%" echo storeFile=tijing-release.jks

echo.
echo [完成] 已写入 %KP%
echo.
echo 下一步：flutter build apk --release
echo.
echo ============ 务必备份这两个文件 ============
echo   %KS%
echo   android\key.properties（里面是密码）
echo 建议把 jks 复制到网盘/U盘，密码单独记在密码管理器。
echo ============================================
pause
