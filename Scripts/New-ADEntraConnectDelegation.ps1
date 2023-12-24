#Requires -Version 5.1
#Requires -RunAsAdministrator
#Requires -modules ActiveDirectory

<#PSScriptInfo
    .VERSION 1.0
    .GUID c0621a14-da1d-4227-99c9-2ba91ebadde2
    .AUTHOR Michael Waterman
    .COMPANYNAME None
    .COPYRIGHT
    .TAGS Entra Connect, Delegation, Active Directory
#>

<#
    .SYNOPSIS
    Delegates specific security group rights to be used with Entra Connect 

    .DESCRIPTION
    This script can create security groups and delegate them appropriatly 
    to facilitate a delegation model for Entra ID connect. The initial 
    delegation permissions are from a DIRTEAM blogpost, converted to PowerShell:
    https://dirteam.com/sander/2019/11/12/howto-properly-delegate-directory-access-to-azure-ad-connect-service-accounts/

    .EXAMPLE
    New-ADEntraConnectDelegation.ps1
    

    .EXAMPLE
    New-ADEntraConnectDelegation.ps1 -CreateDefaultGroups -OU "OU=Groups,OU=Tier 0,OU=Admin,DC=sandbox,DC=lab"
    Creates default groups in a designated Organizational Unit.

    .EXAMPLE
    New-ADEntraConnectDelegation.ps1 -PasswordHashSync -SecurityGroup "MSEC - Password Hash Sync"
    Delegates the Password Hash Sync funtionality to the given security group.

    .EXAMPLE
    New-ADEntraConnectDelegation.ps1 -EntraConnectFeature 'Group Writeback' -OU OU=test,DC=sandbox,DC=lab -SecurityGroup "MSEC - Group Writeback"
    Delegates 'Group Writeback' for the security group "MSEC - Group Writeback" to the designated Organizational Unit.
    Options for EntraConnectFeature are: "Base Active Directory", "Device Writeback", "Group Writeback", "Hybrid Exchange", "Password Reset",
    "Password Writeback"
   
    .NOTES
    AUTHOR: Michael Waterman
    Blog: https://michaelwaterman.nl
    LASTEDIT: 2023.12.24
#>



[CmdletBinding(DefaultParameterSetName="Default")]
param(
[Parameter(
    Mandatory=$True,
    ParameterSetName = 'Default')]
[Parameter(
    Mandatory=$True, 
    ParameterSetName = 'CreateDefaultGroups')]
[string]$OU,
[Parameter(
    Mandatory=$True,
    ParameterSetName = 'CreateDefaultGroups'
    )]
[switch]$CreateDefaultGroups=$True,
[Parameter(
    Mandatory=$True,
    ParameterSetName = 'PasswordHashSync'
    )]
[switch]$PasswordHashSync,
[Parameter(
    Mandatory=$True, 
    ParameterSetName = 'Default')]
[Parameter(
    Mandatory=$True, 
    ParameterSetName = 'PasswordHashSync')]
[string]$SecurityGroup,
[Parameter(
    Mandatory=$true,
    ParameterSetName = 'Default'
    )]
[ValidateSet(
    "Base Active Directory",
    "Device Writeback",
    "Group Writeback",
    "Hybrid Exchange",
    "Password Reset",
    "Password Writeback"
    )]
[string]$EntraConnectFeature
)


#AD Security Group Function
##############################################################################################
Function Test-ADGroup ($ADSecurityGroup) {
    Try{
        Get-ADGroup -Identity $ADSecurityGroup | Out-Null
       }
    Catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException]{
       throw $_.Exception.Message
    }
}
##############################################################################################


#Check OU existance
##############################################################################################
If ( -not ( Test-Path "AD:${OU}")){
    Write-Error "Organizational Unit Not Found, make sure you type the correct DN"
    Return
}
##############################################################################################


#Create Security Groups
##############################################################################################
if($CreateDefaultGroups){

    # Array with all the groups
    $Groups = @(
        "MSEC - Password Hash Sync",
        "MSEC - Base Active Directory",
        "MSEC - Password Reset",
        "MSEC - Password Writeback",
        "MSEC - Group Writeback",
        "MSEC - Device Writeback",
        "MSEC - Hybrid Exchange"
    )

    #Create the Groups
    ForEach($Group in $Groups){
        if(!(Get-ADGroup -LDAPFilter "(SAMAccountName=$Group)")){
            New-ADGroup -Name $Group -Path $OU -GroupScope Global
        }
    }
}
##############################################################################################


