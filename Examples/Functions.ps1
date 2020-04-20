function MyFunction (
    
[parameter(Mandatory = $true)]
[int]$param1)

{
    $Param2 = $param1 + 1
    $Result = $true
    return $Result, $Param2
}

$Result = MyFunction(100)
Write-host "Array members: " $Result
Write-host "Array member 1: " $Result[0]
Write-host "Array member 2: " $Result[1]
$Result.GetType()