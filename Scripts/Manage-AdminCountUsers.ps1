#Requires -Version 5.1
#Requires -modules ActiveDirectory

<#PSScriptInfo
    .VERSION 1.0
    .GUID 3ed94a97-23a2-4a06-acc0-a3ef34a183dd
    .AUTHOR Michael Waterman
    .COMPANYNAME None
    .COPYRIGHT
    .TAGS Active Directory, AdminSDHolder, adminCount
#>

<#
.SYNOPSIS
    This script identifies users in Active Directory who have the adminCount attribute set to 1 but are not members of groups
    with adminCount set to 1. It optionally removes the adminCount attribute from these users.

.DESCRIPTION
    The script searches for users with the adminCount attribute set, excluding users who are
    members of groups with adminCount set. It provides the option to clear the adminCount attribute for these users. This is 
    useful for managing and cleaning up unwanted permissions in Active Directory environments.

.PARAMETER ListRogueUsers
    A switch parameter. When used, the script lists all the users that are not in protected groups but have the attribute
    adminCount set to 1.
    
.PARAMETER ListAll
    A switch parameter. When used, the script lists all users and groups that have the attribute adminCount set to 1.

.PARAMETER ListProtectedUsers
    A switch parameter. When used, the script lists all users that have the attribute adminCount set to 1.

.PARAMETER ListProtectedGoups
    A switch parameter. When used, the script lists all groups that have the attribute adminCount set to 1.

.PARAMETER ListAdminSDHolderACL
    A switch parameter. When used, the script lists the ACL on the AdminSDHolder object in Active Directory.

.PARAMETER RemoveAdminCount
    A switch parameter. When used, the script removes the adminCount attribute from the identified rogue users. 
    If not used, the script simply lists these users.

.EXAMPLE
    Manage-AdminCountUsers.ps1
    Lists all users with the adminCount attribute set who are not in groups with adminCount set (excludes the krbtgt account).

.EXAMPLE
    Manage-AdminCountUsers.ps1 -RemoveAdminCount
    Removes the adminCount attribute from users who are not in groups with adminCount set.

.EXAMPLE
    Manage-AdminCountUsers.ps1 -ListAll
    Lists all the users and groups that have the AdminCount set to 1.

.NOTES
    AUTHOR: Michael Waterman
    Blog: https://michaelwaterman.nl
    LASTEDIT: 2024.01.20

#>

[CmdletBinding(DefaultParameterSetName="ListRogueUsers")]
param(
[Parameter(
    Mandatory=$False,
    ParameterSetName = 'ListRogueUsers')]
    [switch]$ListRogueUsers,
[Parameter(
    Mandatory=$False,
    ParameterSetName = 'ListAll')]
    [switch]$ListAll,
[Parameter(
    Mandatory=$False,
    ParameterSetName = 'ListProtectedUsers')]
    [switch]$ListProtectedUsers,
[Parameter(
    Mandatory=$False,
    ParameterSetName = 'ListProtectedGoups')]
    [switch]$ListProtectedGoups,
[Parameter(
    Mandatory=$False,
    ParameterSetName = 'ListAdminSDHolderACL')]
    [switch]$ListAdminSDHolderACL,
[Parameter(
    Mandatory=$False,
    ParameterSetName = 'RemoveAdminCount')]
    [switch]$RemoveAdminCount
)


# Import Active Directory module
##############################################################################################
Import-Module ActiveDirectory
##############################################################################################


# Default function
##############################################################################################
if($PSBoundParameters.Count -eq 0){
    $ListRogueUsers = $true
}
##############################################################################################


# Find all groups with adminCount set to 1
##############################################################################################
$groupsAdminCount = Get-ADGroup -Filter {adminCount -eq 1} -Properties adminCount
##############################################################################################


# Find all users with adminCount set to 1, excluding krbtgt
##############################################################################################
$usersAdminCount = Get-ADUser -Filter {(adminCount -eq 1) -and (SamAccountName -ne 'krbtgt')} -Properties adminCount, MemberOf
##############################################################################################


# Check each user to ensure they are not members of the identified groups
##############################################################################################
$usersNotInAdminCountGroups = foreach ($user in $usersAdminCount) {
    $isInGroup = $false
    foreach ($group in $groupsAdminCount) {
        if ($user.MemberOf -contains $group.DistinguishedName) {
            $isInGroup = $true
            break
        }
    }
    if (-not $isInGroup) {
        $user
    }
}
##############################################################################################


# list all the not protected users with AdminCount set to 1
##############################################################################################
If($ListRogueUsers){
    Write-Host "Users with adminCount set but not in protected groups:"
    $usersNotInAdminCountGroups | Select-Object Name, DistinguishedName, adminCount
}
##############################################################################################


#Depending on the RemoveAdminCount switch, remove the adminCount attribute or list the users
##############################################################################################
if ($RemoveAdminCount) {
        $confirmation = Read-Host "Are you sure you want to proceed? (Y/N)"
        if ($confirmation -ne 'Y') {
            Write-Host "Operation cancelled."
            return
        }
        
        foreach ($user in $usersNotInAdminCountGroups) {
        Set-ADUser -Identity $user.DistinguishedName -Clear adminCount
        Write-Host "Removed adminCount for user: $($user.Name)"}
}
##############################################################################################


# List the ACL of the AdminSDHolder object if the switch is used
##############################################################################################
if ($ListAdminSDHolderACL) {
    # Get the current AD domain
    $currentDomain = Get-ADDomain
    $domainDN = $currentDomain.DistinguishedName

    $adminSDHolderDN = "CN=AdminSDHolder,CN=System,$domainDN"
    $adminSDHolderACL = Get-Acl -Path "AD:$adminSDHolderDN"
    Write-Host "ACL for AdminSDHolder object:"
    $adminSDHolderACL.Access | Format-Table IdentityReference, AccessControlType, IsInherited, ActiveDirectoryRights -AutoSize
}
##############################################################################################


# List All object with AdminCount set to 1
##############################################################################################
If ($ListAll){
 
    # Create a new array to hold the new objects
    $newArray = @()

    foreach ($user in $usersAdminCount) {
        $newObject = [PSCustomObject]@{
        Name = $user.Name
        DistinguishedName = $user.DistinguishedName
        ObjectClass = $user.ObjectClass
        }
    $newArray += $newObject
    }

    foreach ($group in $groupsAdminCount) {
        $newObject = [PSCustomObject]@{
        Name = $group.Name
        DistinguishedName = $group.DistinguishedName
        ObjectClass = $group.ObjectClass
        }
    $newArray += $newObject
    }
 
    # Display the new objects
    $newArray | Format-Table Name, DistinguishedName, ObjectClass
}
##############################################################################################


# List All Protected Users
##############################################################################################
if($ListProtectedUsers){
    
    $usersInAdminCountGroups = foreach ($user in $usersAdminCount) {
    $isInGroup = $true
    foreach ($group in $groupsAdminCount) {
        if ($user.MemberOf -contains $group.DistinguishedName) {
            $isInGroup = $false
            break
        }
    }
    if (-not $isInGroup) {
        $user
        }
    }
    $usersInAdminCountGroups | Format-Table Name, DistinguishedName
}


# List all Protected Groups
##############################################################################################
If($ListProtectedGoups){
    $groupsAdminCount | Format-Table Name, DistinguishedName
}
##############################################################################################