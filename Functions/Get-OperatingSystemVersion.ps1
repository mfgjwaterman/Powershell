function Get-OperatingSystemVersion {
   [cmdletBinding()]
   param (
      [parameter(Mandatory=$false)]
      [version]$MinimalVersionRequired = '6.3.9600'
   )
   Switch ( Get-CimInstance -Class Win32_OperatingSystem ){
      {([version]$_.Version -le $MinimalVersionRequired )}{ 
         Write-Error -Message "$( (Get-WmiObject -Class Win32_Operatingsystem).caption ) is not a supported Windows version."
       }
   }
}