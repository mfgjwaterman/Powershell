<#
.Synopsis
   STIG Checklist merge script

.DESCRIPTION
   STIG Checklist merge script

   Release date: 20 Dec 2016
   Description: This script merges two STIG Checklist (.chk) based on vulnerability ID, it will copy the status, details, comment and severity.
   Author: Michael Waterman

.Parameter Source
   provide a valid path to the source checklist file.

.Parameter Target
   provide a valid path to the target checklist file.

.EXAMPLE
   Merge-Checklist -source <full path> -target <full path>
#>


# Parameter input
##############################################################################################
[CmdletBinding(DefaultParameterSetName="None")]
param(

[Parameter(Mandatory=$true)]
[string]$Source,
[Parameter(Mandatory=$true)]
[string]$Target

)
##############################################################################################


#Remove any " or ' in the path
##############################################################################################
if ($Source -match "`"") {$Source = $Source -replace "`"", ""}
if ($Target -match "`"") {$Target = $Target -replace "`"", ""}
if ($Source -match "`'") {$Source = $Source -replace "`'", ""}
if ($Target -match "`'") {$Target = $Target -replace "`'", ""}
##############################################################################################


#Check Paths
##############################################################################################
if (!(Test-Path $Source))
{
    Write-Host 'Source can not be found, please check if the path is correct and the file exists' -ForegroundColor Yellow ; return
}

if (!(Test-Path $Target))
{
    Write-Host 'Target can not be found, please check if the path is correct and the file exists' -ForegroundColor Yellow ; return
}
##############################################################################################


#Create XML Object
$XdocSource = New-Object xml
$xdocTarget = New-Object xml

#Preserve the whitespace in the XML file
$XdocSource.PreserveWhitespace = $true
$xdocTarget.PreserveWhitespace = $true

#Load the documents
$XdocSource.Load($Source)
$xdocTarget.Load($Target)


#List all the vulnerability items in the checklist and use them as a unique key
foreach ($item in $XdocSource.SelectNodes("//CHECKLIST/STIGS/iSTIG/VULN/STIG_DATA[VULN_ATTRIBUTE='Vuln_Num']/ATTRIBUTE_DATA"))
{
    #Get the text and convert from xml format to string
    $item = $item.InnerText

    #if the vulnerability id with the target exists within the attribute_data element replace the text
    if ($xdocTarget.SelectSingleNode("//CHECKLIST/STIGS/iSTIG/VULN/STIG_DATA[ATTRIBUTE_DATA='$item']/ATTRIBUTE_DATA").InnerText)
    {
        #Copy the status
        $xdocTarget.SelectSingleNode("//CHECKLIST/STIGS/iSTIG/VULN[STIG_DATA/ATTRIBUTE_DATA='$item']/STATUS").InnerText = $XdocSource.SelectSingleNode("//CHECKLIST/STIGS/iSTIG/VULN[STIG_DATA/ATTRIBUTE_DATA='$item']/STATUS").InnerText    
        
        
        #Copy the finding details
        $xdocTarget.SelectSingleNode("//CHECKLIST/STIGS/iSTIG/VULN[STIG_DATA/ATTRIBUTE_DATA='$item']/FINDING_DETAILS").InnerText = $XdocSource.SelectSingleNode("//CHECKLIST/STIGS/iSTIG/VULN[STIG_DATA/ATTRIBUTE_DATA='$item']/FINDING_DETAILS").InnerText 
        

        #Copy the comment
        $xdocTarget.SelectSingleNode("//CHECKLIST/STIGS/iSTIG/VULN[STIG_DATA/ATTRIBUTE_DATA='$item']/COMMENTS").InnerText = $XdocSource.SelectSingleNode("//CHECKLIST/STIGS/iSTIG/VULN[STIG_DATA/ATTRIBUTE_DATA='$item']/COMMENTS").InnerText
        
        
        #Copy the severity
        $xdocTarget.SelectSingleNode("//CHECKLIST/STIGS/iSTIG/VULN[STIG_DATA/ATTRIBUTE_DATA='$item']/SEVERITY_OVERRIDE").InnerText = $XdocSource.SelectSingleNode("//CHECKLIST/STIGS/iSTIG/VULN[STIG_DATA/ATTRIBUTE_DATA='$item']/SEVERITY_OVERRIDE").InnerText
        

        #Copy the severity justification
        $xdocTarget.SelectSingleNode("//CHECKLIST/STIGS/iSTIG/VULN[STIG_DATA/ATTRIBUTE_DATA='$item']/SEVERITY_JUSTIFICATION").InnerText = $XdocSource.SelectSingleNode("//CHECKLIST/STIGS/iSTIG/VULN[STIG_DATA/ATTRIBUTE_DATA='$item']/SEVERITY_JUSTIFICATION").InnerText
    }    
}

#Convert the file to UTF-8
$utf8 = New-Object System.Text.UTF8Encoding($false)
$SaveFile = New-Object System.IO.StreamWriter($Target, $False, $utf8)

#Save the target file
$xdocTarget.Save($SaveFile)
$SaveFile.Close()