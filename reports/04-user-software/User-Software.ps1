# Report 04: Software assignment per user (user - devices - software)
# Input: Tvm-Software.csv (kql/tvm-software.kql export, next to this script)
#        + <Customer>-Devices-Entra-<date>.csv from report 02 (join: TVM AadDeviceId = Entra DeviceId)

param(
    [string]$Customer = 'customer'
)

$devices = Get-ChildItem ".\$Customer-Devices-Entra-*.csv" |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Import-Csv

if (-not $devices) { throw "Run report 02 first - no $Customer-Devices-Entra-*.csv found." }

$software = Import-Csv .\Tvm-Software.csv

$report = foreach ($d in $devices) {
    $sw = $software | Where-Object AadDeviceId -eq $d.DeviceId
    [PSCustomObject]@{
        User          = $d.User
        DeviceName    = $d.DeviceName
        LastSeen      = $d.LastSeen
        Software      = ($sw | ForEach-Object { "$($_.SoftwareName) $($_.SoftwareVersion)" }) -join '; '
        SoftwareCount = @($sw).Count
    }
}

$license = $software | Group-Object SoftwareName, SoftwareVendor |
    Select-Object @{n='Software';e={$_.Name}}, Count |
    Sort-Object Count -Descending

$report | Sort-Object User | Format-Table User, DeviceName, SoftwareCount -AutoSize
$license | Select-Object -First 30 | Format-Table -AutoSize

$date = Get-Date -Format 'yyyy-MM-dd'
$report  | Sort-Object User | Export-Csv ".\$Customer-UserSoftware-$date.csv" -NoTypeInformation -Encoding UTF8
$license | Export-Csv ".\$Customer-SoftwareLicense-$date.csv" -NoTypeInformation -Encoding UTF8
