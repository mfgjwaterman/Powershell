Install-WindowsFeature -Name RSAT, Routing, RSAT-RemoteAccess -IncludeManagementTools

Set-Service -Name RemoteAccess -StartupType Automatic
Start-Service -Name RemoteAccess

#Get-CimInstance -Class Win32_NetworkAdapter | select -ExpandProperty NetConnectionID

#netsh.exe routing ip nat install
netsh.exe routing ip nat install

# Configures NAT on the specified interface
netsh.exe routing ip nat add interface "Internet"

# the interface on which you want to enable NAT.
# Full specifies that full (address and port) translation mode is enabled.
# addressonly specifies that address-only translation mode is enabled.
# private specifies that private mode is enabled
netsh.exe routing ip nat set interface "Internet" mode=full

# Sets the configuration state of the server
netsh.exe ras set conf confstate = enabled

# Install the DNSProxy
netsh.exe routing ip dnsproxy install

Restart-Service -Name RemoteAccess