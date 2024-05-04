# the module we are looking for
$OnlineModule = "posh-ssh"

# Check if the dependend package provider is already installed
 $PSRepositories = Get-PSRepository | select PackageManagementProvider

foreach ($PSRepository in $PSRepositories)
{
    $PSRepositoryPackageProvider = Get-PackageProvider | where name -EQ $PSRepository.PackageManagementProvider
    if (!$PSRepositoryPackageProvider)
    {
        Write-Host "Installing $PSRepository.PackageManagementProvider"
        Install-PackageProvider $PSRepository.PackageManagementProvider -force -ErrorAction Stop
    }
}

$AvailableModules = Get-Module -ListAvailable -name $OnlineModule
If (!$AvailableModules){

    $OnlineModuleResults = Find-Module -name $OnlineModule -ErrorAction SilentlyContinue
    if ($OnlineModuleResults)
    {
        Install-Module -name $OnlineModule -force -ErrorAction Stop
    } else {
        Write-Host "Module could not be found" -ForegroundColor Red ; return
    }
}