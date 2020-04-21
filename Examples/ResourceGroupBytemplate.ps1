<#
 .SYNOPSIS
    Creates a cost budget for a given resource group
 .DESCRIPTION
    Creates a monthly budget and notifies Contributors and Readers when the given threshold is reached
 .PARAMETER rgName
    Resource group the budget will be created for
 .PARAMETER budgetAmount
    Monthly budget you want to spend on this resource group
 .PARAMETER budgetThreshold
    Notification threshold for the given budget    
#>

[CmdletBinding(DefaultParametersetName='none')]
Param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$rgName,
    [Parameter(ParameterSetName='createBudget', Mandatory = $true)][ValidateRange(1,100000)][int]$budgetAmount,
    [Parameter(ParameterSetName='createBudget', Mandatory = $true)][ValidateRange(1,100)][int]$budgetThreshold
)

# Budget ARM template URI
$budgetTemplateUri = "https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/create-budget/azuredeploy.json"

# Create budget for given resource group
# The budget is created by using an ARM template. It is possible to create budgets using ARM API directly but this means dealing with API authentication
# Azure PowerShell module cannot share credentials with ARM API which means the necessary token must be acquired seperately e.g. by using ARMClient.exe
# The start date must be first of the month and should be less than the end date.
$budgetParams = @{
    budgetName = "$rgName-budget"
    amount = "$budgetAmount"
    budgetCategory = "Cost"
    timeGrain = "Monthly"
    startDate = "$(Get-Date -Day 1 -Format "yyyy-MM-dd")"
    endDate = ""
    operator = "GreaterThanOrEqualTo"
    threshold = "$budgetThreshold"
    contactEmails = @()
    contactRoles = "Contributor","Reader"
    contactGroups = @()
    resourcesFilter = @()
    metersFilter = @()
}

# Run ARM resource group deployment
$ArmDeployment = New-AzResourceGroupDeployment -Name "initial-budget-$rgName" -ResourceGroupName $rgName -TemplateUri $budgetTemplateUri -TemplateParameterObject $budgetParams