function Test-AzContext ([string]$Tenant, [string]$Subscription) {

    switch ( [string]::IsNullOrEmpty( ( Get-AzContext ) ) )
    {
        $false
        {
            Write-Verbose "Authentication to Azure successfully established."
        }
        $true
        {
            Connect-AzAccount   -Tenant $Tenant `
                                -Subscription $Subscription `
                                -ErrorAction Stop
        }
    }
}