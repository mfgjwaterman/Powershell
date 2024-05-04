# Define the account name for Active Directory synchronization
$AccountName = '_srv-ADDSEntAdm'

# Define the ou where you want to place the new account
$OUservice = 'OU=Service Accounts,OU=Tier 0,OU=Admins,DC=sandbox,DC=lab'

# Load assembly to generate a random password
$null = [Reflection.Assembly]::LoadWithPartialName("System.Web")

# Generate the password
$AccountPasswd = [System.Web.Security.Membership]::GeneratePassword(64,0)

# Write the password to PowerShell console
$AccountPasswd

# Convert the password as secure string
$AccountPasswd = $AccountPasswd | ConvertTo-SecureString -AsPlainText -Force

# Create new AD User for AAD Connect
New-ADUser -Name $AccountName -SamAccountName $AccountName -DisplayName 'Entra ID Connect Service Account' -Path $OUservice -AccountPassword $AccountPasswd -Enabled:$true


(New-Object PSCredential 0, $AccountPasswd).GetNetworkCredential().Password | Set-Clipboard