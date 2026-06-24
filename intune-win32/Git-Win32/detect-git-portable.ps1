$ErrorActionPreference = 'Stop'

try {
    $bashPath = Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe'

    if (Test-Path $bashPath) {
        Write-Output "Detected PortableGit at $bashPath"
        exit 0
    }

    Write-Output 'PortableGit not detected in user profile.'
    exit 1
}
catch {
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}
