# Report 02: Device inventory from Entra ID + Defender CSV
# Works with scopes: User.Read.All, Directory.Read.All, AuditLog.Read.All
# Intune-enriched variant needs DeviceManagementManagedDevices.Read.All (extra consent)
#
# Defender input: Defender-Devices.csv
#  - KQL export (defender-devices.kql): joins on DeviceId (Entra GUID via AadDeviceId)
#  - Defender portal export (Devices page): joins on DeviceName (fallback), uses LastSeenTime
#
# v3 (2026-10-16): owner lookup fixed (registeredOwner needs the device object Id,
#   not the DeviceId GUID), added ownership/category/enrollment/manufacturer/model fields.

param(
    [string]$Customer = 'customer',
    [int]$ActiveDays = 30,
    [string]$DefenderCsv = '.\Defender-Devices.csv'
)

$requiredModules = @('Microsoft.Graph.Authentication', 'Microsoft.Graph.Identity.DirectoryManagement')
foreach ($m in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $m)) {
        Write-Host "Installing $m..."
        Install-Module $m -Scope CurrentUser -Force
    }
    Import-Module $m -ErrorAction Stop
}

function Normalize-DeviceName([string]$Name) {
    if (-not $Name) { return '' }
    # Entra uses typographic apostrophes (Matteo's), Defender export uses plain (Matteo's)
    ($Name -replace '[\u2018\u2019]', "'").Trim().ToLowerInvariant()
}

