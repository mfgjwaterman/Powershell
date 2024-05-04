Param(
    [Parameter(Mandatory=$true)]
    $OSVersionRequired = '6.1.0.0'
)

$OSVersion = (Get-CimInstance -Class Win32_OperatingSystem).Version
$Caption = (Get-CimInstance -Class Win32_OperatingSystem).Caption

if ( [version]$OSVersion -gt [version]$OSVersionRequired )
{
    write-output "You're running" $Caption

} else {

    throw $Caption + " " + "Is not supported"
}