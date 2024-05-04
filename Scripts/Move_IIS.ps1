#// Get new drive letter from parameters
PARAM (
	[Parameter(Mandatory=$True)]
	[string]$NewDrive,
	[Parameter(Mandatory=$False)]
	[switch]$Force
)

#// Ensure the parameter is a sinlge character
if ($NewDrive.Length -ne 1) {
	$NewDrive = $NewDrive.Substring(0,1)
}

#// Create variables
$OldPath = "%SystemDrive%\inetpub"
$NewPath = $NewDrive+":\inetpub"

#// Check new drive actually exists
if (!(Test-Path $NewDrive":\")) {
	Write-Host "ERROR:"$NewDrive":\ drive does not exist, stopping"
	Exit
}

#// Test if already exists or Force param present
if (!($Force) -And (Test-Path $NewPath)) {
	Write-Host "ERROR: $NewPath already exists, halting move"
	Exit
}

#// Check IIS Installed
if ((Get-WindowsFeature -Name Web-Server).InstallState -ne "Installed") {
	Write-Host "ERROR: IIS not installed, stopping"
	Exit
}

#// stop services
Write-Host "INFO: Stopping IIS"
$StopIIS = &iisreset /stop

#// move inetpub directory
Write-Host "INFO: Moving inetpub directoy to $NewPath"
$MoveFiles = &Robocopy C:\inetpub $NewPath *.* /MOVE /S /E /COPYALL /R:0 /W:0

#// Add file C:\inetpub\Moved_to_Disk_$NewDrive
Write-Host "INFO: Adding movedto file"
$NewDir = New-Item "C:\inetpub" -type directory
$NewFile = Out-File C:\inetpub\Moved_to_Disk_$NewDrive

#// modify reg
Write-Host "INFO: Updating Registry"
$RegUpdate = New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\InetStp" -Name "PathWWWRoot" -Value $NewPath"\wwwroot" -PropertyType ExpandString -Force
$RegUpdate = New-ItemProperty -Path "HKLM:\System\CurrentControlSet\Services\WAS\Parameters" -Name "ConfigIsolationPath" -Value $NewPath"\temp\appPools" -PropertyType String -Force
$RegUpdate = New-ItemProperty -Path "HKLM:\SOFTWARE\Wow6432Node\Microsoft\InetStp" -Name "PathWWWRoot" -Value $NewPath"\wwwroot" -PropertyType ExpandString -Force

#// Backup and modify applicationHost.config file
Write-Host "INFO: Backing up config file"
copy-item C:\Windows\System32\inetsrv\config\applicationHost.config C:\Windows\System32\inetsrv\config\applicationHost.config.bak
Start-Sleep 5

#// Replace "%SystemDrive%\inetpub" with $NewDrive":\inetpub"
Write-Host "INFO: Updating config file"
(Get-Content C:\Windows\System32\inetsrv\config\applicationHost.config).replace("$OldPath","$NewPath") | Set-Content C:\Windows\System32\inetsrv\config\applicationHost.config

#// Update IIS Config
Write-Host "INFO: Updating appcmd config"
$UpdateConfig = &C:\Windows\system32\inetsrv\appcmd set config -section:system.applicationhost/configHistory -path:$NewPath\history

#// Start services
Write-Host "INFO: Starting IIS"
$StartIIS = &iisreset /start

Write-Host "INFO: Completed"
