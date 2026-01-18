$ErrorActionPreference = "Stop"

$duoRegBase    = "HKLM:\SOFTWARE\Duo Security\DuoCredProv"
$duoPolicyBase = "HKLM:\SOFTWARE\Policies\Duo Security\DuoCredProv"

function Test-DuoInstalled {
    # Registry key is a strong signal, but also check common install path(s) to avoid false negatives
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
        Write-Output "Not applicable: Duo Windows Logon & RDP not detected on this device."
        exit 0
    }

    $debugValue = $null
    if (Test-Path $duoRegBase) {
        try { $debugValue = (Get-ItemProperty -Path $duoRegBase -Name "Debug" -ErrorAction Stop)."Debug" } catch { $debugValue = $null }
    }

    $policyDebugValue = $null
    if (Test-Path $duoPolicyBase) {
        # Duo documentation references lower-case 'debug' under Policies (may be enforced/reverted by GPO)
        try { $policyDebugValue = (Get-ItemProperty -Path $duoPolicyBase -Name "debug" -ErrorAction Stop)."debug" } catch { $policyDebugValue = $null }
    }

    $regOk    = ($debugValue -eq 1)
    $policyOk = ($policyDebugValue -eq 1 -or -not (Test-Path $duoPolicyBase))  # if no policy key exists, don't fail on it

    if ($regOk -and $policyOk) {
        Write-Output "Compliant: Duo debug logging enabled. (Debug=$debugValue, PolicyDebug=$policyDebugValue)"
        exit 0
    }

    Write-Output "Non-compliant: Duo debug logging not enabled as expected. (Debug=$debugValue, PolicyDebug=$policyDebugValue)"
    exit 1
}
catch {
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}
