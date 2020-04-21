function Remove-RegistryEntry {
    [cmdletBinding()]
    param (
        [parameter(Mandatory=$true)]
        $DelRegPath,

        [parameter(Mandatory=$true)]
        $DelregValue
    )

    if ( Test-Path -Path $DelRegPath ){

        If( (Get-Item -Path $DelRegPath).GetValue($DelregValue) ){
            Remove-ItemProperty -Path $DelRegPath -Name $DelregValue -Force
        }
    }

    if (Test-Path -Path $DelRegPath){

        if ( ( (Get-Item -Path $DelRegPath | Select-Object -ExpandProperty property).count ) -eq 0 ){
            Remove-Item -Path $DelRegPath -Force
        }
    }
}