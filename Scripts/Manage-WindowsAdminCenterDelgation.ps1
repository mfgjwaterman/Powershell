#Requires -Modules ActiveDirectory

<#PSScriptInfo
    .VERSION 1.0
    .GUID b4b1fb4c-c0ad-4d10-b0d4-3716e7d30263
    .AUTHOR Michael Waterman
    .COMPANYNAME None
    .COPYRIGHT
    .TAGS Active Directory, Windows Admin Center, WAC, Kerberos, Delgation
#>

<#
    .SYNOPSIS
    Sets the Constrained Delegation for Windows Admin Center.

    .DESCRIPTION
    This script can sets the resource-based kerberos constrained delegation for each node
    that is stored in an organisational unit.    

    .EXAMPLE
    Manage-WindowsAdminCenterDelgation.ps1 -Computername "prod-mgmt" -Identity "OU=Servers,DC=corp,DC=Domain,DC=Com"
    Get all the enabled servers in the given OU, sets the constratined delegation for the Windows Admin 
    Center host "prod-mgmt" in the msDS-AllowedToActOnBehalfOfOtherIdentity attribute.

    .EXAMPLE
    Manage-WindowsAdminCenterDelgation.ps1 -Clean -Identity "OU=Servers,DC=corp,DC=Domain,DC=Com" 
    Get all the enabled servers in the given OU, and cleans 
    the msDS-AllowedToActOnBehalfOfOtherIdentity attribute.
    
    .EXAMPLE
    Manage-WindowsAdminCenterDelgation.ps1 -List -Identity "OU=Servers,DC=corp,DC=Domain,DC=Com" 
    Get all the enabled servers in the given OU, and lists 
    the msDS-AllowedToActOnBehalfOfOtherIdentity attribute.

    .NOTES
    AUTHOR: Michael Waterman
    Blog: https://michaelwaterman.nl
    LASTEDIT: 2024.06.11
#>
[CmdletBinding(DefaultParameterSetName="Default")]
    param(
    [Parameter(
        Mandatory=$true,
        ParameterSetName = 'Default'
        )]
    [string]$Computername,
    [Parameter(
        Mandatory=$True
        )]
    [string]$Identity,
    [Parameter(
        Mandatory=$true,
        ParameterSetName = 'Clean'
        )]
    [switch]$Clean=$false,
    [Parameter(
        Mandatory=$true,
        ParameterSetName = 'List'
        )]
    [switch]$List=$false
)

# Get all the servers from the provided OU
$Servers = Get-ADComputer -Filter "OperatingSystem -Like '*Windows Server*' -and Enabled -eq 'True'" `
                          -SearchBase $Identity -Properties "msDS-AllowedToActOnBehalfOfOtherIdentity"

# Only get the computer object of the wac server when setting the attribute.
If($Computername){
    $WindowsAdminCenter = Get-ADComputer -Identity $Computername
}


# Set, list or clean the resource-based kerberos constrained delegation for each node
foreach ($Server in $Servers){
    If($Clean){
        Set-ADComputer -Identity $Server -Clear "msDS-AllowedToActOnBehalfOfOtherIdentity" -Verbose
    } 
    
    If($Computername)
    {
        Set-ADComputer -Identity $Server -PrincipalsAllowedToDelegateToAccount $WindowsAdminCenter -Verbose
    }

    if($List){
        Write-Host -ForegroundColor Green ($server.DNSHostName)
        if($server.'msDS-AllowedToActOnBehalfOfOtherIdentity'.Access){
            $server.'msDS-AllowedToActOnBehalfOfOtherIdentity'.Access
          } else {
            Write-Host -ForegroundColor Red "   No delegation was found for this host."
          }
    }
}