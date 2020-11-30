function Test-AzContext ([string]$Tenant, [string]$Subscription) {

$ErrorActionPreference = "Stop"

    switch ( [string]::IsNullOrEmpty( ( Get-AzContext ) ) )
    {
        # There's already an Azure authenticated connection
        $false
        {
            switch ([string]::IsNullOrEmpty( ( $Tenant ) )) {
                $false { 
                    switch ( (Get-AzContext).Tenant.Id.ToLower().Equals( ($Tenant).ToLower() ) ) {
                        $false { Write-Error "Tenant ID mismatch, please provide the correct id or assume correct Tenant selection" }
                    }
                  }
            }

            switch ([string]::IsNullOrEmpty( ( $Subscription ) )) {
                $false { 
                    switch ( (Get-AzContext).Subscription.Id.ToLower().Equals( ($Subscription).ToLower() ) ) {
                        $false { Write-Error "Subscription ID mismatch, please provide the correct id or assume correct Subscription selection" }
                    }
                  }
            }
        }
        $true
        {
            switch ([string]::IsNullOrEmpty( ( $Tenant ) )) {
                $false { 
                        
                    }
            }
        }
    }
}

Test-AzContext -Tenant "F471a60c-d027-4fce-8bea-37665054066f" -Subscription "c737af30-1edc-4f9a-a7c5-4c9a4783b163"
