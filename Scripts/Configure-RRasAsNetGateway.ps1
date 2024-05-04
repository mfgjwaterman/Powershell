# Get the Installed adapters
Get-NetAdapter | select name, MacAddress

# Select the adapter
Rename-NetAdapter -Name "Adaptername" -NewName "AdapterNewName"

# Get the ip address of the internal adapter
Get-NetIPAddress -InterfaceAlias "AdapterName"

# Set the ip address
New-NetIPAddress -IPAddress 192.168.11.1 -InterfaceAlias "Adaptername" -AddressFamily IPv4 -PrefixLength 24

# Set the dns configuration
Set-DnsClient -InterfaceAlias "Adaptername" -ConnectionSpecificSuffix "corp.mydomain.com" -RegisterThisConnectionsAddress $false

#Set the DNS Server
Set-DnsClientServerAddress -InterfaceAlias "AdapterName" -ServerAddresses ("192.168.11.3","192.168.11.2")

#Disable Bindings
Disable-NetAdapterBinding -Name "Adaptername" -ComponentID "ms_implat"
Disable-NetAdapterBinding -Name "Adaptername" -ComponentID "ms_lltdio"
Disable-NetAdapterBinding -Name "Adaptername" -ComponentID "ms_tcpip6"
Disable-NetAdapterBinding -Name "Adaptername" -ComponentID "ms_rspndr"
Disable-NetAdapterBinding -Name "Adaptername" -ComponentID "ms_server"
Disable-NetAdapterBinding -Name "Adaptername" -ComponentID "ms_msclient"
Disable-NetAdapterBinding -Name "Adaptername" -ComponentID "ms_parser"

#Disable netbios over tcp
Invoke-CimMethod -Query 'SELECT * FROM Win32_NetworkAdapterConfiguration WHERE IPEnabled=1' -MethodName SetTcpipNetbios -Arguments @{TcpipNetbiosOptions=[uint32]2}




