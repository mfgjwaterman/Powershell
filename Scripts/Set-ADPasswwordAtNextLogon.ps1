#requires -Module ActiveDirectory

<#PSScriptInfo
    .VERSION 1.0
    .GUID 6de67fa4-ce51-4410-b34b-527f8ff9b20b
    .AUTHOR Michael Waterman
    .COMPANYNAME None
    .COPYRIGHT
    .TAGS Active Directory, Users, Passwords, Reset

    .NOTES
    AUTHOR: Michael Waterman
    Blog: https://michaelwaterman.nl
    LASTEDIT: 09-01-2024
#>



<#
.SYNOPSIS
This PowerShell script sets the "Reset Password at Next Logon" attribute for all user objects in a specified Organizational Unit (OU) in Active Directory.

.DESCRIPTION
This script takes an Organizational Unit (OU) path as a parameter and retrieves all user objects within that OU. It then sets the "Reset Password at Next Logon" attribute to $true for each user in the specified OU. You can use this script to enforce password changes for users in a specific OU.

.PARAMETER ouPath
Specifies the path to the Organizational Unit (OU) where the user objects are located in Active Directory.

.EXAMPLE
.\Set-ResetPasswordAtLogon.ps1 -ouPath "OU=Users,DC=YourDomain,DC=com"
This example sets the "Reset Password at Next Logon" attribute to $true for all user objects in the "Users" OU in the "YourDomain.com" domain.

#>

param (
    [Parameter(Mandatory=$true)]
    [string]$ouPath
)

# Use the Get-ADUser cmdlet to retrieve all user objects within the specified OU
$users = Get-ADUser -Filter * -SearchBase $ouPath -Properties * -ResultPageSize 256

# Check if $users is empty
if ($users.Count -eq 0) {
    Write-Error "No user objects found in the specified OU: $ouPath"
    return
}

# Loop through the user objects and set the "Reset Password at Next Logon" attribute
foreach ($user in $users) {
    # Set the "Reset Password at Next Logon" attribute to $true
    Set-ADUser -Identity $user -ChangePasswordAtLogon $true

    # Display user properties if verbose is used
    Write-Verbose "Setting 'Reset Password at Next Logon' for $($user.Name)"
}
