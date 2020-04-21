[cmdletBinding()]
Param(
    [parameter(Mandatory=$false)]
    [int]$WaitInSeconds = 300,

    [parameter(Mandatory=$false)]
    [int]$TripCycles = 3,

    [parameter(Mandatory=$false)]
    [string]$WUServer,

    [parameter(Mandatory=$false)]
    [switch]$RepairWU,

    [parameter(Mandatory=$false)]
    [switch]$DoCLeanUp
)

function Get-MDTWSUSServer {
    [cmdletBinding()]
    param (
        [parameter(Mandatory=$false)]
        $MDTVariablesPath = 'C:\MININT\SMSOSD\OSDLOGS\VARIABLES.DAT'
    )
    
    switch ( Test-Path -Path $MDTVariablesPath ) {
        $true { 
            [XML]$XML = Get-Content -Path $MDTVariablesPath
            $XML.SelectSingleNode('//MediaVarList/var[@name="WSUSSERVER"]').InnerText
         }
    }
}

function New-RegistryEntry {
    [cmdletBinding()]
    param (
        [parameter(Mandatory=$true)]
        $SetRegPath,

        [parameter(Mandatory=$true)]
        $SetRegName,

        [parameter(Mandatory=$true)]
        $SetRegValue,

        [parameter(Mandatory=$true)]
        [ValidateSet('String','ExpandString','Binary', 'DWord', 'MultiString', 'Qword')]
        $SetRegPropertyType
    )
 
    switch (Test-Path -Path $SetRegPath ) {
        $true {  
            New-ItemProperty -Path $SetRegPath `
                             -Name $SetRegName `
                             -Value $SetRegValue `
                             -PropertyType $SetRegPropertyType `
                             -Force | Out-Null
        }
        $false {  
            New-Item -Path $SetRegPath -Force | Out-Null

            New-ItemProperty -Path $SetRegPath `
                             -Name $SetRegName `
                             -Value $SetRegValue `
                             -PropertyType $SetRegPropertyType `
                             -Force | Out-Null
        }
    }
}

function Remove-RegistryEntry {
    [cmdletBinding()]
    param (
        [parameter(Mandatory=$true)]
        $DelRegPath,

        [parameter(Mandatory=$true)]
        $DelregValue
    )

    if ( Test-Path -Path $DelRegPath ){

        If( (Get-Item -Path $DelRegPath).GetValue($DelregValue) ){
            Remove-ItemProperty -Path $DelRegPath -Name $DelregValue -Force
        }
    }

    if (Test-Path -Path $DelRegPath){

        if ( ( (Get-Item -Path $DelRegPath | Select-Object -ExpandProperty property).count ) -eq 0 ){
            Remove-Item -Path $DelRegPath -Force
        }
    }
}

function Repair-WindowsUpdate {
    Set-Service -Name wuauserv -StartupType Manual
    Set-Service -Name BITS -StartupType Manual

    switch ( Get-Service -Name BITS ) {
        { $_.Status -eq 'Running' } { Stop-Service -Name BITS -Force }
    }

    switch ( Get-Service -Name wuauserv ) {
        { $_.Status -eq 'Running' } { Stop-Service -Name wuauserv -Force }
    }

    switch ( Test-Path -Path "C:\Windows\SoftwareDistribution" -PathType Container ) {
        $true { Remove-Item -Path "C:\Windows\SoftwareDistribution\*" -Recurse -Force -ErrorAction SilentlyContinue }
    }

    switch ( Test-Path -Path "C:\Windows\WindowsUpdate.log" -PathType Leaf ) {
        $true { Remove-Item -Path "C:\Windows\WindowsUpdate.log" -Force -ErrorAction SilentlyContinue }
    }

    Invoke-Command -ScriptBlock { C:\Windows\system32\regsvr32.exe /s %windir%\system32\atl.dll }
    Invoke-Command -ScriptBlock { C:\Windows\system32\regsvr32.exe /s %windir%\system32\jscript.dll }
    Invoke-Command -ScriptBlock { C:\Windows\system32\regsvr32.exe /s %windir%\system32\msxml3.dll }
    Invoke-Command -ScriptBlock { C:\Windows\system32\regsvr32.exe /s %windir%\system32\softpub.dll }
    Invoke-Command -ScriptBlock { C:\Windows\system32\regsvr32.exe /s %windir%\system32\wuapi.dll }
    Invoke-Command -ScriptBlock { C:\Windows\system32\regsvr32.exe /s %windir%\system32\wuaueng.dll }
    Invoke-Command -ScriptBlock { C:\Windows\system32\regsvr32.exe /s %windir%\system32\wuaueng1.dll}
    Invoke-Command -ScriptBlock { C:\Windows\system32\regsvr32.exe /s %windir%\system32\wucltui.dll }
    Invoke-Command -ScriptBlock { C:\Windows\system32\regsvr32.exe /s %windir%\system32\wups.dll }
    Invoke-Command -ScriptBlock { C:\Windows\system32\regsvr32.exe /s %windir%\system32\wuweb.dll }

    switch ( Get-Service -Name BITS ) {
        { $_.Status -eq 'Stopped' } { Start-Service -Name BITS -Force }
    }

    switch ( Get-Service -Name wuauserv ) {
        { $_.Status -eq 'Stopped' } { Start-Service -Name wuauserv -Force }
    }
}

