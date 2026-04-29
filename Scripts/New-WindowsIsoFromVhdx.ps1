<#
.SYNOPSIS
Creates a bootable Windows installation ISO from a generalized Windows installation inside a VHDX.

.DESCRIPTION
This script mounts a VHDX, detects the Windows partition, captures the Windows installation
to install.wim using DISM, copies the contents of a source Windows ISO to a staging folder,
replaces the original install.wim/install.esd with the captured WIM, and creates a new
bootable ISO using oscdimg.

Typical use case:
- Build and sysprep a Windows image with Packer on Hyper-V
- Use the resulting VHDX as source
- Capture the Windows installation to install.wim
- Create bootable Windows installation media

The script supports both BIOS and UEFI bootable media by using oscdimg bootdata.

.NOTES
Author: Michael Waterman
Purpose: Convert a sysprepped VHDX-based Windows image into bootable installation media
Requirements:
- Run as Administrator
- Hyper-V PowerShell module available for Mount-VHD / Dismount-VHD
- Windows ADK Deployment Tools installed for oscdimg.exe
- DISM available
- Source Windows ISO available

Important:
- The VHDX should contain a generalized Windows installation.
- The source ISO should match the same Windows family as the captured image.
- For automated VM installs, efisys_noprompt.bin is usually preferred.

.EXAMPLE
.\New-WindowsIsoFromVhdx.ps1 `
  -VhdxPath "E:\IAC\output\ws2025\Virtual Hard Disks\ws2025.vhdx" `
  -SourceIsoPath "E:\ISO\Windows_Server_2025.iso" `
  -OutputIsoPath "E:\ISO\Custom\Windows_Server_2025_Custom.iso" `
  -StagingPath "E:\Staging\WS2025ISO" `
  -ImageName "Windows Server 2025 Datacenter Core - Custom" `
  -ImageDescription "Windows Server 2025 Datacenter Core captured from Hyper-V Packer image" `
  -Compression Max `
  -NoPromptBoot
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ })]
    [string]$VhdxPath,

    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ })]
    [string]$SourceIsoPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputIsoPath,

    [Parameter(Mandatory = $true)]
    [string]$StagingPath,

    [Parameter(Mandatory = $false)]
    [string]$WorkPath = "C:\Windows\Temp\WindowsIsoBuild",

    [Parameter(Mandatory = $false)]
    [string]$ImageName = "Custom Windows Image",

    [Parameter(Mandatory = $false)]
    [string]$ImageDescription = "Custom Windows image captured from VHDX",

    [Parameter(Mandatory = $false)]
    [ValidateSet("None","Fast","Max","Recovery")]
    [string]$Compression = "Fast",

    [Parameter(Mandatory = $false)]
    [switch]$CheckIntegrity = $false,

    [Parameter(Mandatory = $false)]
    [string]$OscdimgPath,

    [Parameter(Mandatory = $false)]
    [switch]$NoPromptBoot,

    [Parameter(Mandatory = $false)]
    [switch]$KeepWorkFiles = $false
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------
# Logging
# ---------------------------------------------------------
$LogDir = Join-Path $WorkPath "Logs"

function Initialize-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DirectoryPath,

        [switch]$Clean
    )

    if ((Test-Path $DirectoryPath) -and $Clean) {
        Remove-Item -Path $DirectoryPath -Recurse -Force
    }

    if (-not (Test-Path $DirectoryPath)) {
        New-Item -Path $DirectoryPath -ItemType Directory -Force | Out-Null
    }
}

Initialize-Directory -DirectoryPath $WorkPath
Initialize-Directory -DirectoryPath $LogDir

$LogFile = Join-Path $LogDir "New-WindowsIsoFromVhdx.log"

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO","WARN","ERROR")]
        [string]$Level = "INFO"
    )

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $entry = "[$timestamp] [$Level] $Message"

    Add-Content -Path $LogFile -Value $entry

    switch ($Level) {
        "ERROR" { Write-Error $Message }
        "WARN"  { Write-Warning $Message }
        default { Write-Output $Message }
    }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Resolve-Oscdimg {
    param(
        [string]$ProvidedPath
    )

    if ($ProvidedPath) {
        if (Test-Path $ProvidedPath) {
            return (Resolve-Path $ProvidedPath).Path
        }

        throw "Provided OscdimgPath does not exist: $ProvidedPath"
    }

    $cmd = Get-Command oscdimg.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $knownPaths = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
        "${env:ProgramFiles(x86)}\Windows Kits\11\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
        "${env:ProgramFiles}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
        "${env:ProgramFiles}\Windows Kits\11\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
    )

    foreach ($path in $knownPaths) {
        if (Test-Path $path) {
            return $path
        }
    }

    throw "oscdimg.exe could not be found. Install the Windows ADK Deployment Tools or specify -OscdimgPath."
}

