function Install-NuGetPackageProvider {

    [cmdletBinding()]
    param (
        [parameter(Mandatory=$false)]
        [string]$NuGet = 'NuGet',

        [parameter(Mandatory=$false)]
        [version]$NuGetRequiredVersion = '2.8.5.201'
    )

    Switch ( (Get-PackageProvider -ListAvailable).Name.Contains($NuGet) ) {
        
        $False { 
            Install-PackageProvider -Name $NuGet -MinimumVersion $NuGetrequiredVersion -Force 
        }
        $True {
            Switch ( Find-PackageProvider -Name $NuGet | Select-Object version ){
                { ( [version]$_.Version -lt $NuGetRequiredVersion ) } { 
                    Install-PackageProvider -Name $NuGet -MinimumVersion $NuGetrequiredVersion -Force
                }
            }
        }
    }
}