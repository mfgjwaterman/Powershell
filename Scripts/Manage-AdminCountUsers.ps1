#Requires -Version 5.1
#Requires -modules ActiveDirectory

<#PSScriptInfo
    .VERSION 1.8
    .GUID 3ed94a97-23a2-4a06-acc0-a3ef34a183dd
    .AUTHOR Michael Waterman
    .COMPANYNAME None
    .COPYRIGHT
    .TAGS Active Directory, AdminSDHolder, AdminCount, Exchange
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

.PARAMETER AdminSDHolderSecurity
    A switch parameter. When used, the script will compare the sddl against a known good sddl. When the
    IncludeExchange parameter is added, a known sddl list is compared to the actual sddl. Delta entries are
    displayed when found.

.PARAMETER IncludeExchange
    A switch parameter. When used, the script will include a default SDDL list of Micosoft Exchange installation
    and compare it to the current state in Active Directory

.PARAMETER TranslateSDDL
    A switch parameter. When used, the script will translate any remaining anomalies from the security descriptor
    definition language (SDDL) to human readable text. 

.EXAMPLE
    Manage-AdminCountUsers.ps1
    Lists all users with the adminCount attribute set who are not in groups with adminCount set (excludes the krbtgt account).

.EXAMPLE
    Manage-AdminCountUsers.ps1 -RemoveAdminCount
    Removes the adminCount attribute from users who are not in groups with adminCount set.

.EXAMPLE
    Manage-AdminCountUsers.ps1 -ListAll
    Lists all the users and groups that have the AdminCount set to 1.

.EXAMPLE
    Manage-AdminCountUsers.ps1 -AdminSDHolderSecurity
    Detects anomalies on the AdminSDHolder

.EXAMPLE
    Manage-AdminCountUsers.ps1 -AdminSDHolderSecurity -IncludeExchange -TranslateSDDL
    Detects anomalies on the AdminSDHolder, including default Exchange Server security Access COntrol Entries.
    If any anomalies are detected they are displayed in human readable text.

.NOTES
    AUTHOR: Michael Waterman
    Blog: https://michaelwaterman.nl
    LASTEDIT: 2024.01.25

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
    [switch]$RemoveAdminCount,
[Parameter(
    Mandatory=$False,
    ParameterSetName = 'AdminSDHolderSecurity')]
    [switch]$AdminSDHolderSecurity,
[Parameter(
    Mandatory=$False,
    ParameterSetName = 'AdminSDHolderSecurity')]
    [switch]$IncludeExchange,
[Parameter(
    Mandatory=$False,
    ParameterSetName = 'AdminSDHolderSecurity')]
    [switch]$TranslateSDDL
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


