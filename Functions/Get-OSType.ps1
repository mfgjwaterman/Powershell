function Get-OSType {
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [ValidateSet("Client","Server","DC","ServerDC")]
        [String]$OSType 
    )
    
    Switch( $OSType ){
        'Client' { 
            switch ( (Get-WmiObject -Class Win32_Operatingsystem) ) {
                { ($_.ProductType -ne 1) } { Write-Error -Message "This system type is not supported" }
            }
        }
        'DC' { 
            switch ( (Get-WmiObject -Class Win32_Operatingsystem) ) {
                { ($_.ProductType -ne 2) } { Write-Error -Message "This system type is not supported" }
            }
        }
        'Server' { 
            switch ( (Get-WmiObject -Class Win32_Operatingsystem) ) {
                { ($_.ProductType -ne 3) } { Write-Error -Message "This system type is not supported" }
            }
        }
        'ServerDC' { 
            switch ( (Get-WmiObject -Class Win32_Operatingsystem) ) {
                { ($_.ProductType -eq 1) } { Write-Error -Message "This system type is not supported" }
            }
        }
    }
}



