<#
.Synopsis
   Enables offline installation of signed binary files

.DESCRIPTION
   This script enables the option to install signed software in an offline situation where a certificate revocation check cannot be done. This situation can occur when .Net hardening has been applied and revocation checking has been enforced. When these conditions are true, this error message appears: “0x800b010e – The revocation process could not continue – the certificate(s) could not be checked.”  

   Script version: 1.0
   Script Author: Michael Waterman

.Parameter -On
   Enables the offline installation of signed binary files.

.Parameter -Off
   Reset the system to the default value.

.Parameter -Force
    Force the -On parameter even if a previous backup exists.

.EXAMPLE
    
    Set-OfflineInstallationMode.ps1 -On
    
#>


# Parameter input
##############################################################################################
[CmdletBinding(DefaultParameterSetName="None")]
param(

[Parameter()]
[switch]$On,
[Parameter()]
[switch]$Off,
[Parameter()]
[switch]$Force=$False
)
##############################################################################################

# Setting variables
##############################################################################################
$BackupKey = 'HKCU:\Temp\Software Publishing'
$BackupKeyRoot = 'HKCU:\Temp'
$DefaultValue = "146432"
$Key = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\WinTrust\Trust Providers\Software Publishing'
$Name = 'State'
##############################################################################################


# Script Functions
##############################################################################################
function Test-RegistryValue {

param (

 [parameter(Mandatory=$true)]
 [ValidateNotNullOrEmpty()]$Path,

[parameter(Mandatory=$true)]
 [ValidateNotNullOrEmpty()]$Value
)


try{
    Get-ItemProperty -Path $Path -Name $Value -ErrorAction Stop
    return $true
    }

catch{
    return $false
    }
}
##############################################################################################


# Main(on)
##############################################################################################
If($on){
    If(!$Force){
        If(Test-RegistryValue -Path $BackupKey -Value $Name){
            write-host "Previous stored settings have been located, cannot continue. Use the -Force parameter to override." -ForegroundColor Yellow
                return
            }
        }


If(Test-RegistryValue -Path $Key -Value $Name){
    
    #Create the backup registry location
    New-Item -Path $BackupKey -Force | Out-Null

    #Store the original value in the backup location
    New-ItemProperty -Path $BackupKey -Name $Name -PropertyType DWORD -Value (Get-ItemProperty -Path $Key | Select-Object -ExpandProperty $Name) -Force | Out-Null

    #Set the value to enable offline installation
    New-ItemProperty -Path $Key -Name $Name -PropertyType DWORD -Value $DefaultValue -Force | Out-Null

} Else {
    
    # Create the path
    New-Item -Path $Key -Force | Out-Null

    #Set the value to enable offline installtion
    New-ItemProperty -Path $Key -Name $Name -PropertyType DWORD -Value $DefaultValue -Force | Out-Null
    }
}
##############################################################################################


# Main(Off)
##############################################################################################
If($Off){


If(!$Force){
    If(!(Test-RegistryValue -Path $BackupKey -Value $Name)){
        write-host "Previous stored settings could not be located, cannot continue. Use the -Force parameter to override and reset to OS default." -ForegroundColor Yellow
            return
        }
    }

If(Test-RegistryValue -Path $Key -Value $Name){

        If(Test-RegistryValue -Path $BackupKey -Value $Name){

               # Reset the default value
               New-ItemProperty -Path $Key -Name $Name -PropertyType DWORD -Value (Get-ItemProperty -Path $BackupKey | Select-Object -ExpandProperty $Name) -Force | Out-Null

               #Delete The Backup
               Remove-Item -Path $BackupKeyRoot -Recurse -Force | Out-Null

        } Else {

                # Set the default value if the backup does not exist
                New-ItemProperty -Path $Key -Name $Name -PropertyType DWORD -Value $DefaultValue -Force | Out-Null
        
        }
    
 } Else {
    
        If(Test-RegistryValue -Path $BackupKey -Value $Name){

                # Create the path
                New-Item -Path $Key -Force | Out-Null

                # Set the default value
                New-ItemProperty -Path $Key -Name $Name -PropertyType DWORD -Value (Get-ItemProperty -Path $BackupKey | Select-Object -ExpandProperty $Name) -Force | Out-Null

                #Delete The Backup
                Remove-Item -Path $BackupKeyRoot -Recurse -Force | Out-Null

        } Else {

                # Create the path
                New-Item -Path $Key -Force | Out-Null

                # Set the Default Value if the backup does not exist
                New-ItemProperty -Path $Key -Name $Name -PropertyType DWORD -Value $DefaultValue -Force | Out-Null

        }
    }
}
##############################################################################################