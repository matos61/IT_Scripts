PACKAGE 1: Git-Win32
- Source folder contents:
  install-git-portable.ps1
  detect-git-portable.ps1
- IntuneWin command example:
  IntuneWinAppUtil.exe -c .\Git-Win32 -s install-git-portable.ps1 -o .\output
- Install command:
  powershell.exe -ExecutionPolicy Bypass -File .\install-git-portable.ps1
- Uninstall command:
  cmd.exe /c rmdir /s /q "%LOCALAPPDATA%\Programs\Git"
- Install behavior:
  User
- Device restart behavior:
  No specific action
- Return codes:
  Default is fine
- Detection rule:
  Use custom detection script: detect-git-portable.ps1
  Run script as 64-bit: Yes

PACKAGE 2: Claude-Win32
- Source folder contents:
  install-claude-code.ps1
  detect-claude-code.ps1
- IntuneWin command example:
  IntuneWinAppUtil.exe -c .\Claude-Win32 -s install-claude-code.ps1 -o .\output
- Install command:
  powershell.exe -ExecutionPolicy Bypass -File .\install-claude-code.ps1
- Uninstall command:
  powershell.exe -ExecutionPolicy Bypass -Command "& { $p = Join-Path $env:USERPROFILE '.local\bin\claude.exe'; if (Test-Path $p) { Remove-Item $p -Force } }"
- Install behavior:
  User
- Device restart behavior:
  No specific action
- Return codes:
  Default is fine
- Detection rule:
  Use custom detection script: detect-claude-code.ps1
  Run script as 64-bit: Yes
- Dependency:
  Git-Win32 must be installed first

RECOMMENDED TEST FLOW
1. Assign Git-Win32 as Available to your test user.
2. Install Git-Win32 from Company Portal or required assignment.
3. Assign Claude-Win32 with Git-Win32 as dependency.
4. Install Claude-Win32 and verify `claude` launches in a new terminal.
5. Authenticate manually by running `claude` as the user.
