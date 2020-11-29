function Test-PSModule {
    param (
      [parameter(Mandatory=$false)]
      [string]$Module
    )

    switch (  [string]::IsNullOrEmpty( ( Get-Module -Name $Module -ListAvailable ) ) ){
        $false { 
            Write-Verbose "Module has been located" 
        }
        $true {
            Write-Error "PowerShell Module has not been found, please install before continuing"
        }
    }
}