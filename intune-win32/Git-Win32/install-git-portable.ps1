$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string]$Message)
    Write-Output "$(Get-Date -Format s) $Message"
}

try {
    $installRoot = Join-Path $env:LOCALAPPDATA 'Programs\Git'
    $bashPath = Join-Path $installRoot 'bin\bash.exe'
    $tempInstaller = Join-Path $env:TEMP 'PortableGit-64-bit.7z.exe'

    if (Test-Path $bashPath) {
        Write-Log "PortableGit already installed at $installRoot"
        exit 0
    }

    Write-Log 'Downloading PortableGit...'
    Invoke-WebRequest -Uri 'https://github.com/git-for-windows/git/releases/latest/download/PortableGit-64-bit.7z.exe' -OutFile $tempInstaller -UseBasicParsing

    if (-not (Test-Path $installRoot)) {
        New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
    }

    Write-Log 'Extracting PortableGit...'
    Start-Process -FilePath $tempInstaller -ArgumentList "-y", "-o$installRoot" -Wait -NoNewWindow

    if (-not (Test-Path $bashPath)) {
        throw 'PortableGit install completed but bash.exe was not found.'
    }

    $gitCmdPath = Join-Path $installRoot 'cmd'
    $gitBinPath = Join-Path $installRoot 'bin'
    $currentUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $paths = @()
    if (-not [string]::IsNullOrWhiteSpace($currentUserPath)) {
        $paths = $currentUserPath -split ';' | Where-Object { $_ -and $_.Trim() -ne '' }
    }

    foreach ($pathToAdd in @($gitCmdPath, $gitBinPath)) {
        if (($paths | ForEach-Object { $_.TrimEnd('\\') }) -notcontains $pathToAdd.TrimEnd('\\')) {
            $paths += $pathToAdd
            Write-Log "Added to user PATH: $pathToAdd"
        }
    }

    [Environment]::SetEnvironmentVariable('Path', ($paths -join ';'), 'User')

    Write-Log 'PortableGit install completed successfully.'
    exit 0
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
