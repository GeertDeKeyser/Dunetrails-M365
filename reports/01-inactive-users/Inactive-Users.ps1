# Report 01: Inactive users
# Prereq: tenant-wide admin consent for User.Read.All, Directory.Read.All, AuditLog.Read.All (see docs/consent-and-gdap.md)
# Connect first: Connect-MgGraph -TenantId <customer-tenant-id> -Scopes "User.Read.All","Directory.Read.All","AuditLog.Read.All"

param(
    [string]$Customer = 'customer',
    [int]$ThresholdDays = 60
)

$users = Get-MgUser -All -Property Id, UserPrincipalName, DisplayName, AccountEnabled,
    SignInActivity, CreatedDateTime, UserType, JobTitle

$report = foreach ($u in $users) {
    $lastInteractive     = $u.SignInActivity.LastSignInDateTime
    $lastNonInteractive  = $u.SignInActivity.LastNonInteractiveSignInDateTime

    # Most recent of both sign-in types (handles either being null)
    $lastActivity = @($lastInteractive, $lastNonInteractive) |
        Where-Object { $_ } |
        Sort-Object -Descending |
        Select-Object -First 1

    $daysSince = if ($lastActivity) {
        [math]::Round(((Get-Date).ToUniversalTime() - $lastActivity).TotalDays, 0)
    } else { $null }

    [PSCustomObject]@{
        DisplayName        = $u.DisplayName
        UserPrincipalName  = $u.UserPrincipalName
        Enabled            = $u.AccountEnabled
        Type               = $u.UserType
        Title              = $u.JobTitle
        Created            = $u.CreatedDateTime
        LastSignIn         = $lastInteractive
        LastNonInteractive = $lastNonInteractive
        LastActivity       = $lastActivity
        DaysSinceActivity  = $daysSince
        Status             = if (-not $lastActivity) { 'Never signed in' }
                              elseif ($daysSince -gt $ThresholdDays) { "INACTIVE > $ThresholdDays days" }
                              else { 'Active' }
    }
}

$report | Group-Object Status | Sort-Object Count -Descending | Select-Object Name, Count | Format-Table

$exportPath = ".\$Customer-InactiveUsers-$(Get-Date -Format 'yyyy-MM-dd').csv"
$report | Sort-Object DaysSinceActivity -Descending |
    Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8

Write-Host "Report exported to $exportPath ($($report.Count) users)"
