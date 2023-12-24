#Requires -Version 5.1
#Requires -modules ActiveDirectory

<#PSScriptInfo
    .VERSION 1.0
    .GUID 802b4150-c346-4d63-a852-73b87f67b7a5
    .AUTHOR Michael Waterman
    .COMPANYNAME None
    .COPYRIGHT
    .TAGS Active Directory, Schema
#>

<#
    .SYNOPSIS
    Filter the Active Directory Schema.

    .DESCRIPTION
    Filter the Active Directory Schema by Name (Displayes in ADSIEdit), LDAPDisplayName or
    by schemaIDGUID. The script can also display and export the entire Schema based on these
    attributes to a CSV file.   

    .EXAMPLE
    Get-ADSchemaClassAndAttributes.ps1
    

    .EXAMPLE
    Get-ADSchemaClassAndAttributes.ps1 -Name ms-DS-Key-Credential-Link
    Retreives the schema attributes by name

    .EXAMPLE
    Get-ADSchemaClassAndAttributes.ps1 -LDAPDisplayName msDS-KeyCredentialLink
    Retreives the schema attributes by LDAPDisplayName

    .EXAMPLE
    Get-ADSchemaClassAndAttributes.ps1 -schemaIDGUID 5b47d60f-6090-40b2-9f37-2a4de88f3063
    Retreives the schema attributes and matches by provided GUID

    .EXAMPLE
    Get-ADSchemaClassAndAttributes.ps1 -All -Path .\All.CSV
    Retreives all the Active Directory Schema Attributes and Classes and exports them
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
    ParameterSetName = 'LDAPDisplayName')]
[string]$LDAPDisplayName,
[Parameter(
    Mandatory=$True, 
    ParameterSetName = 'schemaIDGUID')]
[guid]$schemaIDGUID,
[Parameter(
    Mandatory=$True, 
    ParameterSetName = 'Default')]
[switch]$All,
[Parameter(
    Mandatory=$False, 
    ParameterSetName = 'Default')]
[string]$Path
)

#Retreive the Schema
##############################################################################################
$SchemaObjects = Get-ADObject -LDAPFilter "(objectclass=*)" `
                              -SearchBase $((Get-ADRootDSE).schemaNamingContext) `
                              -Properties Name, LDAPDisplayName, schemaIDGUID | `
                              Where-Object { ($_.ObjectClass -EQ "attributeSchema") -or ($_.ObjectClass -EQ "classSchema")}
##############################################################################################


#Select by Name
##############################################################################################
If($Name){
    $SchemaObjects | `
    Where Name -Like "*$($Name)*" | `
    Select Name, LDAPDisplayName,@{e={[System.Guid]$_.schemaIDGUID};l="schemaIDGUID"}
}
##############################################################################################


#Select by LDAPDisplayName
##############################################################################################
If($LDAPDisplayName){
    $SchemaObjects | `
    Where LDAPDisplayName -Like "*$($LDAPDisplayName)*" | `
    Select Name, LDAPDisplayName,@{e={[System.Guid]$_.schemaIDGUID};l="schemaIDGUID"}
}
##############################################################################################


# Select by scemaIDGUID
##############################################################################################
if($schemaIDGUID){
    ForEach ($Obj in $SchemaObjects ){
 
    If( $($Obj.schemaIDGuid -as [guid]).Guid -eq $schemaIDGUID.Guid ){
        $Obj | select Name, LDAPDisplayName, @{e={[System.Guid]$_.schemaIDGUID};l="schemaIDGUID"}
    }
  }
}
##############################################################################################


# Select All
##############################################################################################
if($All){
    If($Path){
        $SchemaObjects | Select Name, LDAPDisplayName,@{e={[System.Guid]$_.schemaIDGUID};l="schemaIDGUID"} | Export-Csv -Path $Path -Delimiter ';' -NoTypeInformation
    } Else {
        $SchemaObjects | Select Name, LDAPDisplayName,@{e={[System.Guid]$_.schemaIDGUID};l="schemaIDGUID"}
    }
}
##############################################################################################
