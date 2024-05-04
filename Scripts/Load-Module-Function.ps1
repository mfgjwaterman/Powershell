function Load-Module
{
    param (
        [parameter(Mandatory = $true)][string] $Module
    )

$retVal = $false

# Check if the module is locally available
$AvailableModules = Get-Module -ListAvailable -name $Module

# If the module is not locally available, look in the online repositories
If (!$AvailableModules)
{
    #Check if the dependend package provider is already installed (requirement)
    $PSRepositories = (Get-PSRepository).PackageManagementProvider

    # Install the package providers for the repositories
    foreach ($PSRepository in $PSRepositories)
    {
        # List the package provider and install it
        $PSRepositoryPackageProvider = Get-PackageProvider | where name -EQ $PSRepository
        if (!$PSRepositoryPackageProvider)
            {
                try
                {
                    Install-PackageProvider $PSRepository -force -ErrorAction SilentlyContinue
                    if ($?)
                        {
                            $retVal = $true
                        }             
                }
                # On error set the return value to false
                catch
                {
                        $retVal = $false
                }

            }
    }

    # Check if the module is available online after installing the package providers
    $AvailableModules = Find-Module -name $Module -ErrorAction SilentlyContinue
    If ($AvailableModules){
        
            #Install the online module
            try
            {
                Install-Module -name $Module -force -ErrorAction SilentlyContinue
                if ($?)
                    {
                        $retVal = $true
                    }             
            }
            # On error set the return value to false
            catch
            {
                    $retVal = $false
            }   
           

            #try to import the module
            try
            {
                Import-Module -name $Module -ErrorAction SilentlyContinue
                if ($?)
                    {
                        $retVal = $true
                    }             
            }
            # On error set the return value to false
            catch
            {
                    $retVal = $false
            }
    
    
    } else {
        
            Write-Host "Module could not be found" -ForegroundColor Red
            $retVal = $false
    }

# If the module is locally available, try to load it
} Else {
            #try to import the module
            try
            {
                Import-Module -name $Module
                if ($?)
                    {
                        $retVal = $true
                    }             
            }
            # On error set the return value to false
            catch
            {
                    $retVal = $false
            }
}
    return $retval
}