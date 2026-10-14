# Graph consent under GDAP (partner context)

## The problem

Partner delegated admins get **AADSTS90099** when connecting with `-Scopes` that are not yet consented in the customer tenant. Consent for multi-tenant first-party apps (e.g. Microsoft Graph Command Line Tools, 14d82eec-204b-4c2f-b7e8-296a70dab67e) must be granted **by an admin inside the customer tenant**. Without `-Scopes`, the app connects but only with User.Read -> 403 Authorization_RequestDenied on most calls.

## The fix (one time, per customer tenant)

A customer tenant admin (Global Admin / Cloud Application Admin / Application Admin) runs:

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Connect-MgGraph -TenantId <customer-tenant-id> -Scopes "User.Read.All","Directory.Read.All","AuditLog.Read.All","DeviceManagementManagedDevices.Read.All" -NoWelcome
```

Accept the consent prompt. The grant is tenant-wide and lands on the enterprise app; partner connections get the scopes afterwards without any prompt.

## Verify

Entra admin center -> Enterprise applications -> Microsoft Graph Command Line Tools -> Permissions: scopes should show as Delegated / Admin consent / An administrator.

## Notes

- The "Grant admin consent" button on that blade only re-consents scopes the app has already requested (i.e. User.Read) - use the PowerShell route instead.
- Changing the scope set later requires re-consent (remove + re-add via Partner Center API or re-run with the new scopes).
