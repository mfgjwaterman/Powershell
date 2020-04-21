$labName = 'ContosoLab' # The name of the lab
$Network = 'Contoso - Virtual Switch' #The Name of the Internal Network
$DomainName = 'corp.contoso.lab' # The Domain name of the LAB
$DoVMDeploymentCleanup = $True # Lab Cleanup after it's deployed
$Windows10Ent = "Windows 10 Enterprise Evaluation"
$WindowsServer2012R2 = "Windows Server 2012 R2 Standard Evaluation (Server with a GUI)"
$WindowsServer2016 = "Windows Server 2016 Standard Evaluation (Desktop Experience)"
$FODIsoFile = "$labSources\ISOs\en_windows_10_features_on_demand_part_1_version_1903_x64_dvd_1076e85a.iso"
$AdminWorkstation = "ADM-CLT1"
$RootDC = "ADM-DC1"
$LabAdmin = ""
$LabPassword = ""

# Define the LAB and needed
New-LabDefinition -Name $labName -DefaultVirtualizationEngine HyperV

# Define the domain (only needed if you want to set a custom password)
Add-LabDomainDefinition -Name $DomainName -AdminUser $LabAdmin -AdminPassword $LabPassword

# Define the Network (AddressSpace (e.g. -AddressSpace 192.168.1.0/24) is optional, if not set it will automatically be selected)
# use get-vmswitch for the name of the switch, used in -Name
# use get-netadapter to get the name of the adapter it should get attached to (used in AdapterName)
Add-LabVirtualNetworkDefinition -Name $Network
Add-LabVirtualNetworkDefinition -Name 'Default Switch' -HyperVProperties @{SwitchType = 'External'; AdapterName = 'vEthernet (Default Switch)'}

#defining default parameter values, as these ones are the same for all the machines
$PSDefaultParameterValues = @{
    'Add-LabMachineDefinition:EnableWindowsFirewall'= $true
    'Add-LabMachineDefinition:OperatingSystem'= $WindowsServer2016
    'Add-LabMachineDefinition:Memory'= 1GB
    'Add-LabMachineDefinition:MinMemory'= 1GB
    'Add-LabMachineDefinition:MaxMemory'= 2GB
}

# Add Network Adapters for the router. Using this cmdlet gives more control over the settings inside the VM
$netAdapterRouter = @()
$netAdapterRouter += New-LabNetworkAdapterDefinition -VirtualSwitch $Network
$netAdapterRouter += New-LabNetworkAdapterDefinition -VirtualSwitch 'Default Switch' -UseDhcp

# Post Installation activities for the RootDC
$postInstallActivity = Get-LabPostInstallationActivity -ScriptFileName ConfigureRootDomain.ps1 -DependencyFolder $labSources\PostInstallationActivities\Contoso

# Add Root Domain Controller
Add-LabMachineDefinition -OperatingSystemVersion "10.0.14393.3542" -Name $RootDC `
    -Roles RootDC `
    -Network $Network `
    -DomainName $DomainName `
    -PostInstallationActivity $postInstallActivity `
    -InstallationUserCredential (New-Object pscredential $LabAdmin, ($LabPassword | convertto-securestring -asplaintext -Force))

# Add Servers to the domain
Add-LabMachineDefinition -OperatingSystemVersion "10.0.14393.3542" -Name ADM-SRV1 `
    -Network $Network `
    -DomainName $DomainName

Add-LabMachineDefinition -OperatingSystemVersion "10.0.14393.3542" -Name ADM-SRV2 `
    -Network $Network `
    -DomainName $DomainName

Add-LabMachineDefinition -Name ADM-SRV3 `
    -Network $Network `
    -DomainName $DomainName `
    -OperatingSystem $WindowsServer2012R2

Add-LabMachineDefinition -Name ADM-SRV4 `
    -Network $Network `
    -DomainName $DomainName `
    -OperatingSystem $WindowsServer2012R2

# Add Standalone machines
Add-LabMachineDefinition -Name ADM-SRV5 `
    -Network $Network

Add-LabMachineDefinition -Name ADM-SRV6 `
    -Network $Network `
    -OperatingSystem $WindowsServer2012R2

# Add Clients to the domain
Add-LabMachineDefinition -OperatingSystemVersion "10.0.18362.657" -Name $AdminWorkstation `
    -Network $Network `
    -DomainName $DomainName `
    -OperatingSystem $Windows10Ent

Add-LabMachineDefinition -OperatingSystemVersion "10.0.18362.657" -Name ADM-CLT2 `
    -Network $Network `
    -DomainName $DomainName `
    -OperatingSystem $Windows10Ent

# Add a router to the lab
Add-LabMachineDefinition -Name ADM-Router `
    -Roles Routing `
    -NetworkAdapter $netAdapterRouter

# Install the lab
Install-Lab

# Mount the FOD ISO to the Admin WorkStation
$Drive = Mount-LabIsoImage -ComputerName $AdminWorkstation -IsoPath $FODIsoFile -PassThru

