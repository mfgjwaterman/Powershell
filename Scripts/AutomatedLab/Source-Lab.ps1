### Notes 
### When removing the lab, do:
### Remove-Lab -Name Security -RemoveExternalSwitches
### Remove the Lab Switch Manually
### get-LabVirtualNetworkDefinition | remove-LabVirtualNetworkDefinition
### get-LabVirtualNetworkDefinition (Check if anything is left)
### ipconfig /flushdns
############################################################################

$LabDefinition = 'Security'
$LabVirtualNetworkDefinition = 'Lab - Virtual Switch'
$LabVirtualNetworkDefinitionExt = 'External Virtual Switch'
$AddressSpace = '192.168.66.0/24'
$LabDomainDefinition = 'security.local'
$AdminUserName = 'Superuser'
$AdminPassword = 'P@ssw0rd!'
$HyperVProperties = @{
    EnableSecureBoot = 'On'
    SecureBootTemplate = 'MicrosoftWindows'
    EnableTpm = 'true'
 }
 $RSATIsoFile = "D:\ISO\Features\mul_windows_11_languages_and_optional_features_x64_dvd_dbe9044b.iso"
 $ManagementComputerName = 'LAB-PAW01'
 $TotalNumberOfServers = 2
 $TotalNumberOfEndPoints = 2
 $AddServer2016 = $false
 $AddServer2019 = $false

#Create an empty lab template
New-LabDefinition -Name $LabDefinition `
                  -DefaultVirtualizationEngine HyperV `
                  -VmPath "C:\AutomatedLab-VMs"

# Define the Network (AddressSpace (e.g. -AddressSpace 192.168.1.0/24) is optional, if not set it will automatically be selected)
# use get-vmswitch for the name of the switch, used in -Name
# use get-netadapter to get the name of the adapter it should get attached to (used in AdapterName)
Add-LabVirtualNetworkDefinition -Name $LabVirtualNetworkDefinition `
                                -AddressSpace $AddressSpace
Add-LabVirtualNetworkDefinition -Name $LabVirtualNetworkDefinitionExt `
                                -HyperVProperties @{SwitchType = 'External'; AdapterName = 'vEthernet (External Virtual Switch)'}

#Create the network definition for the router
$NetAdapterRouter = @()
$NetAdapterRouter += New-LabNetworkAdapterDefinition -VirtualSwitch $LabVirtualNetworkDefinition
$NetAdapterRouter += New-LabNetworkAdapterDefinition -VirtualSwitch $LabVirtualNetworkDefinitionExt -UseDhcp

#Set the domain definition with the domain admin account
Add-LabDomainDefinition -Name $LabDomainDefinition `
                        -AdminUser $AdminUserName `
                        -AdminPassword $AdminPassword

#Set the installation credentials
Set-LabInstallationCredential -Username $AdminUserName `
                              -Password $AdminPassword

#Set the parameters that are the same for all machines
$PSDefaultParameterValues = @{
    'Add-LabMachineDefinition:Network' = $LabVirtualNetworkDefinition
    'Add-LabMachineDefinition:Processors' = 4
    'Add-LabMachineDefinition:Memory' = 2GB
    'Add-LabMachineDefinition:MinMemory'= 1GB
    'Add-LabMachineDefinition:MaxMemory'= 2GB
    'Add-LabMachineDefinition:OperatingSystem' = 'Windows Server 2022 Standard Evaluation (Desktop Experience)'
    'Add-LabMachineDefinition:EnableWindowsFirewall'= $true
}

#Defining LAB machines
Add-LabMachineDefinition -Name "LAB-DC01" `
                         -DomainName $LabDomainDefinition `
                         -Roles RootDC 

#Add-LabMachineDefinition -Name "LAB-DC02" `
#                         -DomainName $LabDomainDefinition `
#                         -Roles DC
    
Add-LabMachineDefinition -Name "LAB-EDGE" `
                         -Roles Routing `
                         -NetworkAdapter $NetAdapterRouter

