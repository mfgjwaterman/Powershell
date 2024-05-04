Param(
[Parameter(Mandatory=$true)]
$vhdxfilespath = "D:\Hyper-V\Virtual Parent Disks"
)

if(-not(Test-Path $vhdxfilespath )){
    Throw "You must supply a valid value for -drive"
}

$vhdxfiles = Get-childItem -Path $vhdxfilespath -Filter *.vhdx

ForEach ($vhdxfile in $vhdxfiles){
    Optimize-VHD -Path $vhdxfile.fullname -Mode Full -Verbose
}