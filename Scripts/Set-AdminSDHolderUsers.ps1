# PowerShell script with a switch parameter to optionally remove the adminCount attribute
# Users are listed only if the switch is not used

param (
    [switch]$RemoveAdminCount
)

# Import Active Directory module
Import-Module ActiveDirectory

# Find all groups with adminCount set to 1
$groupsAdminCount = Get-ADGroup -Filter {adminCount -eq 1} -Properties adminCount

# Find all users with adminCount set to 1, excluding krbtgt
$usersAdminCount = Get-ADUser -Filter {(adminCount -eq 1) -and (SamAccountName -ne 'krbtgt')} -Properties adminCount, MemberOf

# Check each user to ensure they are not members of the identified groups
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

# Depending on the RemoveAdminCount switch, remove the adminCount attribute or list the users
if ($RemoveAdminCount) {
    foreach ($user in $usersNotInAdminCountGroups) {
        Set-ADUser -Identity $user.DistinguishedName -Clear adminCount
        Write-Host "Removed adminCount for user: $($user.Name)"
    }
} else {
    # Output the filtered users
    Write-Host "Users with adminCount set but not in groups with adminCount set (excluding krbtgt):"
    $usersNotInAdminCountGroups | Select-Object Name, DistinguishedName, adminCount
}
