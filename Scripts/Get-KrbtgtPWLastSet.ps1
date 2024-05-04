Get-ADUser -Identity 'krbtgt' -properties PwdLastSet  | ft Name,@{Name='PwdLastSet';Expression={[DateTime]::FromFileTime($_.PwdLastSet)}}

Get-ADUser 'krbtgt' -Properties "msDS-KeyVersionNumber"
