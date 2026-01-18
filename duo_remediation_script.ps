<# 
Duo Windows Logon & RDP - Debug Logging Remediation
Enables debug logging by setting:
- HKLM:\SOFTWARE\Duo Security\DuoCredProv\Debug (DWORD) = 1
- HKLM:\SOFTWARE\Policies\Duo Security\DuoCredProv\debug (DWORD) = 1 (helps when GPO-managed; may be reverted on refresh)

Exit 0 = success / not applicable
Exit 1 = failed
#>

$ErrorActionPreference = "Stop"

$duoRegBase    = "HKLM:\SOFTWARE\Duo Security\DuoCredProv"
$duoPolicyBase = "HKLM:\SOFTWARE\Policies\Duo Security\DuoCredProv"

$logDir  = Join-Path $env:ProgramData "DuoDebugLogging"
$logFile = Join-Path $logDir "Enable-DuoDebugLogging.log"

function Write-Log {
    param([string]$Message)
    if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
    $stamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
    Add-Content -Path $logFile -Value "$stamp $Message"
}

function Test-DuoInstalled {
    if (Test-Path $duoRegBase) { return $true }

    $possiblePaths = @(
        Join-Path $env:ProgramFiles "Duo Security\DuoCredProv",
        Join-Path ${env:ProgramFiles(x86)} "Duo Security\DuoCredProv"
    ) | Where-Object { $_ -and $_.Trim() -ne "" }

    foreach ($p in $possiblePaths) {
        if (Test-Path $p) { return $true }
    }

    return $false
}

try {
    if (-not (Test-DuoInstalled)) {
        Write-Log "Not applicable: Duo Windows Logon & RDP not detected; no changes made."
        Write-Output "Not applicable: Duo Windows Logon & RDP not detected."
        exit 0
    }

    # Ensure base key exists
    if (-not (Test-Path $duoRegBase)) {
        New-Item -Path $duoRegBase -Force | Out-Null
        Write-Log "Created registry key: $duoRegBase"
    }

    # Set Debug DWORD
    New-ItemProperty -Path $duoRegBase -Name "Debug" -PropertyType DWord -Value 1 -Force | Out-Null
    Write-Log "Set $duoRegBase\Debug = 1 (DWORD)"

    # Ensure policy key exists and set policy debug (lowercase name per Duo doc)
    if (-not (Test-Path $duoPolicyBase)) {
        New-Item -Path $duoPolicyBase -Force | Out-Null
        Write-Log "Created registry key: $duoPolicyBase"
    }

    New-ItemProperty -Path $duoPolicyBase -Name "debug" -PropertyType DWord -Value 1 -Force | Out-Null
    Write-Log "Set $duoPolicyBase\debug = 1 (DWORD)"

    # Verify
    $debugValue = (Get-ItemProperty -Path $duoRegBase -Name "Debug" -ErrorAction Stop)."Debug"
    $policyDebugValue = (Get-ItemProperty -Path $duoPolicyBase -Name "debug" -ErrorAction Stop)."debug"

    if ($debugValue -eq 1 -and $policyDebugValue -eq 1) {
        Write-Log "Verification success. Debug=$debugValue, PolicyDebug=$policyDebugValue"
        Write-Output "Remediated: Duo debug logging enabled."
        exit 0
    }

    Write-Log "Verification failed. Debug=$debugValue, PolicyDebug=$policyDebugValue"
    Write-Output "Remediation failed verification."
    exit 1
}
catch {
    Write-Log "Remediation error: $($_.Exception.Message)"
    Write-Output "Remediation error: $($_.Exception.Message)"
    exit 1
}
