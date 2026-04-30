#requires -RunAsAdministrator

<#
.SYNOPSIS
Creates or recreates a Hyper-V virtual machine from a source VHDX with optional configuration.

.DESCRIPTION
This script creates a Hyper-V virtual machine using a provided or selected base VHDX file.
The source disk is copied to the default Hyper-V virtual hard disk location and renamed 
using the format "<VMName> - Disk_0.vhdx".

If a virtual machine and/or destination VHDX with the same name already exists, the script 
will prompt to remove the existing resources before continuing.

The script supports additional configuration such as:
- Default assignment of 4 virtual processors
- Optional Dynamic Memory (minimum 1GB, maximum equals startup memory)
- Optional virtual switch selection (interactive if not provided)
- Optional VLAN assignment
- Optional TPM (Generation 2 only, including automatic key protector configuration)
- Enabling all integration services

The VM name is automatically converted to uppercase for consistency.

.PARAMETER VMName
Specifies the name of the virtual machine. The name will be converted to uppercase.

.PARAMETER SourceVhdxPath
Specifies the full path to the source VHDX file. If not provided, the script will prompt 
to select a VHDX from the BaseDiskFolder.

.PARAMETER BaseDiskFolder
Specifies the folder containing base VHDX files. Used when SourceVhdxPath is not provided.

.PARAMETER MemoryStartupBytes
Specifies the startup memory for the VM. Also used as the maximum memory when Dynamic Memory is enabled.
Default is 4GB.

.PARAMETER ProcessorCount
Specifies the number of virtual processors assigned to the VM. Default is 4.

.PARAMETER Generation
Specifies the VM generation (1 or 2). TPM requires Generation 2. Default is 2.

.PARAMETER SwitchName
Specifies the name of the virtual switch. If not provided, an interactive selection is shown.

.PARAMETER EnableTPM
Enables a virtual TPM on the VM. A local key protector will be configured automatically.

.PARAMETER VlanId
Specifies a VLAN ID for the VM network adapter. Requires a virtual switch.

.PARAMETER EnableDynamicMemory
Enables Dynamic Memory with a minimum of 1GB and a maximum equal to the startup memory.

