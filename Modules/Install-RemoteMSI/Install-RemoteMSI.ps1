<#
.Synopsis
   Install a MSI file on a remote machine using PowerShell.

.DESCRIPTION
   This script installs a MSI file remotly on a Windows based
   machine using PowerShell remoting. The files are first copied
   to the remote machine and executed there. After the installation
   all remote files are cleaned up. Logging is done with every 
   step of the process. Log files can be located in the local
   C:\Windows\Temp folder.

.Parameter MSIFile
    File name of the MSI file. If no filename is ommited 
    "install.msi" is used.

.Parameter MSILocalWorkingDirectory
    The Name of the local install folder. E.g. C:\Foldername.
    Please note that the MSIFile should be present in this 
    folder.

.Parameter MSIParam
    Parameters used during the installation of the MSI file. When 
    this parameter is not ommited the default of "/quiet" is used.

.Parameter ComputerListPath
    The full path to the file containing the host names of the target
    machines.

.Parameter OpenLog
    Opens the logfile after an installation.

.Parameter NoClear
    Does not clear the screen when using -Verbose combined with -Openlog
    
.Example
    Install-MSI-RemotePS.ps1 -MSIFile "LAPS.X64.msi" -MSILocalWorkingDirectory "C:\temp\install" -ComputerListPath "C:\temp\servers.txt"

    This example installs the MSI with the name "LAPS.X64.msi" located in the local foler "C:\temp\install" to all the machines found
    in the file "C:\temp\servers.txt". The "LAPS.X64.msi" file is installed with the default parameter "/quiet"
#>


