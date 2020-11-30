[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]$Tenant,

    [Parameter(Mandatory=$false)]
    [string]$Subscription,

    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupprefix,

    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupSuffix,

    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupLocation,

    [Parameter(Mandatory=$true)]
    [string]$ContributorName
)

$ResourceGroup = ( ($ResourceGroupprefix).ToUpper() + ($ResourceGroupSuffix).ToUpper() )
$ErrorActionPreference = "Stop"

function Test-AzContext ([string]$Tenant, [string]$Subscription) {

    switch ( [string]::IsNullOrEmpty( ( Get-AzContext ) ) )
    {
        $false
        {
            Write-Verbose "Authentication to Azure successfully established."
        }
        $true
        {
            Connect-AzAccount   -Tenant $Tenant `
                                -Subscription $Subscription `
        }
    }
}

Test-AzContext -Tenant $Tenant -Subscription $Subscription

## Check the Azure location
try {
    switch -Exact ( ( (Get-AzLocation).location).ToLower().Contains( ($ResourceGroupLocation).ToLower() ) ) {
        $true { Write-Verbose -Message "Using region $ResourceGroupLocation" }
        $false { Write-Error -Message "Azure location could not be located."  }
    }
}
catch {
    Write-Error -Message $Error[0].Exception.Message
}


## Get All the Resource Groups
$ResourceGroups = Get-AzResourceGroup

## Create the Resource Group
try {
    switch -Exact ( ( ( ($ResourceGroups.ResourceGroupName).ToUpper() ) ).Contains( ($ResourceGroup).ToUpper() ) ) {
        $true { Write-Error -Message "Resource Group Already Exists" }
        $false { $ResourceGroup = New-AzResourceGroup    -Name $ResourceGroup `
                                                         -Location $ResourceGroupLocation }
    }
}
catch {
    Write-Error -Message $Error[0].Exception.Message
}

## Give the user the contributor role
try {
    switch -Exact ( (get-azaduser -UserPrincipalName $ContributorName).UserPrincipalName.ToUpper().Contains( ($ContributorName).ToUpper() ) ) {
        $true { New-AzRoleAssignment    -ResourceGroupName $($ResourceGroup).ResourceGroupName `
                                        -SignInName $ContributorName `
                                        -RoleDefinitionName Contributor    }
        $false { Write-Error -Message "The Contributor name could not be located"}
    }
}
catch {
    Write-Error -Message $Error[0].Exception.Message
}

## Tag the Resource Group
try {
    Set-AzResourceGroup -Name $($ResourceGroup).ResourceGroupName `
                    -Tag @{"Resource Owner"=$((get-azaduser -UserPrincipalName $ContributorName).DisplayName);"Creation Date"=(get-date -Format ("MM-dd-yyyy"))}
}
catch {
    Write-Error -Message $Error[0].Exception.Message
}

