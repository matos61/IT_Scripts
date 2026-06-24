$ErrorActionPreference = 'Stop'

try {
    $possiblePaths = @(
        (Join-Path $env:USERPROFILE '.local\bin\claude.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Claude\claude.exe')
    )

    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            Write-Output "Detected Claude Code at $path"
            exit 0
        }
    }

    $cmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Output "Detected Claude Code via PATH at $($cmd.Source)"
        exit 0
    }

    Write-Output 'Claude Code not detected in user profile.'
    exit 1
}
catch {
    Write-Output "Detection error: $($_.Exception.Message)"
    exit 1
}
