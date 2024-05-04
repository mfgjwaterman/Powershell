<#
.Synopsis
   Gets Disk Space of the given remote computer name
.DESCRIPTION
   Get-RemoteComputerDisk cmdlet gets the used, free and total space with the drive name.
.EXAMPLE
   Get-RemoteComputerDisk -RemoteComputerName "abc.contoso.com"
   Drive    UsedSpace(in GB)    FreeSpace(in GB)    TotalSpace(in GB)
   C        75                  52                  127
   D        28                  372                 400

.INPUTS
   Inputs to this cmdlet (if any)
.OUTPUTS
   Output from this cmdlet (if any)
.NOTES
   General notes
.COMPONENT
   The component this cmdlet belongs to
.ROLE
   The role this cmdlet belongs to
.FUNCTIONALITY
   The functionality that best describes this cmdlet
#>
function Get-RemoteComputerDisk
{
    
    Param
    (
        $RemoteComputerName
    )

    Begin
    {
        $output="Drive `t UsedSpace(in GB) `t FreeSpace(in GB) `t TotalSpace(in GB) `n"
    }
    Process
    {
        $drives=Get-WmiObject Win32_LogicalDisk -ComputerName $RemoteComputerName

        foreach ($drive in $drives){
            
            $drivename=$drive.DeviceID
            $freespace=[int]($drive.FreeSpace/1GB)
            $totalspace=[int]($drive.Size/1GB)
            $usedspace=$totalspace - $freespace
            $output=$output+$drivename+"`t`t"+$usedspace+"`t`t`t`t`t`t"+$freespace+"`t`t`t`t`t`t"+$totalspace+"`n"
        }
    }
    End
    {
        return $output
    }
}