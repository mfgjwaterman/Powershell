#Requires -Modules ActiveDirectory
#Requires -Version 5.1

<#PSScriptInfo
    .VERSION 1.0
    .GUID f1128939-3828-42d2-b22e-daf4d81e662c
    .AUTHOR Michael Waterman
    .COMPANYNAME None
    .COPYRIGHT
    .TAGS Active Directory, Users, Contacts
#>

<#
    .SYNOPSIS
    Converts user objects in Active Directory to contacts.

    .DESCRIPTION
    This script can convert user objects in a specific organizational unit to
    Active Directory contacts. per default the user object will be renamed first,
    but the -Cleanup parameter will delete the user object instead.     

    .EXAMPLE
    Convert-UsersToContacts.ps1 -SearchBase "OU=Contacts,OU=Organisation,DC=security,DC=local"
    Get all the users in the given OU, rename them with the "_Renamed " suffix and create new
    Contact objects in the same OU using the attributes of the user that are applicable to a 
    contact object. 
    
    .EXAMPLE
    Convert-UsersToContacts.ps1 -SearchBase "OU=Contacts,OU=Organisation,DC=security,DC=local" -Cleanup:$true
    Get all the users in the given OU, create new Contact objects in the same OU using the attributes of the user 
    that are applicable to a contact object, but deletes the user object instead or renaming it. 
   
    .NOTES
    AUTHOR: Michael Waterman
    Blog: https://michaelwaterman.nl
    LASTEDIT: 2024.05.20
#>


[CmdletBinding(DefaultParameterSetName="Default")]
param(
[Parameter(
    Mandatory=$true
    )]
[string]$SearchBase,
[Parameter(
    Mandatory=$false
    )]
[string]$TempSuffix = "_Renamed ",
[Parameter(
    Mandatory=$false
    )]
[switch]$Cleanup = $false
)

If($Cleanup){
    Write-Host "You selected the option to delete the user objects." -ForegroundColor Red
    Write-Host "This action is not reversible, are you sure you wish to continue?" -ForegroundColor Red
    Write-Host "yes or no? " -ForegroundColor Red
    $answer = read-host
    if (($answer).ToLower() -eq 'yes') { 
        #Continue 
    } else {
        return
    } 
}

# Retreive all user objects from the OU
$users = Get-ADUser -SearchBase $SearchBase -Filter * -Properties * -ResultPageSize 5000

