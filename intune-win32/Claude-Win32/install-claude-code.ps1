$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string]$Message)
    Write-Output "$(Get-Date -Format s) $Message"
}

function Get-UserPathEntries {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ([string]::IsNullOrWhiteSpace($userPath)) { return @() }
    return $userPath -split ';' | Where-Object { $_ -and $_.Trim() -ne '' }
}

function Add-UserPathIfMissing {
    param([string]$PathToAdd)

    if (-not (Test-Path $PathToAdd)) { return }

    $entries = Get-UserPathEntries
    $normalized = $entries | ForEach-Object { $_.TrimEnd('\\') }
    if ($normalized -notcontains $PathToAdd.TrimEnd('\\')) {
        $entries += $PathToAdd
        [Environment]::SetEnvironmentVariable('Path', ($entries -join ';'), 'User')
        Write-Log "Added to user PATH: $PathToAdd"
    }
}

function Test-ClaudeInstalled {
    $possiblePaths = @(
        (Join-Path $env:USERPROFILE '.local\bin\claude.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Claude\claude.exe')
    )

    foreach ($path in $possiblePaths) {
        if (Test-Path $path) { return $true }
    }

    $cmd = Get-Command claude -ErrorAction SilentlyContinue
    return [bool]$cmd
}

try {
    $gitBash = Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe'
    if (-not (Test-Path $gitBash)) {
        throw 'PortableGit dependency not found in the user profile. Deploy Git package first.'
    }

    Add-UserPathIfMissing -PathToAdd (Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd')
    Add-UserPathIfMissing -PathToAdd (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin')

    if (Test-ClaudeInstalled) {
        Write-Log 'Claude Code already installed.'
        Add-UserPathIfMissing -PathToAdd (Join-Path $env:USERPROFILE '.local\bin')
        exit 0
    }

    Write-Log 'Running Claude Code installer...'
    $installScript = Invoke-RestMethod -Uri 'https://claude.ai/install.ps1'
    & ([scriptblock]::Create($installScript))

    Add-UserPathIfMissing -PathToAdd (Join-Path $env:USERPROFILE '.local\bin')

    if (-not (Test-ClaudeInstalled)) {
        throw 'Claude Code install completed but the cli was not detected.'
    }

    Write-Log 'Claude Code install completed successfully.'
    exit 0
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
