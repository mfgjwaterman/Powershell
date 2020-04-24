#Requires -RunAsAdministrator
#Requires -Version 5.1

<#PSScriptInfo
    .VERSION 1.0
    .GUID 66c01f41-81df-4125-8431-7b34d360df43
    .AUTHOR ACA IT-Solution - Security Consulting
    .COMPANYNAME ACA IT-Solution
    .COPYRIGHT
    .TAGS LAB Gateway
#>

<#
    .SYNOPSIS
    Install and configure a gateway server for a hyper-v based lab

    .DESCRIPTION
    This script installs and configures a gateway server for a hyper-v based lab

    Please note that this script requires Windows Server 2016 or above.

    .EXAMPLE
    Install-Gateway.ps1
    Configure a gateway server.

    .EXAMPLE
    Install-Gateway.ps1 -InstallRouting 
    Install the Windows Routing feature and restart, this needs to be done before the machine can be configured.

    .EXAMPLE
    Install-Gateway.ps1 -InternallNetWorkAddress 00-15-5D-0A-C8-12 -ExternallNetWorkAddress 00-15-5D-0A-C8-13 InternalAdapterName corp
                        -ExternalAdapterName gateway -InternalIPAddress 192.168.11.1 -InternalPrefixLength 24 
                        -InternalConnectionSpecificSuffix mydomain.com -InternalDNSServerAddresses 192.168.11.2,192.168.11.3
    Set all available parameters

    .NOTES
    AUTHOR: ACA IT-Solution - Security Consulting
    LASTEDIT: 2020.03.30
#>

[cmdletbinding(DefaultParameterSetName='Configure')]
param (
    [Parameter(Mandatory=$true, ParameterSetName='Configure')]
    [string]$InternallNetWorkAddress,
    
    [Parameter(Mandatory=$true, ParameterSetName='Configure')]
    [string]$ExternallNetWorkAddress,

    [Parameter(Mandatory=$true, ParameterSetName='Configure')]
    [string]$InternalAdapterName,

    [Parameter(Mandatory=$true, ParameterSetName='Configure')]
    [string]$ExternalAdapterName,

    [Parameter(Mandatory=$true, ParameterSetName='Configure')]
    [string]$InternalIPAddress,

    [Parameter(Mandatory=$true, ParameterSetName='Configure')]
    [string]$InternalPrefixLength,

    [Parameter(Mandatory=$true, ParameterSetName='Configure')]
    [string]$InternalConnectionSpecificSuffix,

    [Parameter(Mandatory=$true, ParameterSetName='Configure')]
    [Array]$InternalDNSServerAddresses,

    [Parameter(Mandatory=$true, ParameterSetName='RoutingInstall')]
    [switch]$InstallRouting
)

$ErrorActionPreference = "Stop"

Switch ($InstallRouting) {
    $true { switch ( (Get-WindowsFeature -Name Routing).InstallState) {
                Available { Install-WindowsFeature -Name Routing -IncludeAllSubFeature -Restart ; return }
                Installed { Write-Error "Windows Feature Routing is already installed" }
                Default { Write-Verbose "State of the Windows Feature Routing is unknown, configuration cannot continue" ; return }
          }
     }
    $False { switch ( (Get-WindowsFeature -Name Routing).InstallState) {
                Available { Write-Verbose "Windows Feature Routing is not installed, use the -InstallRouting to install the role first" ; return }
                Installed { Write-Verbose "Windows Feature Routing is installed, configuration can continue" }
                Default { Write-Verbose "State of the Windows Feature Routing is unknown, configuration cannot continue" ; return }
           }
    }
}

Write-Verbose -Message "Check the operational status of the networkadapters"
If(Get-NetAdapter | Where-Object Status -NE "UP"){
    Write-Error -Message "Network is not operational"
}

