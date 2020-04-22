function Get-DomainJoinStatus {
    [cmdletBinding()]
    param (
        [parameter(Mandatory = $false)]
        [bool]$IsJoined = $true
    )
    Switch ( Get-CimInstance -Class Win32_OperatingSystem ) {
        { ( !(Get-WmiObject win32_computersystem).partofdomain -eq $IsJoined) } { 
            Write-Error -Message "This machine does not meet the requirements for domain membership status"
        }
    }
}