Function Install-RemoteMSI{

[cmdletbinding(
        DefaultParameterSetName='default'
)]

Param(
    [parameter(
        Position=0, 
        Mandatory = $true,
        ParameterSetName='default'
    )]
    [String]$MSILocalWorkingDirectory,

    [parameter(
        Position=1,
        Mandatory = $true,
        ParameterSetName='default'
    )]
    [String]$MSIFile="install.msi",
 
    [parameter(
        Mandatory=$false,
        ParameterSetName='default'
    )]
    [String]$MSIParam="/quiet",

    [parameter(
        Mandatory = $true,
        ParameterSetName='default'
    )]
    [String]$ComputerListPath,

    [parameter(
        Mandatory = $false,
        ParameterSetName='default'
    )]
    [switch]$OpenLog,

    [parameter(
        Mandatory = $false,
        ParameterSetName='default'
    )]
    [switch]$NoClear

)


$MSIRemoteWorkingDirectory = "C:\Windows\temp\$((New-Guid).Guid)"
$LogFile = ("$env:windir\temp\$(get-date -f yyyy-MM-dd-hh-mm-ss).txt")
$Tab = [char]9
$start = get-date

If(!(Test-Path (Join-Path $MSILocalWorkingDirectory $MSIFile))){
    Write-Error "Installer File does not exist, installation cannot continue" -ErrorAction Stop
} 

If(!(Test-Path $ComputerListPath)){
    Write-Error "Server list does not exist, installation cannot continue" -ErrorAction Stop
} Else 
{
    $ComputerNames = Get-Content -Path $ComputerListPath | where {$_.trim() -ne "" }
}

cls

foreach($ComputerName in $ComputerNames){

    Write-Verbose -Message "$(get-date -f "hh:mm:ss:ms") $($Tab) Installing on: $($ComputerName)"
    Write-Output "$(Get-Date -Format "yyyy-MM-dd hh:mm:ss"), Info     Starting on $($($ComputerName).ToUpper()) " | Out-File $LogFile -Append

    $ping = $null
    $Ping = Get-WmiObject -Class Win32_PingStatus -Filter "Address='$ComputerName' AND Timeout=1000"


if ($Ping.IPV4Address){

Write-Output "$(Get-Date -Format "yyyy-MM-dd hh:mm:ss"), Info     Machine $($($ComputerName).ToUpper()) Is Available" | Out-File $LogFile -Append

    Try
    {
        Write-Verbose -Message "$(get-date -f "hh:mm:ss:ms") $($Tab) Creating session"
        $session = New-PSSession -ComputerName $computerName -ErrorAction SilentlyContinue    
                
        If(!($session)){
            Write-Verbose -Message "$(get-date -f "hh:mm:ss:ms") $($Tab) Session could not be created"
            throw $error[0].ErrorDetails
        } Else {
            Write-Output "$(Get-Date -Format "yyyy-MM-dd hh:mm:ss"), Info     Session with id $($session.ID) to $($($ComputerName).ToUpper()) Succesfully created" | Out-File $LogFile -Append        
        }
        
        Write-Verbose -Message "$(get-date -f "hh:mm:ss:ms") $($Tab) Copy installation files"
        Copy-Item -Path $MSILocalWorkingDirectory -Filter * -ToSession $session -Destination $MSIRemoteWorkingDirectory -Recurse -Force -ErrorVariable CopyFile -ErrorAction SilentlyContinue
        
        If($CopyFile){
            Write-Verbose -Message "$(get-date -f "hh:mm:ss:ms") $($Tab) Installation files could not be copied"
            throw $error[0].ErrorDetails
        } Else {
            Write-Output "$(Get-Date -Format "yyyy-MM-dd hh:mm:ss"), Info     Installation files to $($($ComputerName).ToUpper()) succesfully copied" | Out-File $LogFile -Append
        }

        Write-Verbose -Message "$(get-date -f "hh:mm:ss:ms") $($Tab) Installing on remote host"
        $MSIProcessExitCode = Invoke-Command -Session $session -ScriptBlock {
            $MSIProcess = Start-Process msiexec.exe -ArgumentList "/I $($args[1]) $($args[2])" -WorkingDirectory $($args[0]) -Wait -PassThru
            return $MSIProcess.ExitCode

            Remove-Item -Path $args[0] -Recurse -Force

        } -ArgumentList $MSIRemoteWorkingDirectory, $MSIFile, $MSIParam -ErrorAction SilentlyContinue
        
        If($MSIProcessExitCode -ne 0)
        {
            Write-Verbose -Message "$(get-date -f "hh:mm:ss:ms") $($Tab) Installation was not successfull"
            Write-Output "$(Get-Date -Format "yyyy-MM-dd hh:mm:ss"), Error    MSI Error Code: $MSIProcessExitCode" | Out-File $LogFile -Append
            throw
        } Else {
            Write-Output "$(Get-Date -Format "yyyy-MM-dd hh:mm:ss"), Info     $MSIFile on $($($ComputerName).ToUpper()) Succesfully Installed" | Out-File $LogFile -Append
        }

        Write-Verbose -Message "$(get-date -f "hh:mm:ss:ms") $($Tab) Remove the session"
        Remove-PSSession $session

        If(!($Session.Availability -eq "None")){ 
           Write-Verbose -Message "$(get-date -f "hh:mm:ss:ms") $($Tab) Session could not be terminated"
           throw $error[0].ErrorDetails
        } Else {
            Write-Output "$(Get-Date -Format "yyyy-MM-dd hh:mm:ss"), Info     Session ID $($Session.ID) to Machine $($($ComputerName).ToUpper()) succesfully terminated" | Out-File $LogFile -Append
        }

        Write-Verbose "$(get-date -f "hh:mm:ss:ms") $($Tab) $($($ComputerName).ToUpper()) succesfully installed"
        Write-Output "$(Get-Date -Format "yyyy-MM-dd hh:mm:ss"), Succes   $MSIFile on $($($ComputerName).ToUpper()) Installed" | Out-File $LogFile -Append
     } 
    
    Catch {  
        Write-Host "$($($ComputerName).ToUpper()) Was not succesfully installed, please review the log" -ForegroundColor Red
        Write-Output "$(Get-Date -Format "yyyy-MM-dd hh:mm:ss"), Error    $($error[0].FullyQualifiedErrorId)" | Out-File $LogFile -Append
    }

} Else
  {
    Write-Host "$($($ComputerName).ToUpper()) can not be located or reached" -ForegroundColor Red
    Write-Output "$(Get-Date -Format "yyyy-MM-dd hh:mm:ss"), Error    $($($ComputerName).ToUpper()) could not be located or reached" | Out-File $LogFile -Append
  }
} 

$end = get-date
$TimeSpan = New-TimeSpan -Start $start -End $end
Write-Verbose -Message ""
Write-Verbose -Message "Total runtime was $([math]::Round($($TimeSpan.TotalSeconds),3)) seconds"
Write-Output "$(Get-Date -Format "yyyy-MM-dd hh:mm:ss"), Info     Total runtime was $([math]::Round($($TimeSpan.TotalSeconds),3)) seconds" | Out-File $LogFile -Append

If($OpenLog)
{
    If(!($NoClear)){
        cls
    } Else {
        write-host ""
    }

    If(Test-Path $LogFile) {
        $Logcontent = Get-Content $LogFile
        
        Foreach($Line in $Logcontent) {
            If($line -like "*, Succes*") {
                Write-Host $Line -ForegroundColor Green
            } ElseIf ($line -like "*, Error*") {
                Write-Host $Line -ForegroundColor Red
            } Else {
                Write-Host $Line
            }
        }              
    }
}

}