# Install the Admin Tools from the FOD ISO
Invoke-LabCommand -ArgumentList $($drive.DriveLetter) `
    -ScriptBlock { Get-WindowsCapability -Online | Where {($_.Name -eq "Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0" -or $_.Name -eq "Rsat.Dns.Tools~~~~0.0.1.0" -or $_.Name -eq "Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0" )} | Add-WindowsCapability -Online -Source $args[0]  } `
    -ComputerName $AdminWorkstation `
    -ActivityName "Admin Tools Installation"

# Remove the FOD ISO from the Admin WorkStation
Dismount-LabIsoImage -ComputerName $AdminWorkstation

# Reset the Lab Primary User because of a bug (No Kerberos Tickets)
Invoke-LabCommand -ArgumentList $LabAdmin, $LabPassword `
    -ScriptBlock { Set-ADAccountPassword -Identity $args[0] -Reset -NewPassword (ConvertTo-SecureString -AsPlainText $args[1] -Force) } `
    -ComputerName $RootDC -PassThru

# Remove the AutoLogon feature
Invoke-LabCommand -ComputerName (Get-LabVM) -ActivityName "Disable AutoLogon" -ScriptBlock {
    if(Get-ItemProperty -Path 'HKLM:\\Software\Microsoft\Windows NT\CurrentVersion\winlogon' -Name AutoAdminLogon -ErrorAction SilentlyContinue){
        Set-ItemProperty -literalPath 'HKLM:\\Software\Microsoft\Windows NT\CurrentVersion\winlogon' -Name AutoAdminLogon -Value 0
    }
    if(Get-ItemProperty -Path 'HKLM:\\Software\Microsoft\Windows NT\CurrentVersion\winlogon' -Name AutoLogonCount -ErrorAction SilentlyContinue ){
        Remove-ItemProperty -Path 'HKLM:\\Software\Microsoft\Windows NT\CurrentVersion\winlogon' -Name AutoLogonCount
    }
    if(Get-ItemProperty -Path 'HKLM:\\Software\Microsoft\Windows NT\CurrentVersion\winlogon' -Name DefaultPassword  -ErrorAction SilentlyContinue ){
        Remove-ItemProperty -Path 'HKLM:\\Software\Microsoft\Windows NT\CurrentVersion\winlogon' -Name DefaultPassword
    }
    if(Get-ItemProperty -Path 'HKLM:\\Software\Microsoft\Windows NT\CurrentVersion\winlogon' -Name AutoLogonSID -ErrorAction SilentlyContinue ){
        Remove-ItemProperty -Path 'HKLM:\\Software\Microsoft\Windows NT\CurrentVersion\winlogon' -Name AutoLogonSID
    }
    if(Get-ItemProperty -Path 'HKLM:\\Software\Microsoft\Windows NT\CurrentVersion\winlogon' -Name DefaultDomainName -ErrorAction SilentlyContinue ){
        Remove-ItemProperty -Path 'HKLM:\\Software\Microsoft\Windows NT\CurrentVersion\winlogon' -Name DefaultDomainName
    }
    if(Get-ItemProperty -Path 'HKLM:\\Software\Microsoft\Windows NT\CurrentVersion\winlogon' -Name DefaultUserName -ErrorAction SilentlyContinue ){
        Remove-ItemProperty -Path 'HKLM:\\Software\Microsoft\Windows NT\CurrentVersion\winlogon' -Name DefaultUserName
    }

} -PassThru


# Set User Account Control
Set-LabVMUacStatus -ComputerName (Get-LabVM) `
    -EnableLUA $true `
    -ConsentPromptBehaviorAdmin 5 `
    -ConsentPromptBehaviorUser 3

# Cleanup Deployment Files From Virtual Machines
if ($DoVMDeploymentCleanup){
    Invoke-LabCommand -ComputerName (Get-LabVM) -ScriptBlock {
        if (Test-Path -Path 'C:\AdditionalDisksOnline.ps1'){
            Remove-Item 'C:\AdditionalDisksOnline.ps1' -Force
        }
            if (Test-Path -Path 'C:\Unattend.xml'){
            Remove-Item 'C:\Unattend.xml' -Force
        }
            if (Test-Path -Path 'C:\WSManRegKey.reg'){
            Remove-Item 'C:\WSManRegKey.reg' -Force
        }
            if (Test-Path -Path 'C:\DeployDebug'){
            Remove-Item 'C:\DeployDebug' -Recurse -Force
        }
    }
}

# Restart all the Domain Controllers lab virtual machines
$LabDCs =Get-LabVM | where {( $_.Roles -like "*DC*" -and $_.OperatingSystemType -eq "Windows" )}
foreach($LabDC in $LabDCs)
{
    Write-Output "Restarting $($LabDC.name)"
    Restart-LabVM -ComputerName $LabDC.Name -NoNewLine -Wait
}

# Restart All Servers
$LabServers = Get-LabVM | where {( $_.OperatingSystem -Like "*Windows Server*" -and (($_.roles).count -eq 0 -or $_.Roles -notlike "*DC*") -and $_.OperatingSystemType -eq "Windows" )}
foreach($LabServer in $LabServers)
{
    Write-Output "Restarting $($LabServer.name)"
    Restart-LabVM -ComputerName $LabServer.Name -NoNewLine -Wait
}

#Restart All Clients
$LabClients = Get-LabVM | where {( $_.OperatingSystem -NotLike "*Windows Server*" -and $_.OperatingSystemType -eq "Windows" )}
foreach($LabClient in $LabClients)
{
    Write-Output "Restarting $($LabClient.Name)"
    Restart-LabVM -ComputerName $LabClient.Name -NoNewLine -Wait
}

# Show all the installation details
Show-LabDeploymentSummary -Detailed