#ACL for Password Hash Sync
##############################################################################################
If($PasswordHashSync){

    Test-ADGroup -ADSecurityGroup $SecurityGroup

    #ACL for Hash Sync
    $SIDPWHashSync = (Get-ADGroup -Identity $SecurityGroup).SID
    $objRootACL = Get-ACL "AD:$((Get-ADDomain).DistinguishedName)"
    $objRootACL.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule `
        ($SIDPWHashSync, `
         "ExtendedRight", `
         "Allow", `
         [guid]'1131f6aa-9c07-11d1-f79f-00c04fc2dcd2', `
         'None', `
         [guid]'00000000-0000-0000-0000-000000000000')))
    $objRootACL.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule `
        ($SIDPWHashSync, `
         "ExtendedRight", `
         "Allow", `
         [guid]'1131f6ad-9c07-11d1-f79f-00c04fc2dcd2', `
         'None', `
         [guid]'00000000-0000-0000-0000-000000000000')))
    Set-acl -AclObject $objRootACL "AD:$((Get-ADDomain).DistinguishedName)"
}
##############################################################################################


#ACL for Base Active Directory
##############################################################################################
If($EntraConnectFeature -eq "Base Active Directory"){

    Test-ADGroup -ADSecurityGroup $SecurityGroup

    $SIDBaseAD = (Get-ADGroup -Identity $SecurityGroup).SID  
    $objACL = Get-ACL "AD:${OU}"
    $objACL.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule `
        ($SIDBaseAD, `
         "WriteProperty", `
         "Allow", `
         [guid]'23773dc2-b63a-11d2-90e1-00c04fd91ab1', `
         'Descendents', `
         [guid]'bf967aba-0de6-11d0-a285-00aa003049e2')))
    $objACL.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule `
        ($SIDBaseAD, `
         "WriteProperty", `
         "Allow", `
         [guid]'5b47d60f-6090-40b2-9f37-2a4de88f3063', `
         'Descendents', `
         [guid]'bf967aba-0de6-11d0-a285-00aa003049e2')))
    $objACL.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule `
        ($SIDBaseAD, `
         "WriteProperty", `
         "Allow", `
         [guid]'5b47d60f-6090-40b2-9f37-2a4de88f3063', `
         'Descendents', `
         [guid]'bf967a9c-0de6-11d0-a285-00aa003049e2')))
    Set-acl -AclObject $objACL "AD:${OU}"
}
##############################################################################################


#ACL For Password Reset
##############################################################################################
If($EntraConnectFeature -eq "Password Reset"){

    Test-ADGroup -ADSecurityGroup $SecurityGroup

    $SIDPWReset = (Get-ADGroup -Identity $SecurityGroup).SID
    $objACL = Get-ACL "AD:${OU}"
    $objACL.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule `
        ($SIDPWReset, `
         "WriteProperty", `
         "Allow", `
         [guid]'28630ebf-41d5-11d1-a9c1-0000f80367c1', `
         'Descendents', `
         [guid]'bf967aba-0de6-11d0-a285-00aa003049e2')))
    $objACL.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule `
        ($SIDPWReset, `
         "WriteProperty", `
         "Allow", `
         [guid]'bf967a0a-0de6-11d0-a285-00aa003049e2', `
         'Descendents', `
         [guid]'bf967aba-0de6-11d0-a285-00aa003049e2')))
    $objACL.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule `
        ($SIDPWReset, `
         "ExtendedRight", `
         "Allow", `
         [guid]'ccc2dc7d-a6ad-4a7a-8846-c04e3cc53501', `
         'Descendents', `
         [guid]'bf967aba-0de6-11d0-a285-00aa003049e2')))
    $objACL.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule `
        ($SIDPWReset, `
         "ExtendedRight", `
         "Allow", `
         [guid]'00299570-246d-11d0-a768-00aa006e0529', `
         'Descendents', `
         [guid]'bf967aba-0de6-11d0-a285-00aa003049e2')))
    $objACL.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule `
        ($SIDPWReset, `
         "ExtendedRight", `
         "Allow", `
         [guid]'ab721a53-1e2f-11d0-9819-00aa0040529b', `
         'Descendents', `
         [guid]'bf967aba-0de6-11d0-a285-00aa003049e2')))
    Set-acl -AclObject $objACL "AD:${OU}"
}
##############################################################################################


#ACL For Password Writeback
##############################################################################################
If($EntraConnectFeature -eq "Password Writeback"){

    Test-ADGroup -ADSecurityGroup $SecurityGroup

    $SIDPWWriteback = (Get-ADGroup -Identity $SecurityGroup).SID
    $objACL = Get-ACL "AD:${OU}"
    $objACL.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule `
        ($SIDPWWriteback, `
         "WriteProperty", `
         "Allow", `
         [guid]'28630ebf-41d5-11d1-a9c1-0000f80367c1', `
         'Descendents', `
         [guid]'bf967aba-0de6-11d0-a285-00aa003049e2')))
    $objACL.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule `
        ($SIDPWWriteback, `
         "WriteProperty", `
         "Allow", `
         [guid]'bf967a0a-0de6-11d0-a285-00aa003049e2', `
         'Descendents', `
         [guid]'bf967aba-0de6-11d0-a285-00aa003049e2')))
    $objACL.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule `
        ($SIDPWWriteback, `
         "ExtendedRight", `
         "Allow", `
         [guid]'00299570-246d-11d0-a768-00aa006e0529', `
         'Descendents', `
         [guid]'bf967aba-0de6-11d0-a285-00aa003049e2')))
    $objACL.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule `
        ($SIDPWWriteback, `
         "ExtendedRight", `
         "Allow", `
         [guid]'ab721a53-1e2f-11d0-9819-00aa0040529b', `
         'Descendents', `
         [guid]'bf967aba-0de6-11d0-a285-00aa003049e2')))
    Set-acl -AclObject $objACL "AD:${OU}"
}
##############################################################################################


