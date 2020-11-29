function Test-PSModule {
    param (
      [parameter(Mandatory=$false)]
      [string]$ModuleName = ""
    )
    
    switch ( (Get-Module -ListAvailable).name.Contains($ModuleName) ) {
        $true { 
            Write-Verbose "Module has been located" 
        }
        $false {
            Write-Error "PowerShell Module has not been found, please install before continuing"
        }
    }
}