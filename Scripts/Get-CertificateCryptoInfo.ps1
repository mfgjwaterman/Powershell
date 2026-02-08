function Get-CertificateCryptoInfo {
<#
.SYNOPSIS
Returns cryptographic details for X.509 certificates (RSA or ECC), including key type, key size, curve (ECC), and signature algorithm.

.DESCRIPTION
Get-CertificateCryptoInfo extracts crypto-relevant properties from certificates such as:
- Key type (RSA vs ECC/ECDSA) based on Public Key OID
- Key size (RSA modulus size or ECC curve size)
- Curve information for ECC certificates
- Signature algorithm (e.g., sha256RSA)
- Optional EKU OID presence check

Because PowerShell/.NET can sometimes return incomplete key information for CNG-based keys (especially ECC),
this function includes a fallback to certutil.exe to reliably determine the public key length and curve details.

.PARAMETER Certificate
A certificate object (X509Certificate2) provided via pipeline input.

.PARAMETER Thumbprint
Finds a certificate by thumbprint in the specified certificate store path.

.PARAMETER StorePath
The certificate store path used with -Thumbprint. Defaults to Cert:\LocalMachine\My.

.PARAMETER EkuOidToCheck
Optional EKU OID to check for presence in the certificate.

.OUTPUTS
System.Management.Automation.PSCustomObject

.EXAMPLE
Get-ChildItem Cert:\LocalMachine\My | Get-CertificateCryptoInfo

.EXAMPLE
Get-CertificateCryptoInfo -Thumbprint "ABCD1234..." -StorePath "Cert:\LocalMachine\My"

.EXAMPLE
$rdpEkuOid = "1.3.6.1.4.1.311.54.1.2"
Get-ChildItem Cert:\LocalMachine\My | Get-CertificateCryptoInfo -EkuOidToCheck $rdpEkuOid
#>
    [CmdletBinding(DefaultParameterSetName = "ByCert")]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = "ByCert")]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

        [Parameter(Mandatory, ParameterSetName = "ByThumbprint")]
        [string]$Thumbprint,

        [Parameter(ParameterSetName = "ByThumbprint")]
        [string]$StorePath = "Cert:\LocalMachine\My",

        [string]$EkuOidToCheck
    )

    process {
        $cert = $null

        if ($PSCmdlet.ParameterSetName -eq "ByThumbprint") {
            $tp = ($Thumbprint -replace '\s','').ToUpperInvariant()
            $cert = Get-ChildItem $StorePath -ErrorAction Stop |
                Where-Object { (($_.Thumbprint -replace '\s','').ToUpperInvariant()) -eq $tp } |
                Select-Object -First 1

            if (-not $cert) {
                throw "No certificate with thumbprint '$Thumbprint' was found in '$StorePath'."
            }
        } else {
            $cert = $Certificate
        }

        $sigAlg = $cert.SignatureAlgorithm.FriendlyName
        $pkAlgFriendly = $cert.PublicKey.Oid.FriendlyName
        $pkAlgOid = $cert.PublicKey.Oid.Value

        $keyType = switch ($pkAlgOid) {
            "1.2.840.113549.1.1.1" { "RSA" }
            "1.2.840.10045.2.1"   { "ECC/ECDSA" }
            default               { "Unknown" }
        }

        $keySize = $null
        $curve   = $null

        try {
            if ($cert.PublicKey.Key -and $cert.PublicKey.Key.KeySize) {
                $keySize = $cert.PublicKey.Key.KeySize
            }
        } catch { }

        if (-not $keySize) {
            try {
                $thumb = ($cert.Thumbprint -replace '\s','').ToUpperInvariant()
                $certutilText = certutil.exe -store -v My $thumb 2>$null | Out-String

                if ($certutilText -match 'Public Key Length:\s*(\d+)\s*bits') {
                    $keySize = [int]$Matches[1]
                }

                if ($certutilText -match '(?im)Curve Name:\s*(.+)$') {
                    $curve = $Matches[1].Trim()
                }
            } catch { }
        }

        if ($keyType -eq "ECC/ECDSA" -and -not $curve -and $keySize) {
            $curve = switch ($keySize) {
                256 { "P-256 (prime256v1/secp256r1)" }
                384 { "P-384 (secp384r1)" }
                521 { "P-521 (secp521r1)" }
                default { $null }
            }
        }

        $cryptoSummary = if ($keyType -eq "RSA") {
            "RSA $keySize / $sigAlg"
        }
        elseif ($keyType -eq "ECC/ECDSA") {
            if ($curve) {
                "ECDSA $curve / $sigAlg"
            } else {
                "ECDSA $keySize-bit / $sigAlg"
            }
        }
        else {
            "$keyType / $sigAlg"
        }

        $hasEku = $null
        if ($EkuOidToCheck) {
            $hasEku = $false
            try {
                if ($cert.EnhancedKeyUsageList) {
                    $hasEku = $cert.EnhancedKeyUsageList.ObjectId -contains $EkuOidToCheck
                }
            } catch { }
        }

        [pscustomobject]@{
            Subject            = $cert.Subject
            Thumbprint         = $cert.Thumbprint
            NotAfter           = $cert.NotAfter

            KeyType            = $keyType
            KeySize            = $keySize
            Curve              = $curve

            PublicKeyAlgorithm = $pkAlgFriendly
            PublicKeyAlgOid    = $pkAlgOid
            SignatureAlgorithm = $sigAlg

            CryptoSummary      = $cryptoSummary

            EkuOidChecked      = $EkuOidToCheck
            HasEkuOid          = $hasEku
        }
    }
}


$targetOid = "1.3.6.1.4.1.311.54.1.2"
Get-ChildItem Cert:\LocalMachine\My | Get-CertificateCryptoInfo -EkuOidToCheck $targetOid