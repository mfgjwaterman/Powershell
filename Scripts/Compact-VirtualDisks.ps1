#Requires -RunAsAdministrator

<#PSScriptInfo
    .VERSION 1.0
    .GUID 138c1d25-5e80-4118-9cdb-3e5aa185380e
    .AUTHOR Michael Waterman
    .COMPANYNAME None
    .COPYRIGHT
    .TAGS Hyper-v, vhd, vhdx, compact
#>

<#
    .SYNOPSIS
    Compact vhdx virtual disk files.

    .DESCRIPTION
    This script list alls VMs and attached disks and compacts them. At the end it will display the 
    gained disk space.     

    .EXAMPLE
    Compact-VirtualDisks.ps1
    Obtain all local VMs, obtain all virtual disks and compact them. 

    .NOTES
    AUTHOR: Michael Waterman
    Blog: https://michaelwaterman.nl
    LASTEDIT: 2024.06.13

#>

# Get all the virtual machines
$VirtualMachines = Get-VM

foreach($VirtualMachine in $VirtualMachines){
    
    # Stop the machine if running
    If( $VirtualMachine.State -eq "Running"){
        $State = "Running"
        Stop-VM -Name $VirtualMachine.VMName -Force
        while ((get-vm -name $VirtualMachine.VMName).state -ne 'Off'){
            start-sleep -s 5
        }
    } Else {
        $State = $null
    }
    
    # Get all the Virtual Disks
    $VirtualDisks = Get-VMHardDiskDrive -VMName $VirtualMachine.name

    # Compact the virtual disks
    foreach($VirtualDisk in $VirtualDisks){
        #get the initial size of the disk
        $PreSize = (Get-Item -Path $VirtualDisk.Path).Length/1mb
        
        # Compact the disk
        Optimize-VHD -Path $VirtualDisk.Path -Mode Full -Verbose
        
        # Get the new disk size
        $PostSize = (Get-Item -Path $VirtualDisk.Path).Length/1mb
        
        # Calculate the size difference
        $SizeDiff = $PreSize - $PostSize
    }

    # Start the VM again if it was running before maintenance
    If($State -eq "Running"){
        Start-VM $VirtualMachine.VMName
        while ((get-vm -name $VirtualMachine.VMName).state -ne 'Running') { start-sleep -s 5 }
    }

    # Reset variables
    $SavedDiskSpace += $SizeDiff
    $PreSize = $null
    $PostSize = $null
    $SizeDiff = $null
    $State = $null
}

# Display the difference in Gigabytes
Write-Host -ForegroundColor Green "Saved diskspace: $([math]::Round($SavedDiskSpace/1024,2)) Gigabyte"