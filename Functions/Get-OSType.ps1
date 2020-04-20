function Get-OSType {
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateSet("Client","Server","DC","ServerDC")]
        [String]$OSType 
    )
    
    switch ( $OSType ){
        Client   { $ProductType = 1 }
        DC       { $ProductType = 2 }
        Server   { $ProductType = 3 }
        ServerDC { $ProductType = 4 }
    }

    Switch( $ProductType ){
        1 { 
            switch ( (Get-WmiObject -Class Win32_Operatingsystem) ) {
                { ($_.ProductType -ne 1) } { Write-Error -Message "This system type is not supported" }
            }
        }
        2 { 
            switch ( (Get-WmiObject -Class Win32_Operatingsystem) ) {
                { ($_.ProductType -ne 2) } { Write-Error -Message "This system type is not supported" }
            }
        }
        3 { 
            switch ( (Get-WmiObject -Class Win32_Operatingsystem) ) {
                { ($_.ProductType -ne 3) } { Write-Error -Message "This system type is not supported" }
            }
        }
        4 { 
            switch ( (Get-WmiObject -Class Win32_Operatingsystem) ) {
                { ($_.ProductType -eq 1) } { Write-Error -Message "This system type is not supported" }
            }
        }
    }
}