function Get-WindowsVolumeFromMountedVhd {
    param(
        [Parameter(Mandatory = $true)]
        [Microsoft.Vhd.PowerShell.VirtualHardDisk]$MountedVhd
    )

    $disk = $MountedVhd | Get-Disk

    Write-Log "Mounted VHDX detected as disk number: $($disk.Number)"

    $partitions = Get-Partition -DiskNumber $disk.Number | Where-Object {
        $_.Type -eq "Basic"
    }

    foreach ($partition in $partitions) {
        $volume = $partition | Get-Volume -ErrorAction SilentlyContinue

        if (-not $volume -or $volume.FileSystem -ne "NTFS") {
            continue
        }

        $driveLetter = $volume.DriveLetter
        $temporaryLetterAssigned = $false

        if (-not $driveLetter) {
            Write-Log "Partition $($partition.PartitionNumber) has no drive letter. Assigning temporary drive letter."

            $usedLetters = Get-Volume |
                Where-Object { $_.DriveLetter } |
                Select-Object -ExpandProperty DriveLetter

            $freeLetter = [char[]](90..68) |
                Where-Object { $_ -notin $usedLetters } |
                Select-Object -First 1

            if (-not $freeLetter) {
                throw "No free drive letter available to inspect partition $($partition.PartitionNumber)."
            }

            Set-Partition `
                -DiskNumber $disk.Number `
                -PartitionNumber $partition.PartitionNumber `
                -NewDriveLetter $freeLetter `
                -ErrorAction Stop

            $driveLetter = $freeLetter
            $temporaryLetterAssigned = $true

            Start-Sleep -Seconds 1
        }

        $windowsSystemHive = "{0}:\Windows\System32\Config\SYSTEM" -f $driveLetter

        if (Test-Path $windowsSystemHive) {
            Write-Log "Windows partition found: Disk $($disk.Number), Partition $($partition.PartitionNumber), Drive $driveLetter`:"

            if ($partition.NoDefaultDriveLetter) {
                Write-Log "NoDefaultDriveLetter is True on Windows partition. Setting it to False."

                Set-Partition `
                    -DiskNumber $disk.Number `
                    -PartitionNumber $partition.PartitionNumber `
                    -NoDefaultDriveLetter $false `
                    -ErrorAction Stop

                Write-Log "NoDefaultDriveLetter set to False."
            }
            else {
                Write-Log "NoDefaultDriveLetter is already False."
            }

            return Get-Volume -DriveLetter $driveLetter
        }

        if ($temporaryLetterAssigned) {
            Write-Log "Partition $($partition.PartitionNumber) is not the Windows partition. Removing temporary drive letter $driveLetter`:"

            Remove-PartitionAccessPath `
                -DiskNumber $disk.Number `
                -PartitionNumber $partition.PartitionNumber `
                -AccessPath "$driveLetter`:\"
        }
    }

    throw "Could not locate a Windows installation partition in mounted VHDX."
}

function Mount-SourceIso {
    param(
        [Parameter(Mandatory = $true)]
        [string]$IsoPath
    )

    Write-Log "Mounting source ISO: $IsoPath"
    $diskImage = Mount-DiskImage -ImagePath $IsoPath -PassThru
    Start-Sleep -Seconds 2

    $volume = $diskImage | Get-Volume | Where-Object { $_.DriveLetter } | Select-Object -First 1
    if (-not $volume) {
        throw "Could not determine drive letter for mounted ISO."
    }

    return @{
        DiskImage = $diskImage
        DriveRoot = ("{0}:\" -f $volume.DriveLetter)
    }
}

function Copy-IsoContentToStaging {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceRoot,

        [Parameter(Mandatory = $true)]
        [string]$DestinationRoot
    )

    Write-Log "Preparing staging folder: $DestinationRoot"
    Initialize-Directory -DirectoryPath $DestinationRoot -Clean

    Write-Log "Copying source ISO contents to staging folder..."
    robocopy $SourceRoot $DestinationRoot /E /NFL /NDL /NJH /NJS /NP | Out-Null

    $exitCode = $LASTEXITCODE
    if ($exitCode -gt 7) {
        throw "Robocopy failed with exit code $exitCode."
    }

    Write-Log "Source ISO content copied to staging folder."

    $oldInstallWim = Join-Path $DestinationRoot "sources\install.wim"
    $oldInstallEsd = Join-Path $DestinationRoot "sources\install.esd"

    if (Test-Path $oldInstallWim) {
        Remove-Item -Path $oldInstallWim -Force
        Write-Log "Removed original install.wim from staging."
    }

    if (Test-Path $oldInstallEsd) {
        Remove-Item -Path $oldInstallEsd -Force
        Write-Log "Removed original install.esd from staging."
    }
}