#ACL For Device Writeback
##############################################################################################
If($EntraConnectFeature -eq "Device Writeback"){

    Test-ADGroup -ADSecurityGroup $SecurityGroup

    $SIDDevWriteback = (Get-ADGroup -Identity $SecurityGroup).SID
    $objACL = Get-ACL "AD:${OU}"
    $objACL.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule `
        ($SIDDevWriteback, `
         "CreateChild, DeleteChild, ReadProperty, WriteProperty", `
         "Allow", `
         [guid]'00000000-0000-0000-0000-000000000000', `
         'Descendents', `
         [guid]'bf967a86-0de6-11d0-a285-00aa003049e2')))
    Set-acl -AclObject $objACL "AD:${OU}"
}
##############################################################################################


#ACL For Group Writeback
##############################################################################################
If($EntraConnectFeature -eq "Group Writeback"){

    Test-ADGroup -ADSecurityGroup $SecurityGroup

    $SIDGrpWriteback = (Get-ADGroup -Identity $SecurityGroup).SID
    $objACL = Get-ACL "AD:${OU}"
    $objACL.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule `
        ($SIDGrpWriteback, `
         "CreateChild, DeleteChild", `
         "Allow", `
         [guid]'bf967a9c-0de6-11d0-a285-00aa003049e2', `
         'Descendents', `
         [guid]'00000000-0000-0000-0000-000000000000')))
    $objACL.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule `
        ($SIDGrpWriteback, `
         "WriteProperty", `
         "Allow", `
         [guid]'bf9679c0-0de6-11d0-a285-00aa003049e2', `
         'Descendents', `
         [guid]'bf967a9c-0de6-11d0-a285-00aa003049e2')))
    Set-acl -AclObject $objACL "AD:${OU}"
}
##############################################################################################


#ACL For Hybrid Exchange
##############################################################################################
If($EntraConnectFeature -eq "Hybrid Exchange"){

    Test-ADGroup -ADSecurityGroup $SecurityGroup
    
    $SIDHybridExch = (Get-ADGroup -Identity $SecurityGroup).SID
    $objACL = Get-ACL "AD:${OU}"
    $objACL.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule `
        ($SIDHybridExch, `
         "WriteProperty", `
         "Allow", `
         [guid]'6f606079-3a82-4c1b-8efb-dcc8c91d26fe', `
         'Descendents', `
         [guid]'bf967aba-0de6-11d0-a285-00aa003049e2')))
    $objACL.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule `
        ($SIDHybridExch, `
         "WriteProperty", `
         "Allow", `
         [guid]'2432acdb-71c4-4d45-b5aa-9beee36630fe', `
         'Descendents', `
         [guid]'bf967aba-0de6-11d0-a285-00aa003049e2')))
    $objACL.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule `
        ($SIDHybridExch, `
         "WriteProperty", `
         "Allow", `
         [guid]'b1d6bdd0-2a3d-4aba-8c72-40640a999566', `
         'Descendents', `
         [guid]'bf967aba-0de6-11d0-a285-00aa003049e2')))
    $objACL.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule `
        ($SIDHybridExch, `
         "WriteProperty", `
         "Allow", `
         [guid]'66437984-c3c5-498f-b269-987819ef484b', `
         'Descendents', `
         [guid]'bf967aba-0de6-11d0-a285-00aa003049e2')))
    $objACL.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule `
        ($SIDHybridExch, ` 
         "WriteProperty", `
         "Allow", `
         [guid]'b17c00b8-46b9-484e-b053-d5c26835f11e', `
         'Descendents', `
         [guid]'bf967aba-0de6-11d0-a285-00aa003049e2')))
    $objACL.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule `
        ($SIDHybridExch, `
         "WriteProperty", `
         "Allow", `
         [guid]'f0f8ff9a-1191-11d0-a060-00aa006c33ed', `
         'Descendents', `
         [guid]'bf967aba-0de6-11d0-a285-00aa003049e2')))
    $objACL.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule `
        ($SIDHybridExch, `
         "WriteProperty", `
         "Allow", `
         [guid]'bd29bf90-66ad-40e1-887b-10df070419a6', `
         'Descendents', `
         [guid]'bf967aba-0de6-11d0-a285-00aa003049e2')))
    $objACL.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule `
        ($SIDHybridExch, `
         "WriteProperty", `
         "Allow", `
         [guid]'bf967a06-0de6-11d0-a285-00aa003049e2', `
         'Descendents', `
         [guid]'bf967aba-0de6-11d0-a285-00aa003049e2')))
    Set-acl -AclObject $objACL "AD:${OU}"
}
##############################################################################################