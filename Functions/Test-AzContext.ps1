function Test-AzContext {

    switch ( [string]::IsNullOrEmpty( ( Get-AzContext ) ) )
    {
        $false
        {
            Write-Output "You are logged into Azure"
        }
        $true
        {
            Connect-AzAccount
        }
    }

}