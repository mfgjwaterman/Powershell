function Report($msg, $logfile)
{
    Write-Host $msg
 
    $msg | Out-File -FilePath $logfile -Append
}
 
 
$logfile = [System.Environment]::ExpandEnvironmentVariables('%temp%') + "\sidhistorylog.csv"
 
Report "Logging to $logfile" $logfile
 
$forest = Get-ADForest
 
foreach ($domain in $forest.Domains)
{ "Domain $domain SID: $((Get-ADDomain -Identity $domain).DomainSID.ToString())" } 
 
foreach ($domain in $forest.Domains)
{
    Report "Inspecting $domain" $logfile
 
    $users = Get-ADUser -LDAPFilter '(sIDHistory=*)' -Server $domain -Properties sIDHistory
    
    foreach ($usr in $users)
    {
        foreach ($sid in $usr.SIDHistory)
        {
        
            Report "$($usr.DistinguishedName);$($sid.ToString())" $logfile
        }
    }
}
 
Report "Finished logging into $logfile" $logfile 