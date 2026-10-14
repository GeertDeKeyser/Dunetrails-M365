# Report 02: Device inventory from Entra ID + optional Defender CSV
# Works with scopes: User.Read.All, Directory.Read.All, AuditLog.Read.All
# Optional input: Defender-Devices.csv (kql/defender-devices.kql export)
# Intune-enriched variant needs DeviceManagementManagedDevices.Read.All (extra consent)

param(
    [string]$Customer = 'customer',
    [int]$ActiveDays = 30
)

$requiredModules = @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Identity.DirectoryManagement')
foreach ($m in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $m)) {
        Write-Host "Installing $m..."
        Install-Module $m -Scope CurrentUser -Force
    }
    Import-Module $m -ErrorAction Stop
}

# --- Entra ID devices ---
$entra = Get-MgDevice -All |
    Select-Object DisplayName, DeviceId, OperatingSystem, OperatingSystemVersion,
        ProfileType, TrustType, ApproximateLastSignInDateTime, RegistrationDateTime,
        IsCompliant, IsManaged, AccountEnabled

# --- Registered owners (best effort, one call per device) ---
$owners = @{}
foreach ($d in $entra) {
    try {
        $owner = Get-MgDeviceRegisteredOwner -DeviceId $d.DeviceId -ErrorAction Stop
        if ($owner) { $owners[$d.DeviceId] = ($owner | ForEach-Object { $_.AdditionalProperties.userPrincipalName }) -join '; ' }
    } catch { $owners[$d.DeviceId] = $null }
}

# --- Defender export (optional) ---
$defender = if (Test-Path .\Defender-Devices.csv) {
    $rows = Import-Csv .\Defender-Devices.csv
    Write-Host "Defender CSV loaded ($(@($rows).Count) rows)"
    $rows
} else {
    Write-Warning "Defender-Devices.csv not found - report will lack Defender data."
    $null
}

$report = foreach ($d in $entra) {
    $f = if ($defender) { $defender | Where-Object { $_.DeviceId -eq $d.DeviceId } | Select-Object -First 1 }

    $lastSeen = @($d.ApproximateLastSignInDateTime, $f.Timestamp) |
        Where-Object { $_ } | Sort-Object -Descending | Select-Object -First 1

    $daysSince = if ($lastSeen) {
        [math]::Round(((Get-Date).ToUniversalTime() - $lastSeen).TotalDays, 0)
    } else { $null }

    [PSCustomObject]@{
        DeviceName      = $d.DisplayName
        DeviceId        = $d.DeviceId
        User            = $owners[$d.DeviceId]
        OS              = $d.OperatingSystem
        OSVersion       = $d.OperatingSystemVersion
        ProfileType     = $d.ProfileType
        TrustType       = $d.TrustType
        InDefender      = [bool]$f
        IsManaged       = $d.IsManaged
        IsCompliant     = $d.IsCompliant
        EntraLastSignIn = $d.ApproximateLastSignInDateTime
        DefenderSeen    = $f.Timestamp
        DefenderHealth  = $f.HealthStatus
        DefenderRisk    = $f.RiskLevel
        Registered      = $d.RegistrationDateTime
        LastSeen        = $lastSeen
        DaysSinceSeen   = $daysSince
        Status          = if (-not $lastSeen) { 'Never seen' }
                             elseif ($daysSince -gt $ActiveDays) { "NOT ACTIVE > $ActiveDays days" }
                             else { 'Active' }
    }
}

$report | Group-Object Status | Sort-Object Count -Descending | Select-Object Name, Count | Format-Table
$report | Group-Object IsManaged | Select-Object @{n='Managed';e={$_.Name}}, Count | Format-Table

$date = Get-Date -Format 'yyyy-MM-dd'
$report | Sort-Object Status, DaysSinceSeen -Descending |
    Export-Csv ".\$Customer-Devices-Entra-$date.csv" -NoTypeInformation -Encoding UTF8
Write-Host "Report exported ($(@($report).Count) devices)"
