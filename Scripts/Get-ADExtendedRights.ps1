#Requires -Version 5.1
#Requires -modules ActiveDirectory

<#PSScriptInfo
    .VERSION 1.0
    .GUID 0a841ae8-5b4c-4b39-8793-0d9f7137ff57
    .AUTHOR Michael Waterman
    .COMPANYNAME None
    .COPYRIGHT
    .TAGS Active Directory, Extended Rights
#>

<#
    .SYNOPSIS
    Lists all the Extended Rights in Active Directory

    .DESCRIPTION
    Filter Extended rights in Active Directory . The script can also display and export all the
    extended rights to a CSV file.   

    .EXAMPLE
    Get-ADExtendedRights.ps1 -Name DS-Replication-Get-Changes-All
    Retreive an extended right from Active Directory by name
    
    .EXAMPLE
    Get-ADExtendedRights.ps1 -rightsGUID 1131f6ad-9c07-11d1-f79f-00c04fc2dcd2
    Retreive an extended right from Active Directory by rightsGUID
    
    .EXAMPLE
    Get-ADExtendedRights.ps1 -All
    List all extended rights in Active Directory. 
        
    .EXAMPLE
    Get-ADExtendedRights.ps1 -All -Path .\All.CSV
    Retreives all the Active Directory Extended Rights and exports them
    to a CSV file
   
    .NOTES
    AUTHOR: Michael Waterman
    Blog: https://michaelwaterman.nl
    LASTEDIT: 2023.12.24
#>


[CmdletBinding(DefaultParameterSetName="Default")]
param(
[Parameter(
    Mandatory=$True, 
    ParameterSetName = 'Name')]
[string]$Name,
[Parameter(
    Mandatory=$True, 
    ParameterSetName = 'rightsGUID')]
[string]$rightsGUID,
[Parameter(
    Mandatory=$True, 
    ParameterSetName = 'Default')]
[switch]$All,
[Parameter(
    Mandatory=$False, 
    ParameterSetName = 'Default')]
[string]$Path
)


#Retreive All Extended Rights
##############################################################################################
$ExtendedRights = Get-ADObject -SearchBase "CN=Extended-Rights,$((Get-ADRootDSE).configurationNamingContext)" `
                               -LDAPFilter '(objectClass=controlAccessRight)' `
                               -Properties name, rightsGUID
##############################################################################################


# Retreive by Name                               
##############################################################################################
If($Name){
    $ExtendedRights | Where-Object Name -Like "*$($Name)*" | `
        Select Name, rightsGUID
}
##############################################################################################


# Retreive by rightsGUID
##############################################################################################
if($rightsGUID){
    $ExtendedRights | Where-Object rightsGUID -Like "*$($rightsGUID)*" | `
        Select Name, rightsGUID
}
##############################################################################################                               
                               

# Select All
##############################################################################################
if($All){
    If($Path){
        $ExtendedRights | Select Name, rightsGUID | Export-Csv -Path $Path -Delimiter ';' -NoTypeInformation
    } Else {
        $ExtendedRights | Select Name, rightsGUID
    }
}
##############################################################################################