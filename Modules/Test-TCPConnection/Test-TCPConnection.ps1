function Test-TCPConnection{

    [cmdletbinding(
        DefaultParameterSetName='default'
    )]
    Param(
        [parameter(
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName='default',
            Mandatory=$true,
            Position = 0
        )]
        [parameter(
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            ParameterSetName='service',
            Mandatory=$true,
            Position = 0
        )]
        [string]$ComputerName,
    
        [parameter(
            ParameterSetName='default',
            Mandatory=$true)]
        [int]$Port,
    
        [parameter(
            ParameterSetName='service',
            Mandatory=$true)]
        [ValidateSet("SSH", "SMTP", "DNS", "HTTP","HTTPS", "SMB", "RDP", "WINRM", "WINRMSSL")]
        [string]$Service,

        [parameter(
            Mandatory=$false)]
        [int]$Timeout = 80

        )

            if ($PSCmdlet.ParameterSetName -eq 'service')
            {
                switch ( $service )
                {
                    "SSH" {$port = "22"}
                    "SMTP" {$port = "25"}
                    "DNS" {$port = "53"}
                    "http" {$port = "80"}
                    "https" {$port = "443"}
                    "SMB" {$Port = "445"}
                    "RDP" {$Port = "3389"}
                    "WINRM" {$port = "5985"}
                    "WINRMSSL" {$port = "5986"}
                }
            }

    
    try {
        
        Write-Verbose "Resolving IP Address"
        $IPAddress = ([System.Net.Dns]::GetHostAddresses(“$ComputerName“)).IPAddressToString

        Write-Verbose "Create Net Socket Object"
        $TCPClient = New-Object System.Net.Sockets.TcpClient

        Write-Verbose "Connect to host"
        $TCPClient.BeginConnect($ComputerName, $port, $requestCallback, $state) | Out-Null

        Write-Verbose "Wait for the connection to establish, default wait time is 80 Milliseconds"
        Start-Sleep -Milliseconds $timeOut
        
        Write-Verbose "Checking if connection is establish"
        if ($TCPClient.Connected) {
            Write-Verbose "Connection succesful"
            $open = $true
        } 
        else {
            Write-Verbose "Connection unsuccesful"
            $open = $false
        }

        Write-Verbose "Close the connection"
        $TCPClient.Close()

        Write-Verbose "Constructing Object Properties"
        $Properties = @{ComputerName = $ComputerName
            PortNumber               = $port
            IsConnected              = $open
            IPAddress                = $IPAddress
        }

    }

    Catch { 
        
        Write-Verbose "Constructing Object Properties after failure"
        $Properties = @{ComputerName = $ComputerName
            Port                     = $port
            IsConnection             = $false
            IPAddress                = $false
        }

    }

    Finally {
        
        Write-Verbose "Creating return object with properties"
        $ReturnObject = New-Object -TypeName PSObject -Property $Properties

    }
    
  return $ReturnObject

}