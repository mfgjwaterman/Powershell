function Get-WindowsProductKey {
    $WindowsProductKey = (Get-WmiObject -query ‘select * from SoftwareLicensingService’).OA3xOriginalProductKey
    return $WindowsProductKey
}