foreach($user in $users){
    # Write to screen

    $username = $user.Name
    Write-Host "processing $username" -ForegroundColor Green

    # Retreive all security groups
    $groups = Get-ADPrincipalGroupMembership -Identity $user.DistinguishedName

    # If cleanup is true, delete instead of rename
    if($cleanup){
        Remove-ADUser -Identity $user.DistinguishedName -Confirm:$false
    } else {
        Get-ADUser -Identity $user.DistinguishedName | Rename-ADObject -NewName ($tempsuffix + $user.Name)
    }

    # Create the contact
    $contact = New-ADObject -Type 'Contact' -Name $user.Name -Path $SearchBase -PassThru

    # Set the Attributes
    if(-not ([string]::IsNullOrEmpty($user.GivenName))){Set-ADObject -Identity $contact.DistinguishedName -Add @{'GivenName'=$user.GivenName}}
    if(-not ([string]::IsNullOrEmpty($user.sn))){Set-ADObject -Identity $contact.DistinguishedName -Add @{'sn'=$user.sn}}
    if(-not ([string]::IsNullOrEmpty($user.DisplayName))){Set-ADObject -Identity $contact.DistinguishedName -Add @{'DisplayName'=$user.DisplayName}}
    if(-not ([string]::IsNullOrEmpty($user.Description))){Set-ADObject -Identity $contact.DistinguishedName -Add @{'Description'=$user.Description}}
    if(-not ([string]::IsNullOrEmpty($user.physicalDeliveryOfficeName))){Set-ADObject -Identity $contact.DistinguishedName -Add @{'physicalDeliveryOfficeName'=$user.physicalDeliveryOfficeName}}
    if(-not ([string]::IsNullOrEmpty($user.TelephoneNumber))){Set-ADObject -Identity $contact.DistinguishedName -Add @{'TelephoneNumber'=$user.TelephoneNumber}}
    if(-not ([string]::IsNullOrEmpty($user.EmailAddress))){Set-ADObject -Identity $contact.DistinguishedName -Add @{'mail'=$user.EmailAddress}}
    if(-not ([string]::IsNullOrEmpty($user.wWWHomePage))){Set-ADObject -Identity $contact.DistinguishedName -Add @{'wWWHomePage'=$user.wWWHomePage}}
    if(-not ([string]::IsNullOrEmpty($user.StreetAddress))){Set-ADObject -Identity $contact.DistinguishedName -Add @{'StreetAddress'=$user.StreetAddress}}
    if(-not ([string]::IsNullOrEmpty($user.postOfficeBox))){Set-ADObject -Identity $contact.DistinguishedName -Add @{'postOfficeBox'=($user.postOfficeBox[0]).ToString()}}
    if(-not ([string]::IsNullOrEmpty($user.l))){Set-ADObject -Identity $contact.DistinguishedName -Add @{'l'=$user.l}}
    if(-not ([string]::IsNullOrEmpty($user.st))){Set-ADObject -Identity $contact.DistinguishedName -Add @{'st'=$user.st}}
    if(-not ([string]::IsNullOrEmpty($user.PostalCode))){Set-ADObject -Identity $contact.DistinguishedName -Add @{'PostalCode'=$user.PostalCode}}
    if(-not ([string]::IsNullOrEmpty($user.countryCode))){Set-ADObject -Identity $contact.DistinguishedName -Add @{'countryCode'=$user.countryCode}}
    if(-not ([string]::IsNullOrEmpty($user.co))){Set-ADObject -Identity $contact.DistinguishedName -Add @{'co'=$user.co}}
    if(-not ([string]::IsNullOrEmpty($user.c))){Set-ADObject -Identity $contact.DistinguishedName -Add @{'c'=$user.c}}
    if(-not ([string]::IsNullOrEmpty($user.HomePhone))){Set-ADObject -Identity $contact.DistinguishedName -Add @{'HomePhone'=$user.HomePhone}}
    if(-not ([string]::IsNullOrEmpty($user.pager))){Set-ADObject -Identity $contact.DistinguishedName -Add @{'pager'=$user.pager}}
    if(-not ([string]::IsNullOrEmpty($user.mobile))){Set-ADObject -Identity $contact.DistinguishedName -Add @{'mobile'=$user.mobile}}
    if(-not ([string]::IsNullOrEmpty($user.facsimileTelephoneNumber))){Set-ADObject -Identity $contact.DistinguishedName -Add @{'facsimileTelephoneNumber'=$user.facsimileTelephoneNumber}}
    if(-not ([string]::IsNullOrEmpty($user.ipPhone))){Set-ADObject -Identity $contact.DistinguishedName -Add @{'ipPhone'=$user.ipPhone}}
    if(-not ([string]::IsNullOrEmpty($user.info))){Set-ADObject -Identity $contact.DistinguishedName -Add @{'info'=$user.info}}
    if(-not ([string]::IsNullOrEmpty($user.Title))){Set-ADObject -Identity $contact.DistinguishedName -Add @{'Title'=$user.Title}}
    if(-not ([string]::IsNullOrEmpty($user.Title))){Set-ADObject -Identity $contact.DistinguishedName -Add @{'Title'=$user.Title}}
    if(-not ([string]::IsNullOrEmpty($user.Department))){Set-ADObject -Identity $contact.DistinguishedName -Add @{'Department'=$user.Department}}
    if(-not ([string]::IsNullOrEmpty($user.Company))){Set-ADObject -Identity $contact.DistinguishedName -Add @{'Company'=$user.Company}}
    if(-not ([string]::IsNullOrEmpty($user.Manager))){Set-ADObject -Identity $contact.DistinguishedName -Add @{'Manager'=$user.Manager}}

    # Set the security groups
    foreach($group in $groups){
        If(!($group.name -eq "Domain Users")){
            Set-ADGroup -Identity $group.Name -Add @{'member'=$contact.DistinguishedName}
        }
    }
           
    # Reset the variables
    $groups = $null
    $contact = $null
    $username = $null
}