Write-Verbose -Message "Rename the networkadapter"
Get-NetAdapter | Where-Object MacAddress -EQ $InternallNetWorkAddress | Rename-NetAdapter -NewName $InternalAdapterName
Get-NetAdapter | Where-Object MacAddress -EQ $ExternallNetWorkAddress | Rename-NetAdapter -NewName $ExternalAdapterName

Write-Verbose -Message "Configure the adapter bindings and disable ip registration in dns"
foreach($NetAdapter in (Get-NetAdapter | where {($_.MacAddress -EQ $InternallNetWorkAddress) -or ($_.MacAddress -EQ $ExternallNetWorkAddress)})){
    Foreach($NetAdapterBinding in (Get-NetAdapterBinding -InterfaceAlias $NetAdapter.Name )){
        Disable-NetAdapterBinding -Name $NetAdapter.Name -ComponentID $NetAdapterBinding.ComponentID
    }
    Enable-NetAdapterBinding  -Name $NetAdapter.Name -ComponentID "ms_tcpip"
    Disable-NetAdapterBinding -Name $NetAdapter.Name -ComponentID "ms_msclient"
    Disable-NetAdapterBinding -Name $NetAdapter.Name -ComponentID "ms_server"
    
    Set-DnsClient -InterfaceAlias $NetAdapter.Name -RegisterThisConnectionsAddress $false
}

Write-Verbose -Message "Set the IP address of the internal adapter"
New-NetIPAddress -IPAddress $InternalIPAddress -InterfaceAlias $InternalAdapterName -AddressFamily IPv4 -PrefixLength $InternalPrefixLength | Out-Null

Write-Verbose -Message "Set the DNS servers for the internal adapter"
Set-DnsClientServerAddress -InterfaceAlias $InternalAdapterName -ServerAddresses $InternalDNSServerAddresses

Write-Verbose -Message "Set the connection specific dns suffix for the internal adapter"
Set-DnsClient -InterfaceAlias $InternalAdapterName -ConnectionSpecificSuffix $InternalConnectionSpecificSuffix

Write-Verbose -Message "Disable netbios over TCP/IP"
Invoke-CimMethod -Query 'SELECT * FROM Win32_NetworkAdapterConfiguration WHERE IPEnabled=1' -MethodName SetTcpipNetbios -Arguments @{TcpipNetbiosOptions=[uint32]2} | Out-Null

Write-Verbose -Message "Disable LMHOST lookup
Invoke-CimMethod -ClassName Win32_NetworkAdapterConfiguration -Arguments @{WINSEnableLMHostsLookup=$false} -MethodName EnableWINS | Out-Null

Write-Verbose -Message "Enable ICMPv4 Ping Echo reply"
Enable-NetFirewallRule -Name "FPS-ICMP4-ERQ-In"

Write-Verbose -Message "Set the RemoteAccess service to automatically start"
Set-Service -Name RemoteAccess -StartupType Automatic

Write-Verbose -Message "Start the RemoteAccess service"
Start-Service -Name RemoteAccess

Write-Verbose -Message "Install the NAT routing feature"
Invoke-Command -ScriptBlock { & netsh.exe routing ip nat install } -ErrorAction SilentlyContinue | Out-Null

Write-Verbose -Message "Add the external network adapter as a NAT interface"
Invoke-Command -ScriptBlock { & netsh.exe routing ip nat add interface $ExternalAdapterName }

Write-Verbose -Message "Set the external network interface to full NAT"
# Full specifies that full (address and port) translation mode is enabled.
# addressonly specifies that address-only translation mode is enabled.
# private specifies that private mode is enabled
Invoke-Command -ScriptBlock { & netsh.exe routing ip nat set interface $ExternalAdapterName mode=full }

Write-Verbose -Message "Enable the NAT configuration"
Invoke-Command -ScriptBlock { & netsh.exe ras set conf confstate = enabled } | Out-Null

Write-Verbose -Message "Restart the RemoteAccess service"
Restart-Service -Name RemoteAccess

if( $? ){
    Write-Verbose -Message "Script was succesfully executed"
}