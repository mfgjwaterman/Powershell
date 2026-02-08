function Test-RDPCertificateBinding {
<#
.SYNOPSIS
Validates whether the certificate bound to Remote Desktop (RDP) matches a certificate containing a specific EKU OID, locally or on a remote system.

.DESCRIPTION
This function validates that the certificate configured for the RDP-tcp listener
is the same certificate that contains a required Enhanced Key Usage (EKU) OID.

It supports both local execution and remote validation via:
- Remote CIM queries for the RDP configuration
- Remote certificate store inspection using Invoke-Command

.PARAMETER ComputerName
Optional remote computer to validate. If omitted, the local machine is used.

.PARAMETER EkuOid
The EKU OID that must be present on the expected certificate.
Default: 1.3.6.1.4.1.311.54.1.2 (Remote Desktop Authentication).

.PARAMETER StorePath
Certificate store path to search. Default: Cert:\LocalMachine\My.

.PARAMETER ListenerName
RDP listener name. Default: RDP-tcp.

.PARAMETER Quiet
Suppresses Write-Host output and returns only an object.

.EXAMPLE
Test-RDPCertificateBinding

Runs validation on the local computer.

.EXAMPLE
Test-RDPCertificateBinding -ComputerName SERVER01

Validates RDP certificate binding on SERVER01.

.EXAMPLE
Test-RDPCertificateBinding -ComputerName SERVER01 -Quiet
#>
    [CmdletBinding()]
    param(
        [string]$ComputerName,

        [string]$EkuOid = "1.3.6.1.4.1.311.54.1.2",

        [string]$StorePath = "Cert:\LocalMachine\My",

        [string]$ListenerName = "RDP-tcp",

        [switch]$Quiet
    )

    function Get-RemoteEkuCerts {
        param($TargetComputer)

        Invoke-Command -ComputerName $TargetComputer -ScriptBlock {
            param($StorePath, $EkuOid)

            Get-ChildItem $StorePath |
            Where-Object {
                $_.EnhancedKeyUsageList -and
                ($_.EnhancedKeyUsageList.ObjectId -contains $EkuOid)
            } |
            Select-Object Thumbprint

        } -ArgumentList $StorePath, $EkuOid
    }

    function Get-LocalEkuCerts {
        Get-ChildItem $StorePath |
        Where-Object {
            $_.EnhancedKeyUsageList -and
            ($_.EnhancedKeyUsageList.ObjectId -contains $EkuOid)
        } |
        Select-Object Thumbprint
    }

    # --- Retrieve EKU certificates ---
    if ($ComputerName) {
        try {
            $ekuCerts = Get-RemoteEkuCerts -TargetComputer $ComputerName
        }
        catch {
            throw "Failed to retrieve certificates from $ComputerName : $_"
        }
    }
    else {
        $ekuCerts = Get-LocalEkuCerts
    }

    $matchingCount = @($ekuCerts).Count

    if ($matchingCount -eq 0) {
        $msg = "No certificate was found containing EKU OID '$EkuOid'."

        if (-not $Quiet) {
            Write-Host $msg -ForegroundColor Yellow
        }

        return [pscustomobject]@{
            ComputerName              = $ComputerName
            ExpectedThumbprint        = $null
            RdpConfiguredThumbprint   = $null
            Match                     = $false
            Status                    = "NotFound"
            Message                   = $msg
            MatchingCertificatesCount = 0
        }
    }

    if ($matchingCount -ne 1 -and -not $Quiet) {
        Write-Host "Warning: $matchingCount certificates found with EKU OID '$EkuOid'. Using the first match." -ForegroundColor Yellow
    }

    $expectedThumbprint = $ekuCerts | Select-Object -First 1 -ExpandProperty Thumbprint

    # --- Retrieve RDP configured thumbprint ---
    try {
        $rdpConfiguredThumbprint = (Get-CimInstance `
            -ComputerName $ComputerName `
            -Class "Win32_TSGeneralSetting" `
            -Namespace root\cimv2\terminalservices `
            -Filter "TerminalName='$ListenerName'").SSLCertificateSHA1Hash
    }
    catch {
        $rdpConfiguredThumbprint = $null
    }

    if (-not $rdpConfiguredThumbprint) {
        $msg = "Could not retrieve RDP configured thumbprint on $($ComputerName + " local system" )."

        if (-not $Quiet) {
            Write-Host $msg -ForegroundColor Yellow
        }

        return [pscustomobject]@{
            ComputerName              = $ComputerName
            ExpectedThumbprint        = $expectedThumbprint
            RdpConfiguredThumbprint   = $null
            Match                     = $false
            Status                    = "RdpThumbprintUnavailable"
            Message                   = $msg
            MatchingCertificatesCount = $matchingCount
        }
    }

    # --- Normalize and compare ---
    $expectedNorm = ($expectedThumbprint -replace '\s','').ToUpperInvariant()
    $rdpNorm      = ($rdpConfiguredThumbprint -replace '\s','').ToUpperInvariant()

    $match = ($expectedNorm -eq $rdpNorm)

    $status  = if ($match) { "Success" } else { "Mismatch" }
    $message = if ($match) {
        "VALIDATION SUCCESS: RDP on $($ComputerName + ' local system') uses the certificate with the expected EKU."
    } else {
        "VALIDATION FAILED: RDP on $($ComputerName + ' local system') is using a different certificate."
    }

    if (-not $Quiet) {
        Write-Host "Computer                     : $($ComputerName + 'Localhost')"
        Write-Host "Thumbprint from store        : $expectedThumbprint"
        Write-Host "Thumbprint configured for RDP: $rdpConfiguredThumbprint"

        if ($match) {
            Write-Host $message -ForegroundColor Green
        } else {
            Write-Host $message -ForegroundColor Red
        }
    }

    return [pscustomobject]@{
        ComputerName              = $ComputerName
        ExpectedThumbprint        = $expectedThumbprint
        RdpConfiguredThumbprint   = $rdpConfiguredThumbprint
        Match                     = $match
        Status                    = $status
        Message                   = $message
        MatchingCertificatesCount = $matchingCount
    }
}