function Update-WSUSCache {
    [cmdletBinding()]
    param (
        [parameter(Mandatory=$false)]
        [int]$WaitInSeconds = 300,

        [parameter(Mandatory=$false)]
        [int]$TripCycles = 3
    )

    foreach ($Counter in 1..($TripCycles -1) ){
        switch ($Counter) {
            1 { 
                Write-Output "Initializing run $($Counter), waiting for $($WaitInSeconds) seconds"
                Invoke-Command -ScriptBlock { wuauclt /resetauthorization /detectnow /reportnow }
                Start-Sleep -Seconds $WaitInSeconds
             }
        }

        $Counter++
        
        Write-Output "Initializing run $($Counter), waiting for $($WaitInSeconds) seconds"
        Start-Sleep -Seconds $WaitInSeconds
        Invoke-Command -ScriptBlock { wuauclt.exe /detectnow /reportnow }
    }
}

switch ( $(Get-MDTWSUSServer) ) {
    { !([string]::IsNullOrEmpty($_)) } {  
        New-RegistryEntry   -SetRegPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' `
                            -SetRegName 'WUServer' `
                            -SetRegValue $(Get-MDTWSUSServer) `
                            -SetRegPropertyType 'String'

        New-RegistryEntry   -SetRegPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' `
                            -SetRegName 'WUStatusServer' `
                            -SetRegValue $(Get-MDTWSUSServer) `
                            -SetRegPropertyType 'String'

        New-RegistryEntry   -SetRegPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' `
                            -SetRegName 'UseWUServer' `
                            -SetRegValue 1 `
                            -SetRegPropertyType 'DWord'   

        switch ( Get-Service -Name wuauserv ) {
            { $_.Status -eq 'Stopped' } { Start-Service -Name wuauserv }
            { $_.Status -eq 'Running' } { Restart-Service -Name wuauserv }
        }
    }
}

switch ($WUServer) {
    { !([string]::IsNullOrEmpty($_)) } { 
        New-RegistryEntry   -SetRegPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' `
                            -SetRegName 'WUServer' `
                            -SetRegValue $WUServer `
                            -SetRegPropertyType 'String'

        New-RegistryEntry   -SetRegPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' `
                            -SetRegName 'WUStatusServer' `
                            -SetRegValue $WUServer `
                            -SetRegPropertyType 'String'

        New-RegistryEntry   -SetRegPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' `
                            -SetRegName 'UseWUServer' `
                            -SetRegValue 1 `
                            -SetRegPropertyType 'DWord'

        switch ( Get-Service -Name wuauserv ) {
            { $_.Status -eq 'Stopped' } { Start-Service -Name wuauserv }
            { $_.Status -eq 'Running' } { Restart-Service -Name wuauserv }
        }
     }
}

switch ( Test-Path -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' ) {
    $true {  
        switch ( (Get-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate').GetValue('WUServer') ) {
            {[string]::IsNullOrEmpty($_)} { Write-Error -Message "No WSUS Server could be located, this script cannot continue" -ErrorAction Stop }
            { !([string]::IsNullOrEmpty($_)) } { Update-WSUSCache -WaitInSeconds $WaitInSeconds -TripCycles $TripCycles  }
        }
    }
    $false { Write-Error -Message "No WSUS Server could be located, this script can not continue" -ErrorAction Stop }
}

switch ($RepairWU) {
    $true { Repair-WindowsUpdate }
}

switch ($DoCLeanUp) {
    $true { 
        Remove-RegistryEntry -DelRegPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -DelregValue 'UseWUServer'
        Remove-RegistryEntry -DelRegPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -DelregValue 'WUServer'
        Remove-RegistryEntry -DelRegPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -DelregValue 'WUStatusServer'

        switch ( Get-Service -Name wuauserv ) {
            { $_.Status -eq 'Stopped' } { Start-Service -Name wuauserv }
            { $_.Status -eq 'Running' } { Restart-Service -Name wuauserv }
        }
    }
}