# Security Check On the AdminSDHolder container
##############################################################################################
If($AdminSDHolderSecurity){

    [System.Collections.ArrayList]$ntsecuritydescriptor = (Get-ADObject -Filter 'ObjectClass -eq "container"' `
                                         -SearchBase "CN=AdminSDHolder,CN=System,$((Get-ADDomain).DistinguishedName)" `
                                         -Properties ntsecuritydescriptor).ntsecuritydescriptor.sddl.Split('(') -replace '\)'

    
    $domainsid = ((Get-ADDomain).DomainSid.Value).split('-',5)[4]


    If(-not $IncludeExchange){
    $defaultsddl = "O:DAG:DAD:PAI", `
                   "A;;LCRPLORC;;;AU", `
                   "A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;SY",
                   "A;;CCDCLCSWRPWPLOCRSDRCWDWO;;;BA",
                   "A;;CCDCLCSWRPWPLOCRRCWDWO;;;DA",
                   "A;;CCDCLCSWRPWPLOCRRCWDWO;;;S-1-5-21-$($DomainSid)-519",
                   "OA;;CR;ab721a53-1e2f-11d0-9819-00aa0040529b;;WD",
                   "OA;CI;RPWPCR;91e647de-d96f-4b70-9557-d63ff4f3ccd8;;PS",
                   "OA;;CR;ab721a53-1e2f-11d0-9819-00aa0040529b;;PS",
                   "OA;;RP;037088f8-0ae1-11d2-b422-00a0c968f939;4828cc14-1437-45bc-9b07-ad6f015e5f28;RU",
                   "OA;;RP;037088f8-0ae1-11d2-b422-00a0c968f939;bf967aba-0de6-11d0-a285-00aa003049e2;RU",
                   "OA;;RP;4c164200-20c0-11d0-a768-00aa006e0529;bf967aba-0de6-11d0-a285-00aa003049e2;RU",
                   "OA;;RP;59ba2f42-79a2-11d0-9020-00c04fc2d3cf;4828cc14-1437-45bc-9b07-ad6f015e5f28;RU",
                   "OA;;RP;bc0ac240-79a9-11d0-9020-00c04fc2d4cf;bf967aba-0de6-11d0-a285-00aa003049e2;RU",
                   "OA;;RP;bc0ac240-79a9-11d0-9020-00c04fc2d4cf;4828cc14-1437-45bc-9b07-ad6f015e5f28;RU",
                   "OA;;LCRPLORC;;4828cc14-1437-45bc-9b07-ad6f015e5f28;RU",
                   "OA;;LCRPLORC;;bf967aba-0de6-11d0-a285-00aa003049e2;RU",
                   "OA;;RP;59ba2f42-79a2-11d0-9020-00c04fc2d3cf;bf967aba-0de6-11d0-a285-00aa003049e2;RU",
                   "OA;;RP;5f202010-79a5-11d0-9020-00c04fc2d4cf;4828cc14-1437-45bc-9b07-ad6f015e5f28;RU",
                   "OA;;RP;4c164200-20c0-11d0-a768-00aa006e0529;4828cc14-1437-45bc-9b07-ad6f015e5f28;RU",
                   "OA;;RP;46a9b11d-60ae-405a-b7e8-ff8a58d456d2;;S-1-5-32-560",
                   "OA;;RPWP;6db69a1c-9422-11d1-aebd-0000f80367c1;;S-1-5-32-561",
                   "OA;;RPWP;5805bc62-bdc9-4428-a5e2-856a0f4c185e;;S-1-5-32-561",
                   "OA;;RPWP;bf967a7f-0de6-11d0-a285-00aa003049e2;;CA"
                   
    [string]$sddlarray = $defaultsddl[0]                   
    }

    If($IncludeExchange){

    try {$organizationmanagement = (Get-ADGroup -Identity "organization management" -ErrorAction SilentlyContinue).sid.Value} catch {}
    try {$delegatedsetupGet = (Get-ADGroup -Identity "delegated setup" -ErrorAction SilentlyContinue).sid.Value} catch {}
    try {$exchangeservers = (Get-ADGroup -Identity "exchange servers" -ErrorAction SilentlyContinue).sid.Value} catch {}
    try {$exchangetrustedsubsystem = (Get-ADGroup -Identity "exchange trusted subsystem" -ErrorAction SilentlyContinue).sid.Value} catch {}

    $exchangesddl = "O:DAG:DAD:PAI", `
                    "OD;CI;WP;bf967a7f-0de6-11d0-a285-00aa003049e2;bf967a86-0de6-11d0-a285-00aa003049e2;$($exchangeservers)", `
                    "OD;CI;WP;00fbf30c-91fe-11d1-aebc-0000f80367c1;bf967a86-0de6-11d0-a285-00aa003049e2;$($exchangetrustedsubsystem)", `
                    "OD;CI;WP;bf967a7f-0de6-11d0-a285-00aa003049e2;;$($exchangetrustedsubsystem)", `
                    "OD;CI;WP;f3a64788-5306-11d1-a9c5-0000f80367c1;;$($exchangetrustedsubsystem)", `
                    "A;;LCRPLORC;;;AU", `
                    "A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;SY", `
                    "A;;CCDCLCSWRPWPLOCRSDRCWDWO;;;BA", `
                    "A;;CCDCLCSWRPWPLOCRRCWDWO;;;DA", `
                    "A;;CCDCLCSWRPWPLOCRRCWDWO;;;S-1-5-21-$($DomainSid)-519", `
                    "A;CI;LCRPLORC;;;$($organizationmanagement)", `
                    "A;CI;LCRPLORC;;;$($exchangetrustedsubsystem)", `
                    "OA;;CR;ab721a53-1e2f-11d0-9819-00aa0040529b;;WD", `
                    "OA;CI;RPWPCR;91e647de-d96f-4b70-9557-d63ff4f3ccd8;;PS", `
                    "OA;;CR;ab721a53-1e2f-11d0-9819-00aa0040529b;;PS", `
                    "OA;CI;RP;1f298a89-de98-47b8-b5cd-572ad53d267e;;AU", `
                    "OA;CI;RP;b1b3a417-ec55-4191-b327-b72e33e38af2;;NS", `
                    "OA;;RP;037088f8-0ae1-11d2-b422-00a0c968f939;bf967aba-0de6-11d0-a285-00aa003049e2;RU", `
                    "OA;;RP;037088f8-0ae1-11d2-b422-00a0c968f939;4828cc14-1437-45bc-9b07-ad6f015e5f28;RU", `
                    "OA;;RP;59ba2f42-79a2-11d0-9020-00c04fc2d3cf;bf967aba-0de6-11d0-a285-00aa003049e2;RU", `
                    "OA;;RP;59ba2f42-79a2-11d0-9020-00c04fc2d3cf;4828cc14-1437-45bc-9b07-ad6f015e5f28;RU", `
                    "OA;;RP;bc0ac240-79a9-11d0-9020-00c04fc2d4cf;bf967aba-0de6-11d0-a285-00aa003049e2;RU", `
                    "OA;;RP;bc0ac240-79a9-11d0-9020-00c04fc2d4cf;4828cc14-1437-45bc-9b07-ad6f015e5f28;RU", `
                    "OA;;RP;5f202010-79a5-11d0-9020-00c04fc2d4cf;4828cc14-1437-45bc-9b07-ad6f015e5f28;RU", `
                    "OA;;RP;4c164200-20c0-11d0-a768-00aa006e0529;bf967aba-0de6-11d0-a285-00aa003049e2;RU", `
                    "OA;;RP;4c164200-20c0-11d0-a768-00aa006e0529;4828cc14-1437-45bc-9b07-ad6f015e5f28;RU", `
                    "OA;;LCRPLORC;;bf967aba-0de6-11d0-a285-00aa003049e2;RU", `
                    "OA;;LCRPLORC;;4828cc14-1437-45bc-9b07-ad6f015e5f28;RU", `
                    "OA;;RP;46a9b11d-60ae-405a-b7e8-ff8a58d456d2;;S-1-5-32-560", `
                    "OA;;RPWP;5805bc62-bdc9-4428-a5e2-856a0f4c185e;;S-1-5-32-561", `
                    "OA;;RPWP;6db69a1c-9422-11d1-aebd-0000f80367c1;;S-1-5-32-561", `
                    "OA;;RPWP;bf967a7f-0de6-11d0-a285-00aa003049e2;;CA", `
                    "OA;CI;WP;bf96791a-0de6-11d0-a285-00aa003049e2;;$($organizationmanagement)", `
                    "OA;CI;WP;bf967a06-0de6-11d0-a285-00aa003049e2;;$($organizationmanagement)", `
                    "OA;CI;WP;a673a21e-e65e-43a6-ac59-7e4bfdeb9fb8;;$($organizationmanagement)", `
                    "OA;CI;WP;3e74f60e-3e73-11d1-a9c0-0000f80367c1;;$($organizationmanagement)", `
                    "OA;CI;WP;b1b3a417-ec55-4191-b327-b72e33e38af2;;$($organizationmanagement)", `
                    "OA;CI;CCDCLCSWRPWPDTLOCRSDRCWDWO;018849b0-a981-11d2-a9ff-00c04f8eedd8;;$($organizationmanagement)", `
                    "OA;CI;WP;28630ebc-41d5-11d1-a9c1-0000f80367c1;;$($organizationmanagement)", `
                    "OA;CI;WP;bf967953-0de6-11d0-a285-00aa003049e2;;$($organizationmanagement)", `
                    "OA;CI;WP;5fd424a1-1262-11d0-a060-00aa006c33ed;;$($organizationmanagement)", `
                    "OA;CI;WP;f0f8ff9a-1191-11d0-a060-00aa006c33ed;;$($organizationmanagement)", `
                    "OA;CI;WP;1f298a89-de98-47b8-b5cd-572ad53d267e;;$($organizationmanagement)", `
                    "OA;CI;WP;bf967954-0de6-11d0-a285-00aa003049e2;;$($organizationmanagement)", `
                    "OA;CI;WP;a8df7489-c5ea-11d1-bbcb-0080c76670c0;;$($organizationmanagement)", `
                    "OA;CI;WP;bf967961-0de6-11d0-a285-00aa003049e2;;$($organizationmanagement)", `
                    "OA;CI;RP;4c164200-20c0-11d0-a768-00aa006e0529;;$($delegatedsetupGet)", `
                    "OA;CI;WP;5430e777-c3ea-4024-902e-dde192204669;;$($exchangeservers)", `
                    "OA;CI;WP;6f606079-3a82-4c1b-8efb-dcc8c91d26fe;;$($exchangeservers)", `
                    "OA;CI;WP;614aea82-abc6-4dd0-a148-d67a59c72816;;$($exchangeservers)", `
                    "OA;CI;WP;66437984-c3c5-498f-b269-987819ef484b;;$($exchangeservers)", `
                    "OA;CI;WP;5e353847-f36c-48be-a7f7-49685402503c;;$($exchangeservers)", `
                    "OA;CI;RP;b1b3a417-ec55-4191-b327-b72e33e38af2;;$($exchangeservers)", `
                    "OA;;CR;1131f6ab-9c07-11d1-f79f-00c04fc2dcd2;;$($exchangeservers)", `
                    "OA;CI;WP;275b2f54-982d-4dcd-b0ad-e53501445efb;;$($exchangeservers)", `
                    "OA;CI;WP;934de926-b09e-11d2-aa06-00c04f8eedd8;;$($exchangeservers)", `
                    "OA;CI;RP;9a7ad945-ca53-11d1-bbd0-0080c76670c0;;$($exchangeservers)", `
                    "OA;CI;WP;f0f8ff9a-1191-11d0-a060-00aa006c33ed;;$($exchangeservers)", `
                    "OA;CI;RP;1f298a89-de98-47b8-b5cd-572ad53d267e;;$($exchangeservers)", `
                    "OA;CI;WP;2cc06e9d-6f7e-426a-8825-0215de176e11;;$($exchangeservers)", `
                    "OA;CI;RP;bf967a68-0de6-11d0-a285-00aa003049e2;;$($exchangeservers)", `
                    "OA;CI;WP;9a9a021e-4a5b-11d1-a9c3-0000f80367c1;;$($exchangeservers)", `
                    "OA;CI;WP;3263e3b8-fd6b-4c60-87f2-34bdaa9d69eb;;$($exchangeservers)", `
                    "OA;CI;WP;8d3bca50-1d7e-11d0-a081-00aa006c33ed;;$($exchangeservers)", `
                    "OA;CI;RP;bf967991-0de6-11d0-a285-00aa003049e2;;$($exchangeservers)", `
                    "OA;CI;WP;7cb4c7d3-8787-42b0-b438-3c5d479ad31e;;$($exchangeservers)", `
                    "OA;CI;RP;5fd424a1-1262-11d0-a060-00aa006c33ed;;$($exchangeservers)", `
                    "OA;CI;CCDCLCRPWPLO;e8b2aff2-59a7-4eac-9a70-819adef701dd;;$($exchangeservers)", `
                    "OA;CIIO;CCDCLC;c975c901-6cea-4b6f-8319-d67f45449506;bf967aba-0de6-11d0-a285-00aa003049e2;$($exchangeservers)", `
                    "OA;CIIO;CCDCLC;c975c901-6cea-4b6f-8319-d67f45449506;4828cc14-1437-45bc-9b07-ad6f015e5f28;$($exchangeservers)", `
                    "OA;CINPIO;RPWPLOSD;;e8b2aff2-59a7-4eac-9a70-819adef701dd;$($exchangeservers)", `
                    "OA;CIIO;CCDCLCSWRPWPDTLOCRSDRCWDWO;;f0f8ffac-1191-11d0-a060-00aa006c33ed;$($exchangetrustedsubsystem)", `
                    "OA;CIIO;CCDCLCSWRPWPDTLOCRSDRCWDWO;;c975c901-6cea-4b6f-8319-d67f45449506;$($exchangetrustedsubsystem)", `
                    "OA;CI;CCDCLCSWRPWPDTLOCRSDRCWDWO;018849b0-a981-11d2-a9ff-00c04f8eedd8;;$($exchangetrustedsubsystem)", `
                    "OA;CI;CCDCLCRPWPLO;f0f8ffac-1191-11d0-a060-00aa006c33ed;;$($exchangetrustedsubsystem)", `
                    "OA;CI;WP;28630ebc-41d5-11d1-a9c1-0000f80367c1;;$($exchangetrustedsubsystem)", `
                    "OA;CI;WP;5fd424a1-1262-11d0-a060-00aa006c33ed;;$($exchangetrustedsubsystem)", `
                    "OA;CI;WP;f0f8ff9a-1191-11d0-a060-00aa006c33ed;;$($exchangetrustedsubsystem)", `
                    "OA;CI;WP;1f298a89-de98-47b8-b5cd-572ad53d267e;;$($exchangetrustedsubsystem)", `
                    "OA;CI;WP;a8df7489-c5ea-11d1-bbcb-0080c76670c0;;$($exchangetrustedsubsystem)", `
                    "OA;CI;WP;77b5b886-944a-11d1-aebd-0000f80367c1;;$($exchangetrustedsubsystem)", `
                    "OA;CI;WP;bf967961-0de6-11d0-a285-00aa003049e2;;$($exchangetrustedsubsystem)", `
                    "OA;CI;WP;bf967954-0de6-11d0-a285-00aa003049e2;;$($exchangetrustedsubsystem)", `
                    "OA;CI;WP;e48d0154-bcf8-11d1-8702-00c04fb96050;;$($exchangetrustedsubsystem)", `
                    "OA;CI;WP;bf967953-0de6-11d0-a285-00aa003049e2;;$($exchangetrustedsubsystem)", `
                    "OA;CI;WP;a673a21e-e65e-43a6-ac59-7e4bfdeb9fb8;;$($exchangetrustedsubsystem)", `
                    "OA;CI;WP;bf96791a-0de6-11d0-a285-00aa003049e2;;$($exchangetrustedsubsystem)", `
                    "OA;CI;WP;b1b3a417-ec55-4191-b327-b72e33e38af2;;$($exchangetrustedsubsystem)", `
                    "OA;CI;WP;3e74f60e-3e73-11d1-a9c0-0000f80367c1;;$($exchangetrustedsubsystem)", `
                    "OA;CI;WP;bf967a06-0de6-11d0-a285-00aa003049e2;;$($exchangetrustedsubsystem)"

        Foreach($sddl in $exchangesddl){
            $ntsecuritydescriptor.Remove($sddl)
        }

        [string]$sddlarray = $exchangesddl[0]
    }    
    
    If($AdminSDHolderSecurity){
        Foreach($sddl in $defaultsddl){
            $ntsecuritydescriptor.Remove($sddl)
        }
    }

    If($ntsecuritydescriptor.Count -eq 0){
        Write-Host "No abnormalities have been found in the AdminSDHolder ACL." -ForegroundColor Green
    } Else {
        Write-Host "Abnormalities have been found in the AdminSDHolder ACL." -ForegroundColor Red
        Write-Output "Number of abnormalities: $($ntsecuritydescriptor.Count)"

        If($TranslateSDDL){
            foreach($securitydescriptor in $ntsecuritydescriptor){
                If(-not ($securitydescriptor -like "*O:DAG:*") ){
                   $sddlarray = $sddlarray + "(" + $securitydescriptor + ")"
                }
        }
            (ConvertFrom-SddlString -Sddl $sddlarray).DiscretionaryAcl
        } Else {
            $ntsecuritydescriptor
        }
    }
}
##############################################################################################