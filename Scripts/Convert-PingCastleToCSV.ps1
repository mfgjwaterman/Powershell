# Parameter input
##############################################################################################
[CmdletBinding(DefaultParameterSetName="Default")]
param(
[Parameter(
    Mandatory=$true
    )]
[string]$XMLFile,
[Parameter(
    Mandatory=$true
    )]
[string]$Path
)
##############################################################################################


# Check input file
##############################################################################################
Test-Path $XMLFile -ErrorAction Stop | Out-Null
##############################################################################################


# Check Output diectory
##############################################################################################
If(-not (Test-Path $Path) ){
    New-Item -Path $XMLFile -ItemType Directory -ErrorAction Stop | Out-Null
}
##############################################################################################


# Process the XML file
##############################################################################################
$HealthcheckRiskRules = (Select-Xml -Path $XMLFile -XPath "/HealthcheckData/RiskRules/HealthcheckRiskRule").node
$CsvObj = $HealthcheckRiskRules | Select-Object -Property "Rationale", "Category", "Points", "Health Impact", "Workload", "Priority", "Actions", "Hours", "Owner", "Status", "Remarks"
##############################################################################################


# Export the file
##############################################################################################
$DateTime = (([datetime](Select-Xml -Path $XMLFile -XPath *).node.GenerationDate).DateTime).ToString().replace(':',' ')
$NetBiosName = ((Select-Xml -Path $XMLFile -XPath *).node.NetBiosName).ToLower()
$WriteFilePath = (Join-Path -Path $Path -ChildPath $($NetBiosName + " - " + $DateTime + ".csv") )

$CsvObj | Export-Csv -Path $WriteFilePath -NoTypeInformation -Delimiter ';'
##############################################################################################