function Capture-WindowsImage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CapturePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationWim,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [ValidateSet("None","Fast","Max","Recovery")]
        [string]$CompressionType,

        [Parameter(Mandatory = $false)]
        [switch]$CheckIntegrity
    )

    Write-Log "Capturing Windows image from $CapturePath to $DestinationWim"

    # Normalize compression casing
    $CompressionType = $CompressionType.Substring(0,1).ToUpper() + $CompressionType.Substring(1).ToLower()

    # DISM is picky. For root paths, use F:\ but pass it quoted.
    $normalizedCapturePath = $CapturePath

    $argumentParts = @(
        "/Capture-Image"
        ('/ImageFile:"{0}"' -f $DestinationWim)
        ('/CaptureDir:{0}' -f $normalizedCapturePath)
        ('/Name:"{0}"' -f $Name)
        ('/Description:"{0}"' -f $Description)
        ('/Compress:{0}' -f $CompressionType)
    )

    if ($CheckIntegrity) {
        $argumentParts += "/CheckIntegrity"
    }

    $argumentString = $argumentParts -join " "

    Write-Log ("Running DISM command: dism.exe {0}" -f $argumentString)

    $process = Start-Process `
        -FilePath "dism.exe" `
        -ArgumentList $argumentString `
        -Wait `
        -PassThru `
        -NoNewWindow

    if ($process.ExitCode -ne 0) {
        throw "DISM capture failed with exit code $($process.ExitCode)."
    }

    Write-Log "DISM capture completed successfully."
}

function Write-InstallWimHash {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallWimPath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationHashPath
    )

    Write-Log "Creating hash file for install.wim."

    $today = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "File created on: $today" | Out-File -FilePath $DestinationHashPath -Force -Encoding utf8
    Get-FileHash -Path $InstallWimPath -Algorithm SHA256 |
        Select-Object Algorithm, Hash |
        Out-File -FilePath $DestinationHashPath -Append -Encoding utf8

    Write-Log "Hash file created: $DestinationHashPath"
}

function New-BootableIso {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Oscdimg,

        [Parameter(Mandatory = $true)]
        [string]$IsoRoot,

        [Parameter(Mandatory = $true)]
        [string]$DestinationIso,

        [switch]$UseNoPromptBoot
    )

    $etfsBoot = Join-Path $IsoRoot "boot\etfsboot.com"

    if ($UseNoPromptBoot) {
        $efiBoot = Join-Path $IsoRoot "efi\Microsoft\boot\efisys_noprompt.bin"
    }
    else {
        $efiBoot = Join-Path $IsoRoot "efi\Microsoft\boot\efisys.bin"
    }

    if (-not (Test-Path $etfsBoot)) {
        throw "BIOS boot file not found: $etfsBoot"
    }

    if (-not (Test-Path $efiBoot)) {
        throw "UEFI boot file not found: $efiBoot"
    }

    $destinationFolder = Split-Path -Path $DestinationIso -Parent
    Initialize-Directory -DirectoryPath $destinationFolder

    if (Test-Path $DestinationIso) {
        Remove-Item -Path $DestinationIso -Force
    }

    $bootData = '2#p0,e,b"{0}"#pEF,e,b"{1}"' -f $etfsBoot, $efiBoot

    Write-Log "Creating bootable ISO: $DestinationIso"
    Write-Log "Using boot data: $bootData"

    $arguments = @(
        "-bootdata:$bootData",
        "-u2",
        "-udfver102",
        "-m",
        "-o",
        "`"$IsoRoot`"",
        "`"$DestinationIso`""
    )

    $process = Start-Process -FilePath $Oscdimg -ArgumentList $arguments -Wait -PassThru -NoNewWindow

    if ($process.ExitCode -ne 0) {
        throw "oscdimg failed with exit code $($process.ExitCode)."
    }

    Write-Log "Bootable ISO created successfully: $DestinationIso"
}

# ---------------------------------------------------------
# Main
# ---------------------------------------------------------
Write-Log "=== Windows ISO creation from VHDX started ==="

if (-not (Test-IsAdministrator)) {
    Write-Log "This script must be run as Administrator." "ERROR"
    exit 1
}

$mountedVhd = $null
$mountedIso = $null
$success = $false

try {
    $resolvedVhdx = (Resolve-Path $VhdxPath).Path
    $resolvedSourceIso = (Resolve-Path $SourceIsoPath).Path
    $resolvedOscdimg = Resolve-Oscdimg -ProvidedPath $OscdimgPath

    Write-Log "VHDX path: $resolvedVhdx"
    Write-Log "Source ISO path: $resolvedSourceIso"
    Write-Log "Output ISO path: $OutputIsoPath"
    Write-Log "Staging path: $StagingPath"
    Write-Log "Work path: $WorkPath"
    Write-Log "oscdimg path: $resolvedOscdimg"

    Initialize-Directory -DirectoryPath $WorkPath
    Initialize-Directory -DirectoryPath $StagingPath -Clean

    $wimPath = Join-Path $WorkPath "install.wim"

    if (Test-Path $wimPath) {
        Remove-Item -Path $wimPath -Force
    }

    Write-Log "Mounting VHDX..."
    $mountedVhd = Mount-VHD -Path $resolvedVhdx -PassThru
    Start-Sleep -Seconds 2

    $windowsVolume = Get-WindowsVolumeFromMountedVhd -MountedVhd $mountedVhd
    $captureRoot = "{0}:\" -f $windowsVolume.DriveLetter

    Write-Log ("Detected Windows volume: {0}" -f $captureRoot)

    Capture-WindowsImage `
        -CapturePath $captureRoot `
        -DestinationWim $wimPath `
        -Name $ImageName `
        -Description $ImageDescription `
        -CompressionType $Compression `
        -CheckIntegrity:$CheckIntegrity

    Write-Log "Mounting source Windows ISO..."
    $mountedIso = Mount-SourceIso -IsoPath $resolvedSourceIso

    Copy-IsoContentToStaging `
        -SourceRoot $mountedIso.DriveRoot `
        -DestinationRoot $StagingPath

    $targetInstallWim = Join-Path $StagingPath "sources\install.wim"
    Copy-Item -Path $wimPath -Destination $targetInstallWim -Force
    Write-Log "Captured install.wim copied to staging sources folder."

    $hashPath = Join-Path $StagingPath "sources\install-source.hash"
    Write-InstallWimHash -InstallWimPath $targetInstallWim -DestinationHashPath $hashPath

    New-BootableIso `
        -Oscdimg $resolvedOscdimg `
        -IsoRoot $StagingPath `
        -DestinationIso $OutputIsoPath `
        -UseNoPromptBoot:$NoPromptBoot

    $success = $true
    Write-Log "=== Windows ISO creation from VHDX completed successfully ==="
    exit 0
}
catch {
    Write-Log ("Windows ISO creation from VHDX failed: {0}" -f $_.Exception.Message) "ERROR"
    exit 1
}
finally {
    if ($mountedIso) {
        try {
            Write-Log "Dismounting source ISO..."
            Dismount-DiskImage -ImagePath $resolvedSourceIso -ErrorAction SilentlyContinue
            Write-Log "Source ISO dismounted."
        }
        catch {
            Write-Log ("Failed to dismount source ISO: {0}" -f $_.Exception.Message) "WARN"
        }
    }

    if ($mountedVhd) {
        try {
            Write-Log "Dismounting VHDX..."
            Dismount-VHD -Path $resolvedVhdx -ErrorAction SilentlyContinue
            Write-Log "VHDX dismounted."
        }
        catch {
            Write-Log ("Failed to dismount VHDX: {0}" -f $_.Exception.Message) "WARN"
        }
    }

    if (-not $KeepWorkFiles -and $success) {
        try {
            if (Test-Path $StagingPath) {
                Write-Log "Removing StagingPath: $StagingPath"
                Remove-Item -Path $StagingPath -Recurse -Force -ErrorAction Stop
            }

            if (Test-Path $WorkPath) {
                Write-Log "Removing WorkPath: $WorkPath"
                Remove-Item -Path $WorkPath -Recurse -Force -ErrorAction Stop
            }
        }
        catch {
            Write-Warning ("Failed to remove temporary directories: {0}" -f $_.Exception.Message)
        }
    }
}
