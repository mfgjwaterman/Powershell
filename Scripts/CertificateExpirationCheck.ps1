$ExpiresInDays = 500

$Certificates = Get-ChildItem -Path Cert:\LocalMachine -Recurse | where { $_.notafter -le (get-date).AddDays($ExpiresInDays) -AND $_.notafter -gt (get-date)} | select thumbprint, @{Name="Expires On";Expression={$_.NotAfter}}

$Certificates