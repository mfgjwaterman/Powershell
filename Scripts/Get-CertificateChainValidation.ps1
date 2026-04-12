<#
.SYNOPSIS
Builds the signing certificate chain for a signed file and checks whether the
chain certificates are present in the Current User Root or Intermediate stores.

.DESCRIPTION
This script reads the Authenticode signature from a signed executable or script,
extracts the leaf signing certificate, builds the certificate chain, and compares
the thumbprints of all certificates in that chain against the following Current User stores:

- Trusted Root Certification Authorities (Cert:\CurrentUser\Root)
- Intermediate Certification Authorities (Cert:\CurrentUser\CA)

The script displays the chain certificates in a color-coded table:
- Green: the certificate was found in one of the Current User stores
- Red: the certificate was not found in either Current User store

Optionally, the script can:
- export the leaf signing certificate to a .cer file
- export the chain comparison results to a CSV file

This is useful for troubleshooting AppLocker Publisher rule issues, certificate
trust behavior, and chain-building behavior in Windows.

.PARAMETER FilePath
Specifies the path to the signed file that should be analyzed.

This parameter is required.

.PARAMETER ExportLeafCertificatePath
Specifies the path where the leaf signing certificate should be exported as a .cer file.

This parameter is optional.

.PARAMETER CsvExportPath
Specifies the path where the chain analysis results should be exported as a CSV file.

This parameter is optional.

.EXAMPLE
.\Check-AppLockerChain.ps1 -FilePath "C:\Temp\test.exe"

Builds the certificate chain for test.exe and displays whether each certificate
in the chain exists in the Current User Root or Intermediate stores.

.EXAMPLE
.\Check-AppLockerChain.ps1 -FilePath "C:\Temp\test.exe" -ExportLeafCertificatePath "C:\Temp\leaf.cer"

Builds the certificate chain, displays the results, and exports the leaf signing
certificate to C:\Temp\leaf.cer.

.EXAMPLE
.\Check-AppLockerChain.ps1 -FilePath "C:\Temp\test.exe" -CsvExportPath "C:\Temp\chain-analysis.csv"

Builds the certificate chain, displays the results, and exports the chain analysis
to a CSV file.

.EXAMPLE
.\Check-AppLockerChain.ps1 `
    -FilePath "C:\Temp\test.exe" `
    -ExportLeafCertificatePath "C:\Temp\leaf.cer" `
    -CsvExportPath "C:\Temp\chain-analysis.csv"

Builds the certificate chain, exports the leaf certificate, and writes the chain
analysis results to a CSV file.

.NOTES
Author: Michael Waterman 
Purpose: AppLocker and certificate chain troubleshooting

The script only checks the Current User certificate stores:
- Cert:\CurrentUser\Root
- Cert:\CurrentUser\CA

It does not check Local Machine certificate stores.

The script uses .NET X509Chain to build the chain and disables revocation checking
to avoid network-related validation failures during local testing.
#>

#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,

    [string]$ExportLeafCertificatePath,

    [string]$CsvExportPath
)

function Normalize-Thumbprint {
    param([string]$Thumbprint)

    if ([string]::IsNullOrWhiteSpace($Thumbprint)) {
        return $null
    }

    return ($Thumbprint -replace '\s','').ToUpperInvariant()
}

if (-not (Test-Path -Path $FilePath)) {
    Write-Error "File not found: $FilePath"
    exit 1
}

$signature = Get-AuthenticodeSignature -FilePath $FilePath

if (-not $signature.SignerCertificate) {
    Write-Error "No signing certificate was found on: $FilePath"
    exit 1
}

$leafCertificate = $signature.SignerCertificate

if ($ExportLeafCertificatePath) {
    try {
        Export-Certificate -Cert $leafCertificate -FilePath $ExportLeafCertificatePath -Force | Out-Null
        Write-Host "Leaf certificate exported to: $ExportLeafCertificatePath" -ForegroundColor Cyan
        Write-Host ""
    }
    catch {
        Write-Warning "Failed to export leaf certificate: $($_.Exception.Message)"
    }
}

$currentUserRoot = Get-ChildItem Cert:\CurrentUser\Root -ErrorAction SilentlyContinue
$currentUserCA   = Get-ChildItem Cert:\CurrentUser\CA   -ErrorAction SilentlyContinue

$rootThumbprints = @{}
foreach ($cert in $currentUserRoot) {
    $rootThumbprints[(Normalize-Thumbprint $cert.Thumbprint)] = $true
}

$caThumbprints = @{}
foreach ($cert in $currentUserCA) {
    $caThumbprints[(Normalize-Thumbprint $cert.Thumbprint)] = $true
}

$chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
$chain.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
$chain.ChainPolicy.VerificationFlags = [System.Security.Cryptography.X509Certificates.X509VerificationFlags]::NoFlag

$null = $chain.Build($leafCertificate)

$results = foreach ($element in $chain.ChainElements) {
    $cert = $element.Certificate
    $normalizedThumbprint = Normalize-Thumbprint $cert.Thumbprint

    $inRoot = $rootThumbprints.ContainsKey($normalizedThumbprint)
    $inCA   = $caThumbprints.ContainsKey($normalizedThumbprint)

    $storeLocation =
        if ($inRoot -and $inCA) { "CurrentUser\Root, CurrentUser\CA" }
        elseif ($inRoot)       { "CurrentUser\Root" }
        elseif ($inCA)         { "CurrentUser\CA" }
        else                   { "Not Present" }

    [PSCustomObject]@{
        Subject      = $cert.Subject
        Thumbprint   = $cert.Thumbprint
        StoreMatch   = $storeLocation
        FoundInStore = ($inRoot -or $inCA)
    }
}

# Console output
$subjectWidth    = 70
$thumbprintWidth = 42
$storeWidth      = 32

$header = "{0,-$subjectWidth} {1,-$thumbprintWidth} {2,-$storeWidth}" -f "Subject", "Thumbprint", "Store Match"
Write-Host $header -ForegroundColor White
Write-Host ("-" * ($subjectWidth + $thumbprintWidth + $storeWidth + 2)) -ForegroundColor DarkGray

foreach ($item in $results) {
    $subject = $item.Subject
    if ($subject.Length -gt ($subjectWidth - 1)) {
        $subject = $subject.Substring(0, $subjectWidth - 4) + "..."
    }

    $line = "{0,-$subjectWidth} {1,-$thumbprintWidth} {2,-$storeWidth}" -f `
        $subject, `
        $item.Thumbprint, `
        $item.StoreMatch

    if ($item.FoundInStore) {
        Write-Host $line -ForegroundColor Green
    }
    else {
        Write-Host $line -ForegroundColor Red
    }
}

# CSV export
if ($CsvExportPath) {
    try {
        $results | Export-Csv -Path $CsvExportPath -NoTypeInformation -Encoding UTF8
        Write-Host ""
        Write-Host "CSV exported to: $CsvExportPath" -ForegroundColor Cyan
    }
    catch {
        Write-Warning "Failed to export CSV: $($_.Exception.Message)"
    }
}