Get-KdsRootKey
Add-KdsRootKey -EffectiveTime (Get-Date).AddHours(-10)

$ServerAADc = 'cloudidp01'

New-ADServiceAccount -Name '_gMSA-AADC' -PrincipalsAllowedToRetrieveManagedPassword ('{0}$' -f $ServerAADc) -DNSHostName ('{0}.{1}' -f $ServerAADc, (Get-ADDomain).DNSRoot)