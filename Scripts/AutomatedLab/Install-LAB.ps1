#Requires -RunAsAdministrator

$labName = 'LAB' # The name of the lab
$Network = 'LAB - Virtual Switch' #The Name of the Internal Network
$DomainName = 'security.lan' # The Domain name of the LAB
$DoVMDeploymentCleanup = $True # Lab Cleanup after it's deployed
$RSATIsoFile = "D:\ISO\Features\mul_windows_11_languages_and_optional_features_x64_dvd_dbe9044b.iso"
$HostNamePAW = "LAB-ADM1"
$HyperVProperties = @{
                        EnableSecureBoot = 'On'
                        SecureBootTemplate = 'MicrosoftWindows'
                        EnableTpm = 'true'
                     }
$LabAdmin = "superuser"
$LabPassword = "P@ssw0rd!"

# Define the LAB
New-LabDefinition -Name $labName `
                  -DefaultVirtualizationEngine HyperV

# Define the domain (only needed if you want to set a custom password)
Add-LabDomainDefinition -Name $DomainName `
                        -AdminUser $LabAdmin `
                        -AdminPassword $LabPassword

# Define the installation credentials, these must be the same as the domain definition credentails 
# (only needed if you want to set a custom password)
Set-LabInstallationCredential -Username $LabAdmin `
                              -Password $LabPassword

# Define the Network (AddressSpace (e.g. -AddressSpace 192.168.1.0/24) is optional, if not set it will automatically be selected)
# use get-vmswitch for the name of the switch, used in -Name
# use get-netadapter to get the name of the adapter it should get attached to (used in AdapterName)
Add-LabVirtualNetworkDefinition -Name $Network `
                                -AddressSpace 192.168.11.0/24
Add-LabVirtualNetworkDefinition -Name 'Default Switch' `
                                -HyperVProperties @{SwitchType = 'External'; AdapterName = 'Ethernet'}

# defining default parameter values, as these ones are the same for all the machines
# use Get-LabAvailableOperatingSystem | select OperatingSystemName, to get the OS names
$PSDefaultParameterValues = @{
    'Add-LabMachineDefinition:EnableWindowsFirewall'= $true
    'Add-LabMachineDefinition:OperatingSystem'= 'Windows Server 2022 Standard Evaluation (Desktop Experience)'
    'Add-LabMachineDefinition:Memory'= 1GB
    'Add-LabMachineDefinition:MinMemory'= 1GB
    'Add-LabMachineDefinition:MaxMemory'= 4GB
    'Add-LabMachineDefinition:Processors'= 4
}

# Add Network Adapters for the router. Using this cmdlet gives more control over the settings inside the VM
$netAdapterRouter = @()
$netAdapterRouter += New-LabNetworkAdapterDefinition -VirtualSwitch $Network
$netAdapterRouter += New-LabNetworkAdapterDefinition -VirtualSwitch 'Default Switch' -UseDhcp

# Add Root Domain Controller
#$postInstallActivity = Get-LabPostInstallationActivity -ScriptFileName ConfigureRootDomain.ps1 -DependencyFolder $labSources\PostInstallationActivities\PWNET
Add-LabMachineDefinition -Name "LAB-DC01" `
                         -Roles RootDC `
                         -Network $Network `
                         -DomainName $DomainName 
                         #-PostInstallationActivity $postInstallActivity
Add-LabMachineDefinition -Name "LAB-DC02" `
                         -Roles DC `
                         -Network $Network `
                         -DomainName $DomainName

# Add the Edge Router
Add-LabMachineDefinition -Name "LAB-EDGE" `
                         -Roles Routing `
                         -NetworkAdapter $netAdapterRouter

# Add Servers to the domain
Add-LabMachineDefinition -Name "LAB-SRV1" `
                         -Network $Network `
                         -DomainName $DomainName
Add-LabMachineDefinition -Name "LAB-SRV2" `
                         -Network $Network `
                         -DomainName $DomainName
Add-LabMachineDefinition -Name "LAB-SRV3" `
                         -Network $Network `
                         -DomainName $DomainName
Add-LabMachineDefinition -Name "LAB-SRV4" `
                         -Network $Network `
                         -DomainName $DomainName
Add-LabMachineDefinition -Name "LAB-SRV5" `
                         -Network $Network `
                         -DomainName $DomainName
Add-LabMachineDefinition -Name "LAB-SRV6" `
                         -Network $Network `
                         -DomainName $DomainName
Add-LabMachineDefinition -Name "LAB-SRV7" `
                         -Network $Network `
                         -DomainName $DomainName `
                         -OperatingSystem 'Windows Server 2019 Standard Evaluation (Desktop Experience)'
Add-LabMachineDefinition -Name "LAB-SRV8" `
                         -Network $Network `
                         -DomainName $DomainName `
                         -OperatingSystem 'Windows Server 2016 Standard Evaluation (Desktop Experience)'

# Add the PAW Machine
Add-LabMachineDefinition -Name $HostNamePAW `
                         -OperatingSystem 'Windows 11 Enterprise Evaluation' `
                         -Network $Network `
                         -DomainName $DomainName `
                         -HyperVProperties $HyperVProperties

#Add Clients to the domain
Add-LabMachineDefinition -Name "LAB-CLT1" `
                         -OperatingSystem 'Windows 11 Enterprise Evaluation' `
                         -Network $Network `
                         -DomainName $DomainName `
                         -HyperVProperties $HyperVProperties
Add-LabMachineDefinition -Name "LAB-CLT2" `
                         -OperatingSystem 'Windows 11 Enterprise Evaluation' `
                         -Network $Network `
                         -DomainName $DomainName `
                         -HyperVProperties $HyperVProperties
Add-LabMachineDefinition -Name "LAB-CLT3" `
                         -OperatingSystem 'Windows 11 Enterprise Evaluation' `
                         -Network $Network `
                         -DomainName $DomainName `
                         -HyperVProperties $HyperVProperties

# Install the lab
Install-Lab

# Install The RSAT Tools on the PAW
Mount-LabIsoImage -ComputerName $HostNamePAW `
                  -IsoPath $RSATIsoFile `
                  -PassThru

#Install RSAT Tools
Invoke-LabCommand -ComputerName $HostNamePAW `
                  -ActivityName "Install RSAT Tools" `
                  -ScriptBlock {$drive = ( Get-CimInstance Win32_CDROMDrive).Drive ;Get-WindowsCapability -Online | Where-Object Name -like "Rsat*"| Add-WindowsCapability -Online -Source (Join-Path -Path $drive -ChildPath "LanguagesAndOptionalFeatures") -LimitAccess} -PassThru

Dismount-LabIsoImage -ComputerName $HostNamePAW

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