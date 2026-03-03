# ==================================================
# 隐藏窗口启动
# ==================================================
if (-not $env:PS_HIDDEN) {
    $env:PS_HIDDEN = 1
    Start-Process powershell `
        -WindowStyle Hidden `
        -ArgumentList "-ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`"" 
    exit
}
# ==================================================
# 设备固定配置
# ==================================================
$DeviceName = "K40"
$UsbSerial  = "20704a"
$WifiIP     = "192.168.1.240"
$Port       = 5555
$WifiDevice = "${WifiIP}:${Port}"

# ==================================================
# scrcpy 配置
# ==================================================
$ScrcpyMaxSize = 1440
$ScrcpyBitRate = "3M"
$ScrcpyMaxFps  = 15

# ==================================================
# adb 设备解析函数
# ==================================================
function Get-AdbDevices {
    adb devices |
        Select-Object -Skip 1 |
        Where-Object { $_.Trim() -ne "" } |
        ForEach-Object {
            $p = $_ -split "\s+"
            [PSCustomObject]@{
                Id     = $p[0]
                Status = $p[1]
            }
        }
}

# ==================================================
# 判断 USB 
# ==================================================
$usbOnline = Get-AdbDevices |
    Where-Object { $_.Id -eq $UsbSerial -and $_.Status -eq "device" }

if ($usbOnline) {
    Write-Host "[$DeviceName] 使用 USB 连接"
    $TargetDevice = $UsbSerial
} else {
    Write-Host "[$DeviceName] USB 不在线，使用 WiFi"
    adb connect $WifiDevice | Out-Null
    $TargetDevice = $WifiDevice
}

# ==================================================
# 启动 scrcpy
# ==================================================
Write-Host "[$DeviceName] 启动 scrcpy → $TargetDevice"

$scrcpyArgs = @(
    "-s", $TargetDevice,
    "-m", $ScrcpyMaxSize,
    "-b", $ScrcpyBitRate,
    "--max-fps", $ScrcpyMaxFps,
    "--window-title", $DeviceName
)

scrcpy @scrcpyArgs -Sws