Add-LabMachineDefinition -Name $ManagementComputerName `
                         -OperatingSystem 'Windows 11 Enterprise Evaluation' `
                         -DomainName $LabDomainDefinition `
                         -HyperVProperties $HyperVProperties                         

#Add Servers to the domain                         
for ($AmountOfServers = 1; $AmountOfServers -le $TotalNumberOfServers; $AmountOfServers++) {
Add-LabMachineDefinition -Name ("LAB-SRV0" + $AmountOfServers) `
                         -DomainName $LabDomainDefinition
}

If ($AddServer2016){
$TotalNumberOfServers++ 
Add-LabMachineDefinition -Name ("LAB-SRV0" + $TotalNumberOfServers ) `
                         -DomainName $LabDomainDefinition `
                         -OperatingSystem 'Windows Server 2016 Standard Evaluation (Desktop Experience)'
}

If ($AddServer2019){
$TotalNumberOfServers++    
Add-LabMachineDefinition -Name ("LAB-SRV0" + $TotalNumberOfServers) `
                         -DomainName $LabDomainDefinition `
                         -OperatingSystem 'Windows Server 2019 Standard Evaluation (Desktop Experience)'                         
}

#Add EndPoints to the domain
for ($AmountOfEndPoints = 1; $AmountOfEndPoints -le  $TotalNumberOfEndPoints; $AmountOfEndPoints++) {
    Add-LabMachineDefinition -Name ("LAB-ENDPOINT0" + $AmountOfEndPoints) `
                             -OperatingSystem 'Windows 11 Enterprise Evaluation' `
                             -DomainName $LabDomainDefinition `
                             -HyperVProperties $HyperVProperties
}

# Install the LAB                         
Install-Lab

# Install The RSAT Tools on the PAW
Mount-LabIsoImage -ComputerName $ManagementComputerName `
                  -IsoPath $RSATIsoFile `
                  -PassThru

#Install RSAT Tools
Invoke-LabCommand -ComputerName $ManagementComputerName `
                  -ActivityName "Install RSAT Tools" `
                  -ScriptBlock {$drive = ( Get-CimInstance Win32_CDROMDrive).Drive ;Get-WindowsCapability -Online | Where-Object Name -like "Rsat*"| Add-WindowsCapability -Online -Source (Join-Path -Path $drive -ChildPath "LanguagesAndOptionalFeatures") -LimitAccess} -PassThru

Dismount-LabIsoImage -ComputerName $ManagementComputerName

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
    Invoke-LabCommand -ComputerName (Get-LabVM) -ActivityName "Cleanup" -ScriptBlock  {
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
            if (Test-Path -Path 'C:\WinRmCustomization.ps1'){
            Remove-Item 'C:\WinRmCustomization.ps1' -Recurse -Force
        }
            if (Test-Path -Path (Join-Path -Path 'C:' -ChildPath $($env:COMPUTERNAME + '.cer') )){
            Remove-Item (Join-Path -Path 'C:' -ChildPath $($env:COMPUTERNAME + '.cer') ) -Recurse -Force
        }
    }
}

# Restart all the Domain Controllers lab virtual machines
$LabDCs =Get-LabVM | Where-Object {( $_.Roles -like "*DC*" -and $_.OperatingSystemType -eq "Windows" )}
foreach($LabDC in $LabDCs)
{
    Restart-LabVM -ComputerName $LabDC.Name `
                  -NoNewLine `
                  -Wait
}

# Restart All Servers
Restart-LabVM -ComputerName (Get-LabVM | Where-Object {( $_.OperatingSystem -Like "*Windows Server*" -and ($_.Roles -notlike "*DC*" -or -not $_.Roles) -and $_.OperatingSystemType -eq "Windows" )}).Name

#Restart All Clients
Restart-LabVM -ComputerName (Get-LabVM | Where-Object {( $_.OperatingSystem -NotLike "*Windows Server*" -and $_.OperatingSystemType -eq "Windows" )}).Name

# Show all the installation details
Show-LabDeploymentSummary -Detailed