<#
.SYNOPSIS
Search, download and install Windows Updates using Windows Update Agent COM API.

.PARAMETER IncludeDrivers
Include driver updates as well (default: $false -> software updates only).

.PARAMETER SecurityCriticalOnly
Install only Security Updates and Critical Updates categories.

.PARAMETER Reboot
Automatically reboot if required after installation (default: no reboot).

.NOTES
Run as Administrator.
#>

[CmdletBinding()]
param(
    [switch]$IncludeDrivers,
    [switch]$SecurityCriticalOnly,
    [switch]$Reboot
)

function New-UpdateSession {
    return New-Object -ComObject "Microsoft.Update.Session"
}

function Get-UpdateCategoryNames {
    param([Parameter(Mandatory)]$Update)

    # Some updates may have no Categories populated, so be defensive
    try {
        $names = @()
        foreach ($c in $Update.Categories) { $names += $c.Name }
        return $names
    } catch {
        return @()
    }
}

function Is-SecurityOrCritical {
    param([Parameter(Mandatory)]$Update)

    $catNames = Get-UpdateCategoryNames -Update $Update
    return ($catNames -contains "Security Updates") -or ($catNames -contains "Critical Updates")
}

# --- Build search criteria (WUA query language) ---
# Base: applicable, not installed, not hidden
$criteria = "IsInstalled=0 and IsHidden=0"

# If not including drivers, restrict to software updates only
if (-not $IncludeDrivers) {
    $criteria += " and Type='Software'"
}

Write-Host "Searching for updates..."
Write-Host "Criteria: $criteria"

$session  = New-UpdateSession
$searcher = $session.CreateUpdateSearcher()
$searchResult = $searcher.Search($criteria)

if ($searchResult.Updates.Count -eq 0) {
    Write-Host "No applicable updates found."
    return
}

# --- Build collection to install ---
$updatesToInstall = New-Object -ComObject "Microsoft.Update.UpdateColl"

for ($i = 0; $i -lt $searchResult.Updates.Count; $i++) {
    $u = $searchResult.Updates.Item($i)

    # Optional: filter to Security + Critical only
    if ($SecurityCriticalOnly) {
        if (-not (Is-SecurityOrCritical -Update $u)) {
            Write-Host "Skipping (not Security/Critical): $($u.Title)"
            continue
        }
    }

    # Optional: skip updates that may prompt the user
    if ($u.InstallationBehavior.CanRequestUserInput) {
        Write-Host "Skipping (needs user input): $($u.Title)"
        continue
    }

    # Accept EULA if needed
    if (-not $u.EulaAccepted) {
        Write-Host "Accepting EULA: $($u.Title)"
        $u.AcceptEula()
    }

    [void]$updatesToInstall.Add($u)
}

if ($updatesToInstall.Count -eq 0) {
    Write-Host "No updates left to install after filtering."
    return
}

Write-Host ""
Write-Host "Updates selected: $($updatesToInstall.Count)"
$updatesToInstall | ForEach-Object {
    $kb = if ($_.KBArticleIDs -and $_.KBArticleIDs.Count -gt 0) { "KB$($_.KBArticleIDs -join ',KB')" } else { "No KB" }
    Write-Host " - $($_.Title) [$kb]"
}

# --- Download ---
$downloader = $session.CreateUpdateDownloader()
$downloader.Updates = $updatesToInstall

Write-Host ""
Write-Host "Downloading updates..."
$downloadResult = $downloader.Download()
Write-Host "Download ResultCode: $($downloadResult.ResultCode) (2=Succeeded, 3=SucceededWithErrors, 4=Failed)"

if ($downloadResult.ResultCode -eq 4) {
    throw "Download failed. Aborting installation."
}

# --- Install ---
$installer = $session.CreateUpdateInstaller()
$installer.Updates = $updatesToInstall

Write-Host ""
Write-Host "Installing updates..."
$installResult = $installer.Install()

Write-Host "Install ResultCode: $($installResult.ResultCode) (2=Succeeded, 3=SucceededWithErrors, 4=Failed)"
Write-Host "Reboot required: $($installResult.RebootRequired)"

Write-Host ""
Write-Host "Per-update results:"
for ($i = 0; $i -lt $updatesToInstall.Count; $i++) {
    $u = $updatesToInstall.Item($i)
    $r = $installResult.GetUpdateResult($i)
    $h = [string]::Format("0x{0:X8}", ($r.HResult -band 0xFFFFFFFF))
    Write-Host " - $($u.Title)"
    Write-Host "   ResultCode: $($r.ResultCode)  HResult: $h"
}

# --- Optional reboot ---
if ($Reboot -and $installResult.RebootRequired) {
    Write-Host ""
    Write-Host "Reboot switch provided and reboot is required. Rebooting now..."
    Restart-Computer -Force
} else {
    if ($installResult.RebootRequired) {
        Write-Host ""
        Write-Host "A reboot is required to complete installation (no reboot performed)."
    }
}
