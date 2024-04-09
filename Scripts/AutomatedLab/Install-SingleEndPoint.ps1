$Name = "SingleEP"

New-LabDefinition -Name "SingleEndPoint" `
                  -DefaultVirtualizationEngine HyperV

Set-LabInstallationCredential -Username "superuser" `
                              -Password "P@ssw0rd!"

Add-LabVirtualNetworkDefinition -Name 'Default Switch' `
                                -HyperVProperties @{SwitchType = 'External'; AdapterName = 'Ethernet'}

Add-LabMachineDefinition -Name $Name -OperatingSystem 'Windows 10 Enterprise Evaluation' `
                         -Network 'Default Switch' `
                         -Memory 8GB `
                         -Processors 4 `
                         -EnableWindowsFirewall
Install-Lab

# Reboot
$LabClients = Get-LabVM | where {( $_.OperatingSystem -NotLike "*Windows Server*" -and $_.OperatingSystemType -eq "Windows" )}
foreach($LabClient in $LabClients)
{
    Restart-LabVM -ComputerName $LabClient.Name -NoNewLine -Wait
}

# Remove Edge
Invoke-LabCommand -ComputerName (Get-LabVM) -ActivityName "EdgeRemove" -ScriptBlock {
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/ChrisTitusTech/winutil/main/edgeremoval.ps1" -OutFile "edgeremoval.ps1"
    Start-Process "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -File .\edgeremoval.ps1" 
} -PassThru

Invoke-LabCommand -ComputerName (Get-LabVM) -ActivityName "Winget" -ScriptBlock {
    Invoke-WebRequest -Uri "https://aka.ms/getwinget" `
                        -OutFile "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    Invoke-WebRequest -Uri "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx" `
                        -OutFile "Microsoft.VCLibs.x64.14.00.Desktop.appx"
    Invoke-WebRequest -Uri "https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx" `
                        -OutFile "Microsoft.UI.Xaml.2.8.x64.appx"

    Add-AppxPackage "Microsoft.VCLibs.x64.14.00.Desktop.appx"
    Add-AppxPackage "Microsoft.UI.Xaml.2.8.x64.appx"
    Add-AppxPackage "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
        
    Remove-Item -Path "Microsoft.VCLibs.x64.14.00.Desktop.appx"
    Remove-Item -Path "Microsoft.UI.Xaml.2.8.x64.appx"
    Remove-Item -Path "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
}

# Reboot
$LabClients = Get-LabVM | where {( $_.OperatingSystem -NotLike "*Windows Server*" -and $_.OperatingSystemType -eq "Windows" )}
foreach($LabClient in $LabClients)
{
    Restart-LabVM -ComputerName $LabClient.Name -NoNewLine -Wait
}

# Download VPN
Invoke-LabCommand -ComputerName (Get-LabVM) -ActivityName "VPN" -ScriptBlock {
    Invoke-WebRequest -Uri "https://www.ipvanish.com/software/setup-prod-v2/ipvanish-setup.exe" -OutFile "ipvanish-setup.exe"
}

# Remove AutoStart
Invoke-LabCommand -ComputerName (Get-LabVM) -ActivityName "BGInfo" -ScriptBlock {
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "BgInfo"
}

# Remove AutoLogon
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

# Cleanup Deployment Files From Virtual Machines
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
    Remove-Item -Path "edgeremoval.ps1"
}

$Session = New-LabPSSession -ComputerName (Get-LabVM)
Copy-Item -ToSession $Session -Path "C:\LabSources\PostInstallationActivities\EndPoint\apps.bat" -Destination "C:\users\superuser\desktop"
Remove-PSSession -Session $Session

# Set UAC
Set-LabVMUacStatus -ComputerName (Get-LabVM) -EnableLUA $true -ConsentPromptBehaviorAdmin 5 -ConsentPromptBehaviorUser 3

# Reboot
$LabClients = Get-LabVM | where {( $_.OperatingSystem -NotLike "*Windows Server*" -and $_.OperatingSystemType -eq "Windows" )}
foreach($LabClient in $LabClients)
{
    Restart-LabVM -ComputerName $LabClient.Name -NoNewLine -Wait
}

# Show all the installation details
Show-LabDeploymentSummary -Detailed