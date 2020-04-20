Function Test-InternetConnection {

    $Beacon = 'internetbeacon.msedge.net'

    Switch ( Test-NetConnection -CommonTCPPort HTTP -ComputerName $Beacon ){
        { ( $_.TcpTestSucceeded -ne $true ) } { 
            $ErrorActionPreference = 'Stop'
            Write-Error -Message 'Cannot connect to the internet, please check your connection and try again.'
        }
        { ( $_.TcpTestSucceeded -eq $true ) } { 
            Write-Verbose -Message "Connectivity to $($Beacon) established"
        }
    }
}