function Parse-DefenderDate($Value) {
    if (-not $Value) { return $null }
    # Portal exports use US format: "Oct 14, 2026 3:28:00 PM"
    $parsed = [DateTime]::MinValue
    if ([DateTime]::TryParse([string]$Value, [System.Globalization.CultureInfo]::GetCultureInfo('en-US'),
            [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
        return $parsed.ToUniversalTime()
    }
    return $null
}

# --- Entra ID devices ---
# NOTE: Id = directory object id (needed for registeredOwner), DeviceId = the Entra device GUID
$entra = Get-MgDevice -All |
    Select-Object Id, DisplayName, DeviceId, OperatingSystem, OperatingSystemVersion,
        ProfileType, TrustType, ApproximateLastSignInDateTime, RegistrationDateTime,
        IsCompliant, IsManaged, AccountEnabled,
        DeviceOwnership, DeviceCategory, EnrollmentProfileName, EnrollmentType,
        Manufacturer, Model

# --- Registered owners (best effort, one call per device, keyed on object Id) ---
$owners = @{}
foreach ($d in $entra) {
    try {
        $owner = Get-MgDeviceRegisteredOwner -DeviceId $d.Id -ErrorAction Stop
        if ($owner) {
            # Prefer UPN, fall back to displayName for accounts without UPN
            $upns = $owner | ForEach-Object { $_.AdditionalProperties.userPrincipalName }
            $names = $owner | ForEach-Object { $_.AdditionalProperties.displayName }
            $owners[$d.Id] = ($upns | Where-Object { $_ }) -join '; '
            if (-not $owners[$d.Id]) { $owners[$d.Id] = ($names | Where-Object { $_ }) -join '; ' }
        }
    } catch { $owners[$d.Id] = $null }
}

# --- Defender export (optional) ---
$defender = if (Test-Path $DefenderCsv) {
    $rows = @(Import-Csv $DefenderCsv)
    Write-Host "Defender CSV loaded ($($rows.Count) rows)"
    $rows
} else {
    Write-Warning "Defender-Devices.csv not found - report will lack Defender data."
    $null
}

# Pre-index Defender rows: by DeviceId (KQL export = Entra GUID) and by normalized name
$defById = @{}
$defByName = @{}
$matchedDefenderRows = @{}
foreach ($f in @($defender)) {
    if ($f.DeviceId) { $defById[$f.DeviceId] = $f }
    $key = Normalize-DeviceName $f.DeviceName
    if ($key) { $defByName[$key] = $f }
}

$report = foreach ($d in $entra) {
    $f = $null
    $matchedOn = $null

    # 1) GUID join (works for KQL export that projects AadDeviceId as DeviceId)
    if ($defById.ContainsKey($d.DeviceId)) {
        $f = $defById[$d.DeviceId]; $matchedOn = 'DeviceId'
    }
    # 2) Name fallback (portal export: DeviceId is the MDE hex id, never matches)
    if (-not $f) {
        $key = Normalize-DeviceName $d.DisplayName
        if ($key -and $defByName.ContainsKey($key)) {
            $f = $defByName[$key]; $matchedOn = 'Name'
        }
    }
    if ($f) { $matchedDefenderRows[$f.DeviceId] = $true }

    # Defender "seen": prefer LastSeenTime (portal export = real last check-in).
    # Timestamp in a portal export is the export moment, identical on every row.
    $defSeen = Parse-DefenderDate $f.LastSeenTime
    if (-not $defSeen) { $defSeen = Parse-DefenderDate $f.Timestamp }

    $entraSeen = if ($d.ApproximateLastSignInDateTime) { [DateTime]$d.ApproximateLastSignInDateTime } else { $null }

    $lastSeen = @($entraSeen, $defSeen) | Where-Object { $_ } |
        Sort-Object -Descending | Select-Object -First 1

    $daysSince = if ($lastSeen) {
        [math]::Round(((Get-Date).ToUniversalTime() - $lastSeen).TotalDays, 0)
    } else { $null }

    [PSCustomObject]@{
        DeviceName          = $d.DisplayName
        DeviceId            = $d.DeviceId
        User                = $owners[$d.Id]
        OS                  = $d.OperatingSystem
        OSVersion           = $d.OperatingSystemVersion
        ProfileType         = $d.ProfileType
        TrustType           = $d.TrustType
        DeviceOwnership     = $d.DeviceOwnership
        DeviceCategory      = $d.DeviceCategory
        EnrollmentProfile   = $d.EnrollmentProfileName
        EnrollmentType      = $d.EnrollmentType
        Manufacturer        = $d.Manufacturer
        Model               = $d.Model
        InDefender          = [bool]$f
        MatchedOn           = $matchedOn
        IsManaged           = $d.IsManaged
        IsCompliant         = $d.IsCompliant
        EntraLastSignIn     = $d.ApproximateLastSignInDateTime
        DefenderSeen        = if ($defSeen) { $defSeen.ToString('yyyy-MM-dd HH:mm:ss') } else { $null }
        DefenderHealth      = $f.HealthStatus
        DefenderRisk        = $f.RiskLevel
        Registered          = $d.RegistrationDateTime
        LastSeen            = if ($lastSeen) { $lastSeen.ToString('yyyy-MM-dd HH:mm:ss') } else { $null }
        DaysSinceSeen       = $daysSince
        Status              = if (-not $lastSeen) { 'Never seen' }
                                 elseif ($daysSince -gt $ActiveDays) { "NOT ACTIVE > $ActiveDays days" }
                                 else { 'Active' }
    }
}

# --- Summary ---
$report | Group-Object Status | Sort-Object Count -Descending | Select-Object Name, Count | Format-Table
$report | Group-Object IsManaged | Select-Object @{n='Managed';e={$_.Name}}, Count | Format-Table
if ($defender) {
    $report | Group-Object MatchedOn | Select-Object @{n='JoinedOn';e={if($_.Name){$_.Name}else{'(none)'}}}, Count | Format-Table
}

# --- Defender rows that matched no Entra device: potential "strangely onboarded" devices ---
if ($defender) {
    $unmatched = @($defender | Where-Object {
        -not $matchedDefenderRows.ContainsKey($_.DeviceId) -and
        -not $entra.DeviceId.Contains($_.DeviceId)
    })
    if ($unmatched.Count -gt 0) {
        Write-Warning "$($unmatched.Count) Defender device(s) not found in Entra ID:"
        $unmatched | Select-Object DeviceName, DeviceId, LastSeenTime | Format-Table
    } else {
        Write-Host "All Defender devices matched an Entra device."
    }
}

$date = Get-Date -Format 'yyyy-MM-dd'
$report | Sort-Object Status, DaysSinceSeen -Descending |
    Export-Csv ".\$Customer-Devices-Entra-$date.csv" -NoTypeInformation -Encoding UTF8
Write-Host "Report exported ($(@($report).Count) devices)"