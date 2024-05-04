$AddsUPN = "sandbox.lab"
$EntraUPN = "michaelwaterman.nl"
$SearchBase = "OU=Users,OU=Management,DC=sandbox,DC=lab"
$UPNFilter = "'*$($AddsUPN)'"

$UsersInScope = Get-ADUser -Filter "UserPrincipalName -like $($UPNFilter)" -Properties userPrincipalName -ResultSetSize $null -SearchBase $SearchBase
$UsersInScope | foreach {$NewUpn = $_.UserPrincipalName.Replace("@$($AddsUPN)","@$($EntraUPN)"); $_ | Set-ADUser -UserPrincipalName $NewUpn}