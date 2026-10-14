# Report 03: Vulnerability report for actively used devices
# Input: Tvm-Vulnerabilities.csv (kql/tvm-vulnerabilities.kql export, next to this script)
#        + <Customer>-Devices-Entra-<date>.csv from report 02 (join: TVM AadDeviceId = Entra DeviceId)

param(
    [string]$Customer = 'customer',
    [int]$ActiveDays = 30
)

$devices = Get-ChildItem ".\$Customer-Devices-Entra-*.csv" |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Import-Csv

if (-not $devices) { throw "Run report 02 first - no $Customer-Devices-Entra-*.csv found." }

$activeDevices = $devices | Where-Object {
    $_.DaysSinceSeen -ne '' -and [int]$_.DaysSinceSeen -le $ActiveDays
}
$activeIds = @($activeDevices.DeviceId)

$vulns = Import-Csv .\Tvm-Vulnerabilities.csv |
    Where-Object { $activeIds -contains $_.AadDeviceId }

$vulSummary = foreach ($d in $activeDevices) {
    $dv = @($vulns | Where-Object AadDeviceId -eq $d.DeviceId)
    [PSCustomObject]@{
        DeviceName   = $d.DeviceName
        User         = $d.User
        LastSeen     = $d.LastSeen
        OSVersion    = $d.OSVersion
        TotalCVEs    = $dv.Count
        Critical     = @($dv | Where-Object VulnerabilitySeverityLevel -eq 'Critical').Count
        High         = @($dv | Where-Object VulnerabilitySeverityLevel -eq 'High').Count
        Medium       = @($dv | Where-Object VulnerabilitySeverityLevel -eq 'Medium').Count
        Low          = @($dv | Where-Object VulnerabilitySeverityLevel -eq 'Low').Count
        Status       = if (@($dv | Where-Object VulnerabilitySeverityLevel -eq 'Critical').Count -gt 0) { 'ACTION: critical CVEs' }
                        elseif (@($dv | Where-Object VulnerabilitySeverityLevel -eq 'High').Count -gt 0) { 'Attention: high CVEs' }
                        elseif ($dv.Count -gt 0) { 'Monitor' }
                        else { 'OK' }
    }
}

$vulSummary | Group-Object Status | Select-Object Name, Count | Format-Table

$date = Get-Date -Format 'yyyy-MM-dd'
$vulSummary | Sort-Object Critical, High -Descending |
    Export-Csv ".\$Customer-Vuln-Summary-$date.csv" -NoTypeInformation -Encoding UTF8
$vulns | Export-Csv ".\$Customer-Vuln-Details-$date.csv" -NoTypeInformation -Encoding UTF8
Write-Host "Report exported ($(@($vulSummary).Count) active devices)"
