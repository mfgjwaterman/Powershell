# Audit NTLM Authentication in this domain: Enable all - Domain Controllers Only
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\services\Netlogon\Parameters' -Name AuditNTLMInDomain -Value 7
 
# Audit incoming NTLM traffic: Enable auditing for all accounts
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0' -Name AuditReceivingNTLMTraffic -Value 2
 
# Restrict NTLM: Outgoing NTLM traffic to remote servers: Audit All
Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0' -Name RestrictSendingNTLMTraffic -Value 1


