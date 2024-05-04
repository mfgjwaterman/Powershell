Function Get-ListeningTCPConnections {            
[cmdletbinding()]            
param(            
)            
            
try {            
    $TCPProperties = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()            
    $Connections = $TCPProperties.GetActiveTcpListeners()            
    foreach($Connection in $Connections) {            
        if($Connection.address.AddressFamily -eq "InterNetwork" ) { $IPType = "IPv4" } else { $IPType = "IPv6" }            
                    
        $OutputObj = New-Object -TypeName PSobject            
        $OutputObj | Add-Member -MemberType NoteProperty -Name "LocalAddress" -Value $connection.Address            
        $OutputObj | Add-Member -MemberType NoteProperty -Name "ListeningPort" -Value $Connection.Port            
        $OutputObj | Add-Member -MemberType NoteProperty -Name "IPV4Or6" -Value $IPType            
        $OutputObj            
    }            
            
} catch {            
    Write-Error "Failed to get listening connections. $_"            
}           
}

Get-ListeningTCPConnections