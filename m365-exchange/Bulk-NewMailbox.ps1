<#
================================================================================
 Script Name : Bulk-NewMailbox.ps1
 Author      : <Your Name>
 Version     : 1.1
 Purpose     : Bulk provision Exchange Online user mailboxes for a specific tenant
               and optionally send a welcome email.
 How to run it with no mailbox just email:
   .\Bulk-NewMailbox.ps1 -TenantAdminUpn admin@contoso.com -CsvPath .\mailboxes.csv

 How to run it with mailbox and email:
 .\Bulk-NewMailbox.ps1 `
  -TenantAdminUpn admin@contoso.com `
  -CsvPath .\mailboxes.csv `
  -SendWelcomeEmail `
  -WelcomeFromUpn it-notify@contoso.com `
  -WelcomeCc helpdesk@contoso.com `
  -HelpdeskUrl "https://helpdesk.contoso.com" `
  -PasswordResetUrl "https://passwordreset.contoso.com"

 Description :
   This script automates mailbox creation in Exchange Online using a CSV file.
   It is designed to be safe, repeatable, auditable, and suitable for enterprise
   provisioning workflows.

   Key Features:
   - Idempotent execution:
       If a mailbox already exists, the script skips it safely.
   - Structured logging:
       Writes detailed logs for audit and troubleshooting.
   - Machine-readable output:
       Generates CSV and JSON reports.
   - Tenant-scoped execution:
       Connects explicitly to the target tenant via admin UPN.
   - Error isolation:
       One failure does not stop the entire batch.
   - Optional welcome email:
       Sends a welcome email to newly created users via Microsoft Graph.

 Future Enhancements (Design Notes):
   1. Dry-run mode (-WhatIf)
      Allows administrators to preview mailbox creation without changes.

   2. Password generation
      Auto-generate strong passwords instead of storing plaintext in CSV.

   3. Welcome email templates
      Multiple templates (contractor vs employee) and localization support.

   4. Rollback mode
      Disable user and remove mailbox if provisioning must be reverted.

   5. Provisioning timeout verification
      Poll mailbox existence to confirm backend completion.

 CSV Format:
   Required:
     UserPrincipalName,DisplayName,FirstName,LastName,Password
   Optional:
     Alias

 Example:
   jane.doe@contoso.com,Jane Doe,Jane,Doe,P@ssw0rd!234,jane.doe

================================================================================
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [string]$TenantAdminUpn,

  [Parameter(Mandatory)]
  [string]$CsvPath,

  [string]$ResultsCsv  = "$env:ProgramData\IT_Scripts\Reports\new_mailbox_results.csv",
  [string]$SummaryJson = "$env:ProgramData\IT_Scripts\Reports\new_mailbox_summary.json",
  [string]$LogPath     = "$env:ProgramData\IT_Scripts\Logs\bulk_newmailbox.log",

  # Welcome email automation
  [switch]$SendWelcomeEmail,

  # The mailbox that will send the welcome email (shared mailbox recommended).
  # Requires Microsoft Graph permissions to send mail as this user.
  [string]$WelcomeFromUpn = "",

  # Optional: CC IT/helpdesk
  [string[]]$WelcomeCc = @(),

  # Optional: Link(s) inserted into email
  [string]$HelpdeskUrl = "",
  [string]$PasswordResetUrl = ""
)

$ErrorActionPreference = "Stop"

function Ensure-Dir([string]$Path) {
  $dir = Split-Path $Path -Parent
  if ($dir -and -not (Test-Path $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
}

function Write-Log([string]$Msg) {
  Ensure-Dir $LogPath
  Add-Content -Path $LogPath -Value "$((Get-Date).ToString('s')) $Msg"
}

function Require-Module([string]$Name) {
  if (-not (Get-Module -ListAvailable -Name $Name)) {
    throw "Required module '$Name' is not installed. Install-Module $Name"
  }
  Import-Module $Name -ErrorAction Stop
}

function HtmlEncode([string]$s) {
  if ($null -eq $s) { return "" }
  return [System.Net.WebUtility]::HtmlEncode($s)
}

function Build-WelcomeEmailHtml {
  param(
    [Parameter(Mandatory)][string]$DisplayName,
    [Parameter(Mandatory)][string]$UserPrincipalName,
    [Parameter(Mandatory)][string]$TempPassword,
    [string]$HelpdeskUrl,
    [string]$PasswordResetUrl
  )

  $dn  = HtmlEncode $DisplayName
  $upn = HtmlEncode $UserPrincipalName
  $pw  = HtmlEncode $TempPassword

  $helpLine = ""
  if ($HelpdeskUrl) {
    $helpLine = "<li>Helpdesk: <a href='$([System.Net.WebUtility]::HtmlEncode($HelpdeskUrl))'>$([System.Net.WebUtility]::HtmlEncode($HelpdeskUrl))</a></li>"
  }

  $resetLine = ""
  if ($PasswordResetUrl) {
    $resetLine = "<li>Password reset: <a href='$([System.Net.WebUtility]::HtmlEncode($PasswordResetUrl))'>$([System.Net.WebUtility]::HtmlEncode($PasswordResetUrl))</a></li>"
  }

  @"
<html>
  <body style="font-family: Segoe UI, Arial, sans-serif; font-size: 12pt;">
    <p>Hello $dn,</p>

    <p>Your company mailbox has been created.</p>

    <p><b>Sign-in details</b></p>
    <ul>
      <li>Username: <b>$upn</b></li>
      <li>Temporary password: <b>$pw</b></li>
      <li>You will be prompted to change your password at first sign-in.</li>
    </ul>

    <p><b>Next steps</b></p>
    <ul>
      <li>Sign in to Outlook on the web or Outlook desktop using the credentials above.</li>
      $resetLine
      $helpLine
    </ul>

    <p>If you have any issues signing in, please contact IT support.</p>

    <p>Thanks,<br/>IT Support</p>
  </body>
</html>
"@
}

function Send-WelcomeEmailGraph {
  param(
    [Parameter(Mandatory)][string]$FromUpn,
    [Parameter(Mandatory)][string]$ToUpn,
    [string[]]$CcUpn = @(),
    [Parameter(Mandatory)][string]$Subject,
    [Parameter(Mandatory)][string]$HtmlBody
  )

  # Requires Microsoft.Graph module and appropriate Graph permissions/consent.
  # Typical delegated: Mail.Send. Typical app-only: Mail.Send (application) + send as mailbox.
  Require-Module "Microsoft.Graph.Users.Actions"

  $toRecipients = @(@{ emailAddress = @{ address = $ToUpn } })

  $ccRecipients = @()
  foreach ($c in $CcUpn) {
    if ($c -and $c.Trim()) {
      $ccRecipients += @{ emailAddress = @{ address = $c.Trim() } }
    }
  }

  $message = @{
    subject = $Subject
    body    = @{
      contentType = "HTML"
      content     = $HtmlBody
    }
    toRecipients  = $toRecipients
  }

  if ($ccRecipients.Count -gt 0) {
    $message["ccRecipients"] = $ccRecipients
  }

  # Send as the configured sender mailbox
  Send-MgUserMail -UserId $FromUpn -Message $message -SaveToSentItems:$true | Out-Null
}

try {
  Ensure-Dir $ResultsCsv
  Ensure-Dir $SummaryJson

  Write-Log "Starting bulk mailbox provisioning. CSV=$CsvPath"

  if ($SendWelcomeEmail) {
    if (-not $WelcomeFromUpn) {
      throw "SendWelcomeEmail was specified but WelcomeFromUpn is empty."
    }
    Write-Log "Welcome email enabled. From=$WelcomeFromUpn"
  }

  Require-Module "ExchangeOnlineManagement"
  Connect-ExchangeOnline -UserPrincipalName $TenantAdminUpn -ShowBanner:$false | Out-Null

  if ($SendWelcomeEmail) {
    # Connect to Graph (interactive by default). For automation, use app-only with cert.
    Require-Module "Microsoft.Graph.Authentication"
    Connect-MgGraph -Scopes "Mail.Send" | Out-Null
  }

  $rows = Import-Csv -Path $CsvPath
  if (-not $rows -or $rows.Count -eq 0) {
    throw "CSV contains no rows."
  }

  $results = New-Object System.Collections.Generic.List[object]

  foreach ($r in $rows) {
    $upn   = $r.UserPrincipalName
    $alias = if ($r.Alias) { $r.Alias } else { ($upn.Split("@")[0]) }

    $res = [ordered]@{
      UserPrincipalName  = $upn
      Alias              = $alias
      Action             = ""
      Success            = $false
      Notes              = ""
      WelcomeEmailSent   = $false
      WelcomeEmailError  = ""
      Timestamp          = (Get-Date).ToString("o")
    }

    try {
      if (-not $upn) { throw "Missing UserPrincipalName." }
      if (-not $r.Password) { throw "Missing Password for $upn." }
      if (-not $r.DisplayName) { throw "Missing DisplayName for $upn." }

      # Idempotency: if mailbox exists, skip
      $existing = Get-Mailbox -Identity $upn -ErrorAction SilentlyContinue
      if ($existing) {
        $res.Action  = "Skip"
        $res.Success = $true
        $res.Notes   = "Mailbox already exists."
        Write-Log "SKIP $upn (exists)"
        $results.Add([pscustomobject]$res)
        continue
      }

      Write-Log "CREATE $upn alias=$alias"

      $securePass = ConvertTo-SecureString -String $r.Password -AsPlainText -Force

      New-Mailbox `
        -UserPrincipalName $upn `
        -Alias $alias `
        -Name $r.DisplayName `
        -DisplayName $r.DisplayName `
        -FirstName $r.FirstName `
        -LastName $r.LastName `
        -Password $securePass `
        -ResetPasswordOnNextLogon $true | Out-Null

      $res.Action  = "Create"
      $res.Success = $true
      $res.Notes   = "Mailbox created successfully."
      Write-Log "CREATE OK $upn"

      # Optional welcome email for newly created mailboxes
      if ($SendWelcomeEmail) {
        try {
          $subject = "Welcome - Your mailbox is ready"
          $body = Build-WelcomeEmailHtml `
            -DisplayName $r.DisplayName `
            -UserPrincipalName $upn `
            -TempPassword $r.Password `
            -HelpdeskUrl $HelpdeskUrl `
            -PasswordResetUrl $PasswordResetUrl

          Send-WelcomeEmailGraph `
            -FromUpn $WelcomeFromUpn `
            -ToUpn $upn `
            -CcUpn $WelcomeCc `
            -Subject $subject `
            -HtmlBody $body

          $res.WelcomeEmailSent = $true
          Write-Log "WELCOME EMAIL OK $upn"
        }
        catch {
          $res.WelcomeEmailSent  = $false
          $res.WelcomeEmailError = $_.Exception.Message
          Write-Log "WELCOME EMAIL ERROR $upn : $($_.Exception.Message)"
        }
      }
    }
    catch {
      $res.Action  = "Error"
      $res.Success = $false
      $res.Notes   = $_.Exception.Message
      Write-Log "ERROR $upn : $($_.Exception.Message)"
    }

    $results.Add([pscustomobject]$res)
  }

  $results | Export-Csv -NoTypeInformation -Path $ResultsCsv -Force

  $summary = [pscustomobject]@{
    TenantAdminUpn = $TenantAdminUpn
    CsvPath        = $CsvPath
    RunAt          = (Get-Date).ToString("o")
    Total          = $results.Count
    Created        = ($results | Where-Object { $_.Action -eq "Create" }).Count
    Skipped        = ($results | Where-Object { $_.Action -eq "Skip" }).Count
    Failed         = ($results | Where-Object { $_.Action -eq "Error" }).Count
    WelcomeSent    = ($results | Where-Object { $_.WelcomeEmailSent }).Count
    Results        = $results
  }

  $summary | ConvertTo-Json -Depth 7 | Out-File -FilePath $SummaryJson -Encoding utf8 -Force

  Write-Log "Provisioning complete. Results=$ResultsCsv Summary=$SummaryJson"

  Disconnect-ExchangeOnline -Confirm:$false | Out-Null
  if ($SendWelcomeEmail) { Disconnect-MgGraph | Out-Null }

  exit 0
}
catch {
  Write-Log "FATAL: $($_.Exception.Message)"
  try { Disconnect-ExchangeOnline -Confirm:$false | Out-Null } catch {}
  try { Disconnect-MgGraph | Out-Null } catch {}
  exit 1
}
