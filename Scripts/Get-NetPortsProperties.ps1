$Computername = $($env:COMPUTERNAME)
$Output = @()
$Service = $null
$TCPConnections = $null
$UDPConnections = $null

$TCPConnections = Get-NetTCPConnection | where { ($_.LocalAddress -notmatch "::" -and $_.LocalAddress -notmatch "0.0.0.0" -and $_.LocalAddress -notmatch "127.0.0.1") }
$UDPConnections = Get-NetUDPEndpoint | where { ($_.LocalAddress -NotMatch "::") -and ($_.LocalAddress -NotMatch "0.0.0.0") -and ($_.LocalAddress -NotMatch "127.0.0.1") }

foreach($TCPConnection in $TCPConnections){
    
    $Process = Get-Process -id $($TCPConnection.OwningProcess) | select Name, Path
    if($Process.Name -like "svchost"){
        $Service = (Get-WmiObject -Class Win32_Service -Filter "ProcessId='$($TCPConnection.OwningProcess)'" | select -ExpandProperty Name) -join ", "
    }

    $Hashtable = @{
        Path = $($Process.Path)
        "Local IPAddress" = $($TCPConnection.LocalAddress)
        "Local Port" = $($TCPConnection.LocalPort)
        "Remote IPAddress" = $($TCPConnection.RemoteAddress)
        "Remote Port" = $($TCPConnection.RemotePort)
        "TCP State" = $($TCPConnection.State)
        ProcessName = $($Process.Name)
        PID = $($TCPConnection.OwningProcess)
        "SVCHost Services" = $($Service)
        Protocol = "TCP"
        ComputerName = $Computername
    }

    if($($Hashtable.ProcessName) -ne "Idle"){
        $OutPut += [pscustomobject]$Hashtable
    }

    $Service = $null
}


## Process all UDP Connections
foreach($UDPConnection in $UDPConnections){
    
    $Process = Get-Process -id $($UDPConnection.OwningProcess) | select Name, Path
        if($Process.Name -like "svchost"){
        $Service = (Get-WmiObject -Class Win32_Service -Filter "ProcessId='$($UDPConnection.OwningProcess)'" | select -ExpandProperty Name) -join ", "
    }

    $Hashtable = @{
        Path = $($Process.Path)
        "Local IPAddress" = $($UDPConnection.LocalAddress)
        Port = $($UDPConnection.LocalPort)
        ProcessName = $($Process.Name)
        PID = $($UDPConnection.OwningProcess)
        "SVCHost Services" = $($Service)
        Protocol = "UDP"
        ComputerName = $Computername
    }

    if($($Hashtable.ProcessName) -ne "Idle"){
        $OutPut += [pscustomobject]$Hashtable
    }

    $Service = $null
}

$Output | Sort-Object -Property Processname, Port | Select ComputerName, Processname, Path, PID, "SVCHost Services", "Local IPAddress", "Local Port", "Remote IPAddress", "Remote Port", Protocol, "TCP State" | Out-GridView