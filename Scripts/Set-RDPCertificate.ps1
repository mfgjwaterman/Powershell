<#
.Synopsis
   Set the server certificate for the RDP connection.

.DESCRIPTION
   This script sets a custom certificate for the RDP session on Windows Server 2012 R2.

   Script version: 1.1
   Script Author: Michael Waterman

.Parameter Hash
   provide a valid hash for the certificate you want to use. Please note that the certificate needs o.i.d: 1.3.6.1.5.5.7.3.1 and 1.3.6.1.5.5.7.3.2.

.Parameter Delete
   Deletes the current RDP Certificate. requires the Hash parameter.

.Parameter Terminalname
   Provides a custom name for the RDP connection name. Default is "RDP-TCP".

.Parameter listCerts
   Lists all certificates in the personal store of the local computer.

.Parameter ListCurrent
   Displays the certificate currently assigned to the RDP-TCP connection.

.EXAMPLE
    Set-RDPCertificate -hash C6761A68B39DCB056C8268CFE6FB640DB5EF7715

    Updates the RDP Certificate to the provided hash value.

.EXAMPLE
    Set-RDPCertificate -hash C6761A68B39DCB056C8268CFE6FB640DB5EF7715 -delete

    Updates the RDP Certificate to the provided hash value and deletes the current one if the hash value is different to the one provided.

.EXAMPLE
    Set-RDPCertificate -hash C6761A68B39DCB056C8268CFE6FB640DB5EF7715 -Terminalname MY-RDP

    Updates the RDP Certificate to the provided hash value on the MY-RDP connection instead of the default RDP-TCP.

.EXAMPLE
    Set-RDPCertificate -ListCerts
    
    Lists the available certificates from the local computer store.        

.EXAMPLE
    Set-RDPCertificate -ListCurrent

    List the currently used certificate for the RDP-TCP connection.

#>



# Parameter input
##############################################################################################
[CmdletBinding(DefaultParameterSetName="hash")]
param(

[Parameter(ParameterSetName="hash", Mandatory=$true)]
[string]$Hash,
[Parameter(ParameterSetName="hash", Mandatory=$false)]
[switch]$Delete,
[Parameter(ParameterSetName="hash", Mandatory=$false)]
[string]$Terminalname = "RDP-TCP",
[Parameter(ParameterSetName="certificates", Mandatory=$true)]
[switch]$listCerts,
[Parameter(ParameterSetName="current", Mandatory=$true)]
[switch]$ListCurrent
)
##############################################################################################


# Check the minimal supported Windows version
##############################################################################################
$OSVersion = (Get-CimInstance -Class Win32_OperatingSystem).Version
$OSVersionRequired = '6.3.9600'

if ([version]$OSVersion -lt [version]$OSVersionRequired )
{
   write-host $Caption "Is not supported" 
    return
}  
##############################################################################################


# Set the script variables 
##############################################################################################
$certificates = Get-ChildItem -path cert:\LocalMachine\My\
$CertificateCheck = $false
$ErrorActionPreference = "Stop"
$Query = "select * from Win32_TSGeneralSetting where Terminalname LIKE ""$Terminalname"""
$CurrentCert = Get-CimInstance -Namespace root/cimv2/terminalservices -Query $Query
##############################################################################################


# List all certificates in the local computer store
##############################################################################################
if ($listCerts) {
    Get-ChildItem -path cert:\LocalMachine\My\ | 
            Format-table Thumbprint, @{ 
                Name= 'Issued to'; Expression= { 
                    $_.getnameinfo('SimpleName', $false) 
                    } 
                }, Friendlyname 
                return}
##############################################################################################


# Display the current certificate
##############################################################################################
if($ListCurrent)
{
    Get-CimInstance -Namespace root/cimv2/terminalservices -ClassName Win32_TSGeneralSetting | 
        Select CertificateName, TerminalName, SSLCertificateSHA1Hash | 
            Format-List
    return
}
##############################################################################################


# Check the lenght of the hash
##############################################################################################
if ($hash.Length -lt 40) 
{
    Write-Host "Provided hash value is not at the expected lenght" -ForegroundColor Red
        return
}
##############################################################################################


# Main
##############################################################################################
foreach ($certificate in $certificates)
{
    if ($certificate.Thumbprint -contains $hash)
    {
        $CertificateCheck = $true

        if ($certificate.EnhancedKeyUsageList.Objectid -contains "1.3.6.1.5.5.7.3.1" -and $certificate.EnhancedKeyUsageList.Objectid -contains "1.3.6.1.5.5.7.3.2" )
        {
            if ($Delete)
            {
                if($hash -ne $CurrentCert.SSLCertificateSHA1Hash)
                {
                    Get-ChildItem Cert:\LocalMachine\My\$($CurrentCert.SSLCertificateSHA1Hash) | 
                        Remove-Item
                }
            }

            Set-CimInstance -InputObject $currentcert -Property @{SSLCertificateSHA1Hash="$hash"}
            
            if($?) {
                Write-Host "Certificate successfully set"
                    return
                    } 
                   
        } else {
            Write-Host "The certificate does not contain the required key usage client & server authentication" -ForegroundColor Yellow 
                return
                }
                
    }
}


# No certificate found
##############################################################################################
if (!$CertificateCheck) 
{
    Write-Host "Provided certificate hash was not found in local computer certificate store" -ForegroundColor Red 
        return
}
##############################################################################################