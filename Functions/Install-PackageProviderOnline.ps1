function Install-NuGetPackageProvider {

    [cmdletBinding()]
    param (
        [parameter(Mandatory=$false)]
        [string]$NuGet = 'NuGet',

        [parameter(Mandatory=$false)]
        [String]$NuGetRequiredVersion = '2.8.5.201'
    )

    Switch ( (Get-PackageProvider -ListAvailable).Name.Contains($NuGet) ) {
        
        $False{ 
            Install-PackageProvider -Name $NuGet -MinimumVersion $NuGetrequiredVersion -Force 
        }
        $True {
            $NuGetVersion = (Find-PackageProvider -Name $NuGet | Select-Object -ExpandProperty Version).replace(".","")
        }
    } 

    Switch ($NuGetVersion = (Find-PackageProvider -Name $NuGet | Select-Object -ExpandProperty Version).replace(".","")){
        { ($NuGetVersion -lt $NuGetRequiredVersion) } { 
            Install-PackageProvider -Name $NuGet -MinimumVersion $NuGetrequiredVersion -Force
        }
    }
}