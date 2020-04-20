Param (
    [Parameter(Mandatory=$true)]
    [string]$XMLFile
)

# Initialize objects for security
$wid=[System.Security.Principal.WindowsIdentity]::GetCurrent()
$prp=new-object System.Security.Principal.WindowsPrincipal($wid)
$adm=[System.Security.Principal.WindowsBuiltInRole]::Administrator
$IsAdmin=$prp.IsInRole($adm)

# Halt if the script is not running as admin
if($IsAdmin -eq $false)
{
    Write-Verbose "Process is not running as admin"
    exit 
}

# Event Logging

$source = "SecureDeployment"

if ([System.Diagnostics.EventLog]::SourceExists($source) -eq $false)
{
    [System.Diagnostics.EventLog]::CreateEventSource($source, "Application")
}

# Functions
function Test-FileLock {
  param (
    [parameter(Mandatory=$true)][string]$Path
  )

  $oFile = New-Object System.IO.FileInfo $Path

  if ((Test-Path -Path $Path) -eq $false) {
      return $false
  }

  try {
    $oStream = $oFile.Open([System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)

    if ($oStream) {
      $oStream.Close()
    }
    return $false
  } catch {
    # file is locked by a process.
    return $true
  }
}


# Test the XML Data file location
If(Test-Path $XMLFile){
    [XML]$XML = Get-Content -Path $XMLFile
} Else {
    Write-EventLog -EventId 1 -LogName Application -Message "XML Data File not Found" -Source SecureDeployment -Category 0 -EntryType Error
    Write-Verbose "XML Data File not Found"
    Return
}

# Test the Image capture folder
If(Test-Path $XML.Configuration.ImageData.CaptureFolder){
    # Folder exists, continue
} Else {
   Write-EventLog -EventId 2 -LogName Application -Message "Image Capture folder not found" -Source SecureDeployment -Category 0 -EntryType Error
   Write-Verbose "Image Capture folder not found"
   Return
}

# Test the ISO destination folder
If(Test-Path $XML.Configuration.ImageData.DestinationFolder){
    # Folder exists, continue
} Else {
   Write-EventLog -EventId 3 -LogName Application -Message "ISO destination folder not found" -Source SecureDeployment -Category 0 -EntryType Error
   Write-Verbose "ISO destination folder not found"
   Return
}

# Test the ISO Creation Utility
If(Test-Path $XML.Configuration.ImageData.Oscdimg){
    # File exists, continue
} Else {
   Write-EventLog -EventId 4 -LogName Application -Message "ISO creation utility OSCDIMG could not be located" -Source SecureDeployment -Category 0 -EntryType Error
   Write-Verbose "ISO creation utility OSCDIMG could not be located"
   Return
}

# Get the Content of the capture folder
$WimFiles = Get-ChildItem -Path $XML.Configuration.ImageData.CaptureFolder -Filter "*.wim"

If($WimFiles){
    foreach($WIMFile in $WimFiles){
        
        Write-EventLog -EventId 5 -LogName Application -Message "New WIM file with name $WIMFile detected" -Source SecureDeployment -Category 0 -EntryType Information

        # Check OpLock
        If(Test-FileLock -Path $WIMFile.Fullname){
            Write-EventLog -EventId 6 -LogName Application -Message "file $WIMFile is locked, will try at next run" -Source SecureDeployment -Category 0 -EntryType Warning
            Return
        }

        # Get/Set the Staging Folder
        If(Test-Path $XML.Configuration.ImageData.StagingFolder){
            Remove-Item -Path $XML.Configuration.ImageData.StagingFolder -Recurse -Force
            New-Item -Path $XML.Configuration.ImageData.StagingFolder -ItemType Directory -Force | Out-Null
        } Else {
            New-Item -Path $XML.Configuration.ImageData.StagingFolder -ItemType Directory -Force | Out-Null
        }

        # Get the MDT Generated Image Name
        $MDTImageName = Get-WindowsImage -ImagePath $WIMFile.Fullname -Index 1 | Select -ExpandProperty ImageName

        # Search for the Conversion Name
        $FileName = Select-Xml -Xml $XML -XPath "//OperatingSystem[@key='$MDTImageName']" | select -ExpandProperty Node | Select -ExpandProperty Name

        # Search for the Image Name
        $ImageName = Select-Xml -Xml $XML -XPath "//OperatingSystem[@key='$MDTImageName']/ImageName" | select -ExpandProperty Node | Select -ExpandProperty "#text"

        # Get the Source Folder
        $SourceFolder = Select-Xml -Xml $XML -XPath "//OperatingSystem[@key='$MDTImageName']/Source" | select -ExpandProperty Node | Select -ExpandProperty "#text"

        # Copy The Source Content to the Staging Folder
        If(Test-Path $SourceFolder){
            Copy-Item -Path (Join-Path -Path $SourceFolder -ChildPath "\*") -Destination $XML.Configuration.ImageData.StagingFolder -Exclude @('install.wim','*.clg') -Recurse -
        } Else {
            Write-EventLog -EventId 7 -LogName Application -Message "Source Folder Could not be located" -Source SecureDeployment -Category 0 -EntryType Error
            Write-Verbose "Source Folder Could not be located"
            Return
        }

        # Copy the Captured WIM File to the Staging Sources folder
        Export-WindowsImage -SourceImagePath $WIMFile.Fullname -DestinationImagePath (Join-Path $XML.Configuration.ImageData.StagingFolder -ChildPath "sources\install.wim") -SourceName $MDTImageName -DestinationName $ImageName | Out-Null

        # Create the ISO File Name
        $GetDate = Get-Date
        $Today = [string]$($GetDate.Day) + '-' + [string]$($GetDate.Month) + '-' + [string]$($GetDate.Year)
        $ISOFile = (Join-Path $XML.Configuration.ImageData.DestinationFolder -ChildPath ($FileName + " - " + $Today + ".iso" ) )

        # Remove Previous ISO File
        if(Test-Path $ISOFile){
            Remove-Item $ISOFile -Force
        }

        # Instead of pointing to normal efisys.bin, use the *_noprompt instead
        if($XML.Configuration.ImageData.BootPrompt -eq "true"){
            $BootFile = "efisys.bin"
        } Else {
            $BootFile = "efisys_noprompt.bin"
        }

        $BootData='2#p0,e,b"{0}"#pEF,e,b"{1}"' -f "$($XML.Configuration.ImageData.StagingFolder)\boot\etfsboot.com","$($XML.Configuration.ImageData.StagingFolder)\efi\Microsoft\boot\$BootFile"

        # Create the ISO File
        Start-Process -FilePath $($XML.Configuration.ImageData.Oscdimg) -ArgumentList @("-bootdata:$BootData",'-u2','-udfver102',"$($XML.Configuration.ImageData.StagingFolder)","""$ISOFile""") -PassThru -Wait -NoNewWindow

        # Clean the Staging folder
        If(Test-Path $XML.Configuration.ImageData.StagingFolder){
            Remove-Item -Path $XML.Configuration.ImageData.StagingFolder -Recurse -Force
        }

        # Remove the MDT Source WIM File
        if($XML.Configuration.ImageData.RemoveSourceWim -eq "true"){
            Remove-Item $WIMFile.Fullname -Force
        }

        Write-EventLog -EventId 8 -LogName Application -Message "Succesfully created $ISOFile" -Source SecureDeployment -Category 0 -EntryType Information
    }
} Else {
    Write-EventLog -EventId 9 -LogName Application -Message "No WIM Files could be located" -Source SecureDeployment -Category 0 -EntryType Information
    Write-Output "No WIM Files could be located"
    Return
}