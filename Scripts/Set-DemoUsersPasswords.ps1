# Requires: RSAT tools installed and import of ActiveDirectory module
Import-Module ActiveDirectory

# Top 20 frequently used passwords that pass the policy
$passwords = @(
    "Summer23!", "Password1!", "Welcome1!", "Qwerty12#", "Winter24@",
    "Spring23#", "Autumn22$", "ChangeMe1!", "Letmein2#", "Monkey99@",
    "Admin123!", "October1!", "Football7#", "IloveYou9@", "Shadow88$",
    "Superman1!", "Batman77#", "Starwars8@", "Dragon45$", "Ninja2024!"
)

# Target OU or group - adjust as needed
$users = Get-ADUser -Filter * -SearchBase "OU=Users,OU=Management,DC=lab,DC=internal"

foreach ($user in $users) {
    # Random password from list
    $newPassword = (Get-Random -InputObject $passwords)

    try {
        # Reset the user's password
        Set-ADAccountPassword -Identity $user.SamAccountName -Reset -NewPassword (ConvertTo-SecureString -AsPlainText $newPassword -Force)

        # Optional: force password change at next logon
        Set-ADUser -Identity $user.SamAccountName -ChangePasswordAtLogon $false

        Write-Host "Updated password for $($user.SamAccountName) to $newPassword" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to set password for $($user.SamAccountName): $_"
    }
}
