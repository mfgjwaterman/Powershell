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