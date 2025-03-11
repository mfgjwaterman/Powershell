#Requires -Modules ActiveDirectory
#Requires -Version 5.1

<#PSScriptInfo
    .VERSION 1.0
    .GUID f010f7b0-b940-4c77-be46-75e23a9d9c5c
    .AUTHOR Michael Waterman
    .COMPANYNAME None
    .COPYRIGHT
    .TAGS Active Directory, Users, Passwords, Passwordless
#>

<#
    .SYNOPSIS
    Randomize passwords for AD Users.

    .DESCRIPTION
    This script can set random passwords for user objects that are part of an 
    Active Directory security group. This script is part of the last step for
    the implementation of passwordless authentication.     

    .EXAMPLE
    Set-RandomPasswordForGroup.ps1 -GroupName "Group name" -PasswordLength 25
    Sets a new random password, that's 20 characters in length for all the users in the security group. Both
    parameters are mandatory.

    .EXAMPLE
    Set-RandomPasswordForGroup.ps1 -GroupName "Group name" -PasswordLength 25 -Debug
    Same as the previous example, but the debug parameter will display the user and the new password. 

    .NOTES
    AUTHOR: Michael Waterman
    Blog: https://michaelwaterman.nl
    LASTEDIT: 2025.03.11
#>

[CmdletBinding(DefaultParameterSetName="Default")]
param(
[Parameter(
    Mandatory=$true
    )]
[string]$GroupName,
[Parameter(
    Mandatory=$true
    )]
[int]$PasswordLength
)

Function Get-RandomPassword
{
    #define parameters
    param([Parameter(ValueFromPipeline=$false)][ValidateRange(1,256)][int]$PasswordLength = 10)
 
    #ASCII Character set for Password.
    $CharacterSet = @{
            Lowercase   = (97..122) | Get-Random -Count 10 | % {[char]$_}
            Uppercase   = (65..90)  | Get-Random -Count 10 | % {[char]$_}
            Numeric     = (48..57)  | Get-Random -Count 10 | % {[char]$_}
            SpecialChar = (33..47)+(58..64)+(91..96)+(123..126) | Get-Random -Count 10 | % {[char]$_}
    }
 
    #Frame Random Password from given character set.
    $StringSet = $CharacterSet.Uppercase + $CharacterSet.Lowercase + $CharacterSet.Numeric + $CharacterSet.SpecialChar
 
    -join(Get-Random -Count $PasswordLength -InputObject $StringSet)
}

# get all the group members.
$GroupMembers = Get-ADGroupMember -Identity $GroupName

# Parse all the members and set a new random password.
Foreach ($Member in $GroupMembers){
    $NewPassword = Get-RandomPassword -PasswordLength $PasswordLength
    
    Write-Debug $Member.name
    Write-Debug $NewPassword

    Set-ADAccountPassword -Reset `
                          -Identity $Member.distinguishedName `
                          -NewPassword (ConvertTo-SecureString -AsPlainText $NewPassword -Force)
}