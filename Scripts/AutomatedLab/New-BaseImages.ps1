$labName = 'BaseImagesCreation'
$incr = 1

New-LabDefinition -Name $labName -DefaultVirtualizationEngine HyperV

ForEach($OperatingSystem in (Get-LabAvailableOperatingSystem)){
    $hostname = "base"
    $hostname = ($hostname + ($incr++))

    Add-LabMachineDefinition -Name $hostname -OperatingSystem ($OperatingSystem.OperatingSystemName)
}

Install-Lab -BaseImages

Remove-Lab -Name $labName -Confirm:$false