#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Retrieves issued certificates from a Microsoft AD CS Certification Authority database.

.DESCRIPTION
    Queries the local AD CS CA database using certutil.exe.
    By default, only issued certificates that are currently valid are returned.

    Supports filtering by certificate template, requester, common name, expiration period,
    summary output per template, raw certutil output, and CSV export.

.PARAMETER Summary
    Shows a summary grouped by certificate template.

.PARAMETER Template
    Filters certificates by certificate template name or template OID.
    Filtering is handled in PowerShell after parsing because AD CS may return template values as:
    "OID" Friendly Template Name

.PARAMETER Requester
    Filters certificates by requester name.

.PARAMETER CommonName
    Filters certificates by issued common name.

.PARAMETER ExpiringInDays
    Shows certificates that expire within the specified number of days.

.PARAMETER IncludeExpired
    Includes expired issued certificates.

.PARAMETER ExportCsv
    Exports the results to a CSV file.

.PARAMETER Raw
    Returns the raw certutil output.

.EXAMPLE
    .\Get-CACertificateInventory.ps1

.EXAMPLE
    .\Get-CACertificateInventory.ps1 -Summary

.EXAMPLE
    .\Get-CACertificateInventory.ps1 -Template "Web Server"

.EXAMPLE
    .\Get-CACertificateInventory.ps1 -Template Web

.EXAMPLE
    .\Get-CACertificateInventory.ps1 -Requester "CORP\LAB-WEB-03$"

.EXAMPLE .\Get-CACertificateInventory.ps1 -CommonName "lab-web-03.corp.michaelwaterman.nl"
 
.EXAMPLE .\Get-CACertificateInventory.ps1 -CommonName "*lab-web*" 
 
.EXAMPLE .\Get-CACertificateInventory.ps1 -CommonName "*.corp.michaelwaterman.nl" 

.EXAMPLE .\Get-CACertificateInventory.ps1 -ExpiringInDays 30

.EXAMPLE .\Get-CACertificateInventory.ps1 -ExportCsv C:\Temp\ActiveCertificates.csv

.NOTES
    Author: Michael Waterman
    Blog: https://michaelwaterman.nl
    Requirements:
    - Run as Administrator
    - Run on a Microsoft AD CS Certification Authority server
    - certutil.exe must be available
#>

[CmdletBinding()]
param(
    [switch]$Summary,

    [string]$Template,

    [string]$Requester,

    [string]$CommonName,

    [int]$ExpiringInDays,

    [switch]$IncludeExpired,

    [string]$ExportCsv,

    [switch]$Raw
)

$Restrictions = @(
    "Disposition=20"
)

if (-not $IncludeExpired) {
    $Restrictions += "NotAfter >= now"
}

if ($Requester) {
    $Restrictions += "RequesterName=$Requester"
}

$RestrictionString = $Restrictions -join ","

$OutputColumns = @(
    "RequestID",
    "RequesterName",
    "CommonName",
    "CertificateTemplate",
    "NotBefore",
    "NotAfter",
    "SerialNumber"
) -join ","

$Output = certutil -view -restrict $RestrictionString -out $OutputColumns

if ($Raw) {
    return $Output
}

$CurrentCert = [ordered]@{}
$Results = @()

foreach ($Line in $Output) {

    if ($Line -match "^Row \d+:") {
        if ($CurrentCert.Count -gt 0) {
            $Results += [PSCustomObject]$CurrentCert
            $CurrentCert = [ordered]@{}
        }
    }

    elseif ($Line -match "^\s*Issued Request ID:\s*(.+)$") {
        $CurrentCert["RequestID"] = $Matches[1].Trim()
    }

    elseif ($Line -match "^\s*Requester Name:\s*(.+)$") {
        $CurrentCert["RequesterName"] = $Matches[1].Trim('"')
    }

    elseif ($Line -match "^\s*Issued Common Name:\s*(.+)$") {
        $CurrentCert["CommonName"] = $Matches[1].Trim('"')
    }

    elseif ($Line -match "^\s*Certificate Template:\s*(.+)$") {
        $TemplateRaw = $Matches[1].Trim()

        if ($TemplateRaw -match '^"([^"]+)"\s+(.+)$') {
            $CurrentCert["CertificateTemplateOid"] = $Matches[1].Trim()
            $CurrentCert["CertificateTemplate"] = $Matches[2].Trim()
        }
        else {
            $CurrentCert["CertificateTemplateOid"] = $null
            $CurrentCert["CertificateTemplate"] = $TemplateRaw.Trim('"')
        }
    }

    elseif ($Line -match "^\s*Certificate Effective Date:\s*(.+)$") {
        $CurrentCert["NotBefore"] = [datetime]$Matches[1].Trim()
    }

    elseif ($Line -match "^\s*Certificate Expiration Date:\s*(.+)$") {
        $CurrentCert["NotAfter"] = [datetime]$Matches[1].Trim()
    }

    elseif ($Line -match "^\s*Serial Number:\s*(.+)$") {
        $CurrentCert["SerialNumber"] = $Matches[1].Trim('"')
    }
}

if ($CurrentCert.Count -gt 0) {
    $Results += [PSCustomObject]$CurrentCert
}

if ($Template) {
    $Results = $Results | Where-Object {
        $_.CertificateTemplate -like "*$Template*" -or
        $_.CertificateTemplateOid -like "*$Template*"
    }
}

if ($CommonName) {
    $Results = $Results | Where-Object {
        $_.CommonName -like "*$CommonName*"
    }
}

if ($PSBoundParameters.ContainsKey("ExpiringInDays")) {
    $Results = $Results | Where-Object {
        $_.NotAfter -le (Get-Date).AddDays($ExpiringInDays)
    }
}

if ($Summary) {
    $Results = $Results |
        Group-Object CertificateTemplate |
        Sort-Object Count -Descending |
        Select-Object @{
            Name       = "CertificateTemplate"
            Expression = { $_.Name }
        }, @{
            Name       = "Certificates"
            Expression = { $_.Count }
        }
}

if ($ExportCsv) {
    $ExportDirectory = Split-Path -Path $ExportCsv -Parent

    if ($ExportDirectory -and -not (Test-Path -Path $ExportDirectory)) {
        New-Item -Path $ExportDirectory -ItemType Directory -Force | Out-Null
    }

    $Results | Export-Csv -Path $ExportCsv -NoTypeInformation -Encoding UTF8
    Write-Host "CSV exported to $ExportCsv" -ForegroundColor Green
}

return $Results
