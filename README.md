# Dunetrails M365 Reporting Toolkit

PowerShell + KQL toolkit for recurring Microsoft 365 hygiene reports for managed-service customers (Entra ID, Intune, Defender). Built for delegated partner access (GDAP) - no app registration required; scripts run interactively.

## Reports

| # | Report | Script | Data sources |
|---|--------|--------|--------------|
| 01 | Inactive users | `reports/01-inactive-users/Inactive-Users.ps1` | Graph (Entra) |
| 02 | Device inventory | `reports/02-device-list/Device-List.ps1` | Graph (Entra) + Defender CSV |
| 03 | Vulnerabilities (active devices) | `reports/03-vulnerabilities/Vuln-Report.ps1` | Report 02 + Defender TVM CSV |
| 04 | Software per user | `reports/04-user-software/User-Software.ps1` | Report 02 + Defender TVM CSV |

## Configuration

Each script has a `$Customer` variable at the top (used in output filenames). The tenant ID is passed at connect time, not stored in scripts:

```powershell
Connect-MgGraph -TenantId <customer-tenant-id> -UseDeviceAuthentication -NoWelcome -Scopes "User.Read.All","Directory.Read.All","AuditLog.Read.All"
```

## Workflow per run

1. Connect (see above; one-time tenant consent prerequisite - see docs/consent-and-gdap.md).
2. Run the Defender XDR KQL queries (`kql/` in each report folder) in Advanced Hunting; export CSVs next to the scripts.
3. Run reports in order: 01 and 02 first (02 produces the device join table for 03/04), then 03/04.
4. Output: dated CSV files per report.

## Prerequisites

- Windows PowerShell 5.1: set `[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12` before Install-Module. PowerShell 7 recommended.
- Tenant-wide admin consent in the **customer tenant** for the Microsoft Graph Command Line Tools app with the scopes above. Partner delegated admins cannot self-consent additional scopes (AADSTS90099); a customer tenant admin must run the Connect-MgGraph with -Scopes once (see docs/consent-and-gdap.md).
- Extra scope for Intune-enriched device data: `DeviceManagementManagedDevices.Read.All`.

## Conventions

- Join keys: Entra `DeviceId` = TVM `AadDeviceId` (GUID). Never join on device name.
- TVM tables (`DeviceTvm*`) are snapshot tables: no Timestamp filter; activity filtering happens via report 02 DaysSinceSeen.
- Output files are dated, never overwrite previous runs.
