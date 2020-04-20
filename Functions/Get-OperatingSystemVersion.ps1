function Get-OperatingSystemVersion {
   [cmdletBinding()]
   param (
      [parameter(Mandatory=$false)]
      [version]$MinimalVersionRequired = '6.3.9600'
   )
   Switch ( Get-CimInstance -Class Win32_OperatingSystem ){
      {([version]$_.Version -le $MinimalVersionRequired )}{ 
         Write-Error " $($_.Caption) is not supported"
       }
   }
}