.EXAMPLE
.\New-VirtualMachineFromSource.ps1 `
    -VMName "dc01" `
    -SourceVhdxPath "D:\BaseImages\WinServer2025.vhdx" `
    -SwitchName "LabSwitch" `
    -EnableTPM `
    -EnableDynamicMemory

Creates a VM named DC01 with TPM and Dynamic Memory enabled.

.EXAMPLE
.\New-VirtualMachineFromSource.ps1 `
    -VMName "srv01" `
    -BaseDiskFolder "D:\BaseImages" `
    -SwitchName "LabSwitch" `
    -VlanId 10

Prompts for a VHDX selection and creates a VM connected to a virtual switch with VLAN ID 10.

.NOTES
Author: Michael Waterman
Requires: Hyper-V PowerShell module
#>

param (
    [Parameter(Mandatory)]
    [ValidateScript({ $_ -match '^[a-zA-Z0-9\-]+$' })]
    [string]$VMName,

    [Parameter()]
    [string]$BaseDiskFolder = "E:\VM Templates",

    [Parameter()]
    [string]$SourceVhdxPath,

    [Parameter()]
    [int64]$MemoryStartupBytes = 4GB,

    [Parameter()]
    [switch]$EnableDynamicMemory,

    [Parameter()]
    [int]$ProcessorCount = 4,

    [Parameter()]
    [ValidateSet(1, 2)]
    [int]$Generation = 2,

    [Parameter()]
    [string]$SwitchName,

    [Parameter()]
    [switch]$EnableTPM,

    [Parameter()]
    [ValidateRange(1, 4094)]
    [int]$VlanId
)

function Confirm-YesNo {
    param (
        [Parameter(Mandatory)]
        [string]$Message
    )

    do {
        $answer = Read-Host "$Message (Y/N)"
    } until ($answer -match '^[YyNn]$')

    return ($answer -match '^[Yy]$')
}

function Stop-VMIfNeeded {
    param (
        [Parameter(Mandatory)]
        [Microsoft.HyperV.PowerShell.VirtualMachine]$VM
    )

    if ($VM.State -ne 'Off') {
        Write-Host "VM is currently $($VM.State). Stopping VM: $($VM.Name)"
        Stop-VM -Name $VM.Name -Force
    }
    else {
        Write-Host "VM is already stopped: $($VM.Name)"
    }
}

function Remove-ExistingVM {
    param (
        [Parameter(Mandatory)]
        [string]$VMName
    )

    $existingVM = Get-VM -Name $VMName -ErrorAction SilentlyContinue

    if ($existingVM) {
        Stop-VMIfNeeded -VM $existingVM

        Write-Host "Removing existing VM: $VMName"
        Remove-VM -Name $VMName -Force
    }
}

$VMName = $VMName.ToUpper()

$vmHost = Get-VMHost
$destinationFolder = $vmHost.VirtualHardDiskPath
$destinationVhdxPath = Join-Path $destinationFolder "$VMName - Disk_0.vhdx"

if (-not $SourceVhdxPath) {
    $availableDisks = @(Get-ChildItem -Path $BaseDiskFolder -Filter "*.vhdx" -File -Recurse)

    if (-not $availableDisks) {
        throw "No VHDX files found in: $BaseDiskFolder"
    }

    Write-Host "Available source disks:"

    for ($i = 0; $i -lt $availableDisks.Count; $i++) {
        Write-Host "[$($i + 1)] $($availableDisks[$i].Name)"
    }

    do {
        $selection = Read-Host "Select source disk"
    } until (
        [int]::TryParse($selection, [ref]$null) -and
        [int]$selection -ge 1 -and
        [int]$selection -le $availableDisks.Count
    )

    $SourceVhdxPath = $availableDisks[[int]$selection - 1].FullName
}

if (-not (Test-Path $SourceVhdxPath)) {
    throw "Source VHDX not found: $SourceVhdxPath"
}

if (-not (Test-Path $destinationFolder)) {
    throw "Default Hyper-V virtual disk folder not found: $destinationFolder"
}

$existingVM = Get-VM -Name $VMName -ErrorAction SilentlyContinue
$existingDisk = Test-Path $destinationVhdxPath

if ($existingVM -or $existingDisk) {
    if ($existingVM) {
        Write-Warning "A VM with the name '$VMName' already exists."
    }

    if ($existingDisk) {
        Write-Warning "A VHDX with this name already exists: $destinationVhdxPath"
    }

    Write-Warning "If you continue, the existing VM and/or VHDX will be removed."

    $confirmRecreate = Confirm-YesNo -Message "Do you want to remove the existing VM and/or VHDX and continue?"

    if (-not $confirmRecreate) {
        throw "Operation cancelled. Existing VM and/or disk were not removed."
    }

    if ($existingVM) {
        Remove-ExistingVM -VMName $VMName
    }

    if ($existingDisk) {
        Write-Host "Removing existing VHDX: $destinationVhdxPath"
        Remove-Item -Path $destinationVhdxPath -Force
    }
}

$switches = @(Get-VMSwitch)

if ($SwitchName) {
    $selectedSwitch = $switches | Where-Object { $_.Name -eq $SwitchName }

    if (-not $selectedSwitch) {
        throw "Virtual switch '$SwitchName' was not found on this host."
    }
}
else {
    if (-not $switches) {
        throw "No virtual switches found on this host."
    }

    Write-Host "Available virtual switches:"

    for ($i = 0; $i -lt $switches.Count; $i++) {
        Write-Host "[$($i + 1)] $($switches[$i].Name) ($($switches[$i].SwitchType))"
    }

    Write-Host "[0] No switch"

    do {
        $selection = Read-Host "Select virtual switch"
    } until (
        [int]::TryParse($selection, [ref]$null) -and
        [int]$selection -ge 0 -and
        [int]$selection -le $switches.Count
    )

    if ([int]$selection -ne 0) {
        $SwitchName = $switches[[int]$selection - 1].Name
    }
}

if ($PSBoundParameters.ContainsKey('VlanId') -and -not $SwitchName) {
    throw "A VLAN ID can only be configured when a virtual switch is assigned."
}

Write-Host "Copying disk to: $destinationVhdxPath"
Copy-Item -Path $SourceVhdxPath -Destination $destinationVhdxPath

$newVmParams = @{
    Name               = $VMName
    MemoryStartupBytes = $MemoryStartupBytes
    Generation         = $Generation
    VHDPath            = $destinationVhdxPath
}

if ($SwitchName) {
    $newVmParams.SwitchName = $SwitchName
}

Write-Host "Creating VM: $VMName"
New-VM @newVmParams | Out-Null

if ($EnableDynamicMemory) {
    Write-Host "Enabling Dynamic Memory"

    Set-VMMemory `
        -VMName $VMName `
        -DynamicMemoryEnabled $true `
        -MinimumBytes 1GB `
        -StartupBytes $MemoryStartupBytes `
        -MaximumBytes $MemoryStartupBytes
}
else {
    Write-Host "Disabling Dynamic Memory"

    Set-VMMemory `
        -VMName $VMName `
        -DynamicMemoryEnabled $false `
        -StartupBytes $MemoryStartupBytes
}

Write-Host "Setting processor count to $ProcessorCount"
Set-VMProcessor -VMName $VMName -Count $ProcessorCount

Write-Host "Enabling all integration services"
Get-VMIntegrationService -VMName $VMName | Enable-VMIntegrationService

if ($EnableTPM) {
    if ($Generation -ne 2) {
        throw "TPM can only be enabled on a Generation 2 VM."
    }

    Write-Host "Configuring key protector for TPM"
    Set-VMKeyProtector -VMName $VMName -NewLocalKeyProtector

    Write-Host "Enabling TPM"
    Enable-VMTPM -VMName $VMName
}

if ($PSBoundParameters.ContainsKey('VlanId')) {
    Write-Host "Configuring VLAN ID $VlanId"
    Set-VMNetworkAdapterVlan -VMName $VMName -Access -VlanId $VlanId
}

Write-Host "VM '$VMName' created successfully."