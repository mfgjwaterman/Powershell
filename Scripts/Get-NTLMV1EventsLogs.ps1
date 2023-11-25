﻿#Requires -Version 5.1

<#PSScriptInfo
    .VERSION 1.0
    .GUID 1b1d52f9-c6f9-4430-b67e-a17db25dbe7d
    .AUTHOR Michael Waterman
    .COMPANYNAME None
    .COPYRIGHT
    .TAGS NTLMv1
#>

<#
    .SYNOPSIS
    retreive NTLMv1 Event log data from remote servers

    .DESCRIPTION
    This script Retreives Event log data regarding NTLM V1 events from assigned servers and generates
    an CSV file from the data.

    Please note that this script requires Windows Server 2016 or above.

    .EXAMPLE
    Get-NTLMV1EventsLogs.ps1 -TimeFilter "24 Hours"
    Retreive all NTLM V1 events from all Domain Controllers

    .EXAMPLE
    Get-NTLMV1EventsLogs.ps1 -TimeFilter "24 Hours" -Servers SRV01,SRV02
    Retreive all NTLM V1 events from all given servers

    .EXAMPLE
    Get-NTLMV1EventsLogs.ps1 -Path C:\Events -TimeFilter "24 Hours"
    Retreive all NTLM V1 events from all Domain Controllers and store the csv file in c:\Events

    .NOTES
    AUTHOR: Michael Waterman
    LASTEDIT: 2023.11.25
#>

# Parameter input
##############################################################################################
[CmdletBinding(DefaultParameterSetName="Default")]
param(
[Parameter(
    Mandatory=$false
    )]
[string]$Path="C:\Events",
[Parameter(
    Mandatory=$true
    )]
[ValidateSet(
    "Last Hour", 
    "Last 12 Hours", 
    "Last 24 Hours", 
    "Last 7 days", 
    "Last 30 days"
    )]
[string]$TimeFilter="Last 24 Hours",
[Parameter(
    Mandatory=$false, 
    ParameterSetName = 'Default'
    )]
[switch]$DC=$True,
[Parameter(
    Mandatory=$true, 
    ParameterSetName = 'Servers'
    )]
[array]$Servers
)
##############################################################################################



# Check Presence Of ActiveDirectory Module
##############################################################################################
If($DC){
    If (-not (Get-Module -ListAvailable | Where-Object Name -eq "ActiveDirectory") ){
        Write-Error "ActiveDirectory Module not found. Please install the RSAT Active Directory Module"
        Return
    }
}
##############################################################################################


# Check Local Directory
##############################################################################################
If(-not (Test-Path $Path) ){
    New-Item -Path $Path -ItemType Directory -ErrorAction Stop | Out-Null
}
##############################################################################################


# Create Full Path to Log File
##############################################################################################
$LogFile = Join-Path -Path $Path -ChildPath "$((Get-Date).Day)-$((Get-Date).Month)-$((Get-Date).Year)-$((Get-Date).Hour)-$((Get-Date).Minute)-$((Get-Date).Second)_NTLM_V1.csv"
##############################################################################################


# Construct Filter Switch
##############################################################################################
switch ( $TimeFilter )
{
    "Last Hour" { $TimeRange = 3600000    }
    "Last 12 Hours" { $TimeRange = 43200000    }
    "Last 24 Hours" { $TimeRange = 86400000   }
    "Last 7 days" { $TimeRange = 604800000 }
    "Last 30 days" { $TimeRange = 2592000000  }
}
##############################################################################################


# Obtain all domain controllers
##############################################################################################
$DomainControllers = Get-ADDomainController -filter *
##############################################################################################


# Construct the XPath filter
##############################################################################################
$XPATH = "*[System[(EventID=4624) and TimeCreated[timediff(@SystemTime) <= $($TimeRange)]]] and Event[EventData[Data[@Name='LmPackageName'] and (Data='NTLM V1' or Data='LM')]]"
##############################################################################################


# Main Function get-NTLMv1Events
##############################################################################################
Function Get-NTLMv1Events($hostname){

 Write-Host "Analysing host $hostname, please wait..." -ForegroundColor Green
 
 try {
 $NTLMv1Events = Get-WinEvent -LogName "Security" -FilterXPath $xpath -ComputerName $hostname
 
    $NTLMv1Events | ForEach-Object {
    $RetObject = [ordered]@{
        TimeCreated          = $_.TimeCreated
        MachineName          = $_.MachineName
        ProviderName         = $_.ProviderName
        LogName              = $_.LogName
        ID                   = $_.ID
        Keywords             = $_.Keywords
        KeywordsDisplayNames = $_.KeywordsDisplayNames
        Level                = $_.Level
        LevelDisplayName     = $_.LevelDisplayName
        Message              = $_.Message
}
    ([xml]$_.ToXml()).Event.EventData.Data | ForEach-Object {
        try {
            $RetObject[$_.Name] = if (Get-Member -InputObject $_ -Name '#text') { $_.'#text' } else { $null }
        }
        catch {
            Write-Debug "[$($MyInvocation.MyCommand)] $($Error[0].Exception.Message) [$($Error[0].Exception.GetType().FullName)]"
            }
        }

        $Data = [PSCustomObject]$RetObject | Select-Object TimeCreated, MachineName, WorkstationName, IpAddress, IpPort, TargetUserName, TargetDomainName, ProcessId, LogonType, LmPackageName
        Export-Csv -InputObject $data -Path $LogFile -Delimiter "," -Append -NoTypeInformation
        }
    }
catch {
    Write-Output $($Error[0].Exception.Message)
}
}
##############################################################################################


# Get Event logs from Domain Controllers
##############################################################################################
If($DC){
    Foreach($DomainController in $DomainControllers){
    
        Get-NTLMv1Events($DomainController.HostName)
    }
}
##############################################################################################


# Get Event logs from Specified Servers
##############################################################################################
If($Servers){
 foreach($Server in $Servers){
    Get-NTLMv1Events $Server
 }
}
##############################################################################################