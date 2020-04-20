<#
.Synopsis
   Create a Hyper-v virtual machine with parameters derived from a XML configuration file.

.DESCRIPTION
   This script creates a virtual machine on Microsoft Windows Hyper-V with it's configuration
   derived from an XML configuration file. This file must be located next to the script and named
   vmconfig.xml. If the file does not exist an optional parameter can be ommited that contains the
   path to the configuration file.

DYNAMIC PARAMETERS
-OS <String>
        Operating system selection list generated from the configuration file.

-VMSwitch <String> 
        Virtual switch generated from the configuration file.

.Parameter XMLPath
    Path to the XML based configuration file.

.Parameter VMName
    The Name of the Virtual machine.

.Parameter VMStart
    Starts the virtual machine directly after creation.

.Parameter LegacyGeneration
    Creates a generation 1 Virtual machine, overrides the value in the configuration file when the configuration is set to 2.
    Has no effect when the value in the configuration file is set to 1.

.Parameter NoSecureBoot
    Creates a Virtual Machine without SecureBoot enabled, overrides the value in the configuration file.

.Parameter NoVMTPM
    Creates a Virtual Machine without a virtual TPM, overrides the value in the configuration file.

.Example
    New-VMFromFile -OS "Windows 10" -VMSwitch "Default Switch" -VMStart

    Creates a new virtual machine from the disk "Windows 10", connects the virtual switch "Default Switch" and starts the VM after creation.

.Example
    New-VMFromFile -OS "Windows 7" -LegacyGeneration -NoSecureBoot -NoTPM

    Creates a new generation 1, virtual machine without secureboot or a TPM.

#>

[CmdletBinding()]

Param(
    [parameter(Mandatory = $false)]
    [String]$XMLPath,
 
    [parameter(Position = 0, Mandatory = $false)]
    [String]$VMName,

    [parameter(Mandatory = $false)]
    [Switch]$VMStart,

    [parameter(Mandatory = $false)]
    [Switch]$LegacyGeneration,

    [parameter(Mandatory = $false)]
    [Switch]$NoSecureBoot,

    [parameter(Mandatory = $false)]
    [Switch]$NoVMTPM
)
 
DynamicParam {
        
    Write-Verbose "In case the xmlpath is not provided use the default"
    if (!($XMLPath)) {
        $XMLPath = ".\vmconfig.xml"
    }

    Write-Verbose "Read the XML Configuration file ###"
    [XML]$XML = Get-Content -Path $XMLPath

    Write-Verbose "Read and set the store values"
    $ParentDataStore = $XML.Configuration.vmdisks.parentdatastore.path
    $ChildDataStore = $XML.Configuration.vmdisks.childdatastore.path

    Write-Verbose "Get all the operating system disks"
    $BaseNamesArray = $XML | Select-Xml -XPath "//vmdisks/disk" | select -ExpandProperty node | select -ExpandProperty basename

    Write-Verbose "Get all the virtual switches"
    $SwitchNameArray = $XML | Select-Xml -XPath "//vmswitch/switch" | select -ExpandProperty node | select -ExpandProperty name

    Write-Verbose "Set the dynamic parameters name"
    $ParamName_basename = 'OS'

    Write-Verbose "Create the collection of attributes"
    $AttributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
    
    Write-Verbose "Create and set the parameters attributes"
    $ParameterAttribute = New-Object System.Management.Automation.ParameterAttribute
    $ParameterAttribute.Mandatory = $true
    $ParameterAttribute.Position = 1
    $ParameterAttribute.HelpMessage = "This is the help message!"
    
    Write-Verbose "Add the attributes to the attributes collection"
    $AttributeCollection.Add($ParameterAttribute) 
    
    Write-Verbose "Create the dictionary"
    $RuntimeParameterDictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
    
    Write-Verbose "Generate and set the ValidateSet"
    $arrSet = $BaseNamesArray
    $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute($arrSet)    
    
    Write-Verbose "Add the ValidateSet to the attributes collection"
    $AttributeCollection.Add($ValidateSetAttribute)
    
    Write-Verbose "Create and return the dynamic parameter"
    $RuntimeParameter = New-Object System.Management.Automation.RuntimeDefinedParameter($ParamName_basename, [string], $AttributeCollection)
    $RuntimeParameterDictionary.Add($ParamName_basename, $RuntimeParameter)

    Write-Verbose "Set the dynamic parameters name"
    $ParamName_vmswitch = 'VMSwitch'

    Write-Verbose "Create the collection of attributes"
    $AttributeCollection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]

    Write-Verbose "Create and set the parameters attributes"
    $ParameterAttribute = New-Object System.Management.Automation.ParameterAttribute
    $ParameterAttribute.Mandatory = $false
    $ParameterAttribute.Position = 2

    Write-Verbose "Add the attributes to the attributes collection"
    $AttributeCollection.Add($ParameterAttribute)  

    Write-Verbose "Generate and set the ValidateSet"
    $arrSet = $SwitchNameArray
    $ValidateSetAttribute = New-Object System.Management.Automation.ValidateSetAttribute($arrSet)

    Write-Verbose "Add the ValidateSet to the attributes collection"
    $AttributeCollection.Add($ValidateSetAttribute)

    Write-Verbose "Create and return the dynamic parameter"
    $RuntimeParameter = New-Object System.Management.Automation.RuntimeDefinedParameter($ParamName_vmswitch, [string], $AttributeCollection)
    $RuntimeParameterDictionary.Add($ParamName_vmswitch, $RuntimeParameter)
    
    Write-Verbose "return the variable to be used as parameters"
    return $RuntimeParameterDictionary
}

begin {
    Write-Verbose "Default error action"
    $ErrorActionPreference = "Stop"

    Write-Verbose "Set the variables"
    $OS = $PSBoundParameters.OS
    $VMSwitch = $PSBoundParameters.VMSwitch
    $extension = $XML | Select-Xml -XPath "//*[@basename='$OS']" | Select-Object -ExpandProperty node | Select-Object -ExpandProperty extension
    $vhdfilename = $XML | Select-Xml -XPath "//*[@basename='$OS']" | Select-Object -ExpandProperty node | Select-Object -ExpandProperty filename
    $ParentVHDX = Join-Path $ParentDataStore ($vhdfilename + "." + $extension)
    $ChildVHDX = Join-Path -Path $ChildDataStore -ChildPath (((New-Guid).Guid) + ".vhdx")
    $MemoryStartupBytes = $xml.Configuration.vmconfig.MemoryStartupBytes

    if ($LegacyGeneration) {
        $Generation = 1
    }
    else {
        $Generation = $xml.Configuration.vmconfig.generation
    }

    $vmprocessorcount = $xml.Configuration.vmconfig.vmprocessorcount
    $MinimumBytes = $xml.Configuration.vmconfig.MinimumBytes
    $MaximumBytes = $xml.Configuration.vmconfig.MaximumBytes
    $AutomaticCheckpointsEnabled = [System.Convert]::ToBoolean($xml.Configuration.vmconfig.AutomaticCheckpointsEnabled)
    $GuestServiceInterface = [System.Convert]::ToBoolean($xml.Configuration.vmconfig.GuestServiceInterface)
    $AddVMDvdDrive = [System.Convert]::ToBoolean($xml.Configuration.vmconfig.AddVMDvdDrive)
    $EnableVMTPM = [System.Convert]::ToBoolean($xml.Configuration.vmconfig.EnableVMTPM)

    if (!($NoSecureBoot)) {
        $EnableSecureBoot = [System.Convert]::ToBoolean($xml.Configuration.vmconfig.EnableSecureBoot)
        $SecureBootTemplate = $xml.Configuration.vmconfig.SecureBootTemplate
    }

}

Process {
    
    Write-Verbose "Create the Virtual Disk"
    $VDISK = New-VHD -Path $ChildVHDX -ParentPath $ParentVHDX -Differencing
    $VHDPath = $VDISK.Path
    
    Write-Verbose "Create the Virtual Machine"
    $VM = New-VM -Generation $Generation -VHDPath $VHDPath

    Write-Verbose "Set the Virtual Switch"
    if ($VMSwitch) {
        Connect-VMNetworkAdapter -VMName ($VM.Name) -SwitchName $VMSwitch
    }

    Write-Verbose "Rename the Virtual Machine"
    if ($VMName) {
        Rename-VM -VM $VM -NewName $VMName
    }

    Write-Verbose "Set the Number of virtual processors"
    if ($vmprocessorcount) {
        Set-VM -VM $VM -ProcessorCount $vmprocessorcount
    }
    
    Write-Verbose "Set the startup memory"
    if ($MemoryStartupBytes) {
        set-vm -VM $VM -MemoryStartupBytes ($MemoryStartupBytes / 1)
    }

    Write-Verbose "Set the minimum memory"
    if ($MinimumBytes) {
        Set-VM $vm -DynamicMemory:$true -MemoryMinimumBytes ($MinimumBytes / 1)
    }

    Write-Verbose "Set the maximum memory"
    if ($MaximumBytes) {
        Set-VM $vm -DynamicMemory:$true -MemoryMaximumBytes ($MaximumBytes / 1)
    }

    Write-Verbose "Configure automatic CheckPoint Creation"
    if ($AutomaticCheckpointsEnabled) {
        Set-VM -VM $vm -AutomaticCheckpointsEnabled:$true
    }
    else {
        Set-VM -VM $vm -AutomaticCheckpointsEnabled:$false
    }

    Write-Verbose "Configure Guest Integration Services"
    if ($GuestServiceInterface) {
        Enable-VMIntegrationService -VM $vm -Name "Guest Service Interface"
    }
    else {
        Disable-VMIntegrationService -VM $vm -Name "Guest Service Interface"
    }

    Write-Verbose "Configure the DVD drive"
    if ($Generation -eq 2) {
        if ($AddVMDvdDrive) {
            Add-VMDvdDrive -VM $vm
        }    
    }

    Write-Verbose "Configure the Virtual TPM"
    if ($Generation -eq 2) {
        If (!($NoVMTPM)) {
            if ($EnableVMTPM) {
                $UntrustedGuardian = Get-HgsGuardian -Name UntrustedGuardian -ErrorAction SilentlyContinue

                If (!$UntrustedGuardian) {
                    $UntrustedGuardian = New-HgsGuardian -Name UntrustedGuardian –GenerateCertificates
                }

                $Owner = Get-HgsGuardian -Name "UntrustedGuardian"
                $KeyProtector = New-HgsKeyProtector -Owner $Owner -AllowUntrustedRoot
                Set-VMKeyProtector -VM $vm -KeyProtector $KeyProtector.RawData
                Enable-VMTPM -VM $vm
            }
        }
    }

    Write-Verbose "Configure SecureBoot"
    if ($Generation -eq 2) {
        if ($EnableSecureBoot) {
            Set-VMFirmware -VM $vm -EnableSecureBoot On -SecureBootTemplate $SecureBootTemplate
        }
        else {
            Set-VMFirmware -VM $vm -EnableSecureBoot Off
        }    
    }

    Write-Verbose "Start the VM"
    if ($VMStart) {
        Start-VM -VM $vm
    }
    
}

end {}

