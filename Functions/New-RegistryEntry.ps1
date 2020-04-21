function New-RegistryEntry {
    [cmdletBinding()]
    param (
        [parameter(Mandatory=$true)]
        $SetRegPath,

        [parameter(Mandatory=$true)]
        $SetRegName,

        [parameter(Mandatory=$true)]
        $SetRegValue,

        [parameter(Mandatory=$true)]
        [ValidateSet('String','ExpandString','Binary', 'DWord', 'MultiString', 'Qword')]
        $SetRegPropertyType
    )
 
    switch (Test-Path -Path $SetRegPath ) {
        $true {  
            New-ItemProperty -Path $SetRegPath `
                             -Name $SetRegName `
                             -Value $SetRegValue `
                             -PropertyType $SetRegPropertyType `
                             -Force | Out-Null
        }
        $false {  
            New-Item -Path $SetRegPath -Force | Out-Null

            New-ItemProperty -Path $SetRegPath `
                             -Name $SetRegName `
                             -Value $SetRegValue `
                             -PropertyType $SetRegPropertyType `
                             -Force | Out-Null
        }
    }
}