
#Requires -Version 7.4

<#
.SYNOPSIS
    Exports a certificate and private key from the Windows
    Certificate Store to PEM files.

.DESCRIPTION
    Exports a certificate from Cert:\LocalMachine\My using
    its SHA-1 thumbprint.

    Supported algorithms:
      - RSA
      - ECDSA
      - ECDH

    Output files:
      - certificate.pem
      - privatekey.pem

    Private keys are exported as PKCS#8 PEM.

    By default, private keys are encrypted using PBES2,
    AES-256-CBC and PBKDF2-HMAC-SHA256.

    Validation:
      - Reimports the generated private key PEM
      - Compares the imported key with the original key
      - Compares the imported key with the certificate
      - Verifies the published PEM files

    Requires Windows and PowerShell 7.4+.
    Automatically requests administrator elevation.

.PARAMETER Thumbprint
    SHA-1 thumbprint of the certificate.

.PARAMETER OutputPath
    Destination directory. Defaults to the user's Desktop.

.PARAMETER NoEncryption
    Exports the private key without encryption.

.PARAMETER Force
    Allows overwriting existing output files.

.EXAMPLE
    .\Export-CertificateToPem.ps1 `
        -Thumbprint "02F6936398E205D13B748BD005708E25D1685FF6" `
        -Force `
        -Verbose

.EXAMPLE
    .\Export-CertificateToPem.ps1 `
        -Thumbprint "02F6936398E205D13B748BD005708E25D1685FF6" `
        -NoEncryption `
        -OutputPath "C:\Temp\Certificates" `
        -Force

.NOTES
    Author      : Michael Waterman
    Website     : https://michaelwaterman.nl
    Version     : 1.3.0
    Script ID   : 1d875d76-b51b-41f7-b27a-44cadbd76fea
    PowerShell  : 7.4+
    Platform    : Windows
    Last updated : 2026-10-08
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Thumbprint,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = [Environment]::GetFolderPath('Desktop'),

    [Parameter()]
    [switch]$NoEncryption,

    [Parameter()]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------
# Helper: Compare SubjectPublicKeyInfo
# ------------------------------------------------------------

function Test-PublicKeyMatch {

    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [object]$FirstKey,

        [Parameter(Mandatory)]
        [object]$SecondKey
    )

    $FirstSpki = $FirstKey.ExportSubjectPublicKeyInfo()
    $SecondSpki = $SecondKey.ExportSubjectPublicKeyInfo()

    return (
        [Convert]::ToHexString($FirstSpki) -ceq
        [Convert]::ToHexString($SecondSpki)
    )
}

# ------------------------------------------------------------
# Helper: Compare key with certificate public key
# ------------------------------------------------------------

function Test-CertificateKeyMatch {

    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]
        $Certificate,

        [Parameter(Mandatory)]
        [object]$PrivateKey
    )

    $CertificateSpki =
        $Certificate.PublicKey.ExportSubjectPublicKeyInfo()

    $PrivateKeySpki =
        $PrivateKey.ExportSubjectPublicKeyInfo()

    return (
        [Convert]::ToHexString($CertificateSpki) -ceq
        [Convert]::ToHexString($PrivateKeySpki)
    )
}

# ------------------------------------------------------------
# Helper: Import private key PEM
# ------------------------------------------------------------

function Import-PrivateKeyPem {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Pem,

        [Parameter(Mandatory)]
        [string]$Algorithm,

        [Parameter()]
        [AllowNull()]
        [string]$Password,

        [Parameter()]
        [switch]$NoEncryption
    )

    $Key = $null

    try {

        switch ($Algorithm) {

            'RSA' {
                $Key = [Security.Cryptography.RSA]::Create()
            }

            'ECDSA' {
                $Key = [Security.Cryptography.ECDsa]::Create()
            }

            'ECDH' {
                $Key = [Security.Cryptography.ECDiffieHellman]::Create()
            }

            default {
                throw "Unsupported algorithm: $Algorithm"
            }
        }

        if ($NoEncryption) {
            $Key.ImportFromPem($Pem)
        }
        else {
            $Key.ImportFromEncryptedPem(
                $Pem,
                $Password
            )
        }

        return $Key
    }
    catch {

        if ($null -ne $Key) {
            $Key.Dispose()
        }

        throw
    }
}

# ------------------------------------------------------------
# Platform validation
# ------------------------------------------------------------

if (-not $IsWindows) {
    throw 'This script requires Windows.'
}

# ------------------------------------------------------------
# Administrator check and elevation
# ------------------------------------------------------------

$Identity = [Security.Principal.WindowsIdentity]::GetCurrent()

$Principal = [Security.Principal.WindowsPrincipal]::new(
    $Identity
)

$IsAdministrator = $Principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $IsAdministrator) {

    Write-Warning 'Administrator privileges are required.'
    Write-Host 'Requesting elevation through UAC...'

    if (-not $PSCommandPath) {
        throw 'Automatic elevation requires a saved .ps1 script.'
    }

    $Arguments = @{
        Thumbprint = $Thumbprint
        OutputPath = $OutputPath
    }

    if ($NoEncryption) {
        $Arguments.NoEncryption = $true
    }

    if ($Force) {
        $Arguments.Force = $true
    }

    if ($VerbosePreference -eq 'Continue') {
        $Arguments.Verbose = $true
    }

    $SerializedArguments =
        [Management.Automation.PSSerializer]::Serialize($Arguments)

    $ArgumentsBase64 = [Convert]::ToBase64String(
        [Text.Encoding]::Unicode.GetBytes($SerializedArguments)
    )

    $ScriptBase64 = [Convert]::ToBase64String(
        [Text.Encoding]::Unicode.GetBytes($PSCommandPath)
    )

    $Command = @"
`$scriptPath = [Text.Encoding]::Unicode.GetString(
    [Convert]::FromBase64String('$ScriptBase64')
)
`$xml = [Text.Encoding]::Unicode.GetString(
    [Convert]::FromBase64String('$ArgumentsBase64')
)
`$params = [Management.Automation.PSSerializer]::Deserialize(`$xml)
& `$scriptPath @params
"@

    $EncodedCommand = [Convert]::ToBase64String(
        [Text.Encoding]::Unicode.GetBytes($Command)
    )

    Start-Process `
        -FilePath (Get-Process -Id $PID).Path `
        -Verb RunAs `
        -ArgumentList @(
            '-NoProfile',
            '-NoExit',
            '-EncodedCommand',
            $EncodedCommand
        )

    return
}

Write-Verbose 'Administrator privileges confirmed.'

# ------------------------------------------------------------
# Normalize thumbprint
# ------------------------------------------------------------

$NormalizedThumbprint = (
    $Thumbprint -replace '[\s\u200E\u200F]', ''
).ToUpperInvariant()

if ($NormalizedThumbprint -notmatch '^[0-9A-F]{40}$') {
    throw 'Invalid thumbprint. Expected 40 hexadecimal characters.'
}

# ------------------------------------------------------------
# Initialize resources
# ------------------------------------------------------------

$Certificate = $null
$PrivateKey = $null
$ImportedKey = $null
$DiskImportedKey = $null

$PrivateKeyPem = $null
$CertificatePem = $null

$Password = $null
$PlainTextPassword = $null

$TempCertificate = $null
$TempPrivateKey = $null

try {

    # --------------------------------------------------------
    # Locate certificate
    # --------------------------------------------------------

    $CertificatePath =
        "Cert:\LocalMachine\My\$NormalizedThumbprint"

    $Certificate = Get-Item `
        -LiteralPath $CertificatePath `
        -ErrorAction Stop

    if (-not $Certificate.HasPrivateKey) {
        throw 'The certificate has no associated private key.'
    }

    Write-Verbose "Certificate found: $($Certificate.Subject)"

    # --------------------------------------------------------
    # Detect algorithm
    # --------------------------------------------------------

    $AlgorithmOid = $Certificate.PublicKey.Oid.Value

    Write-Verbose "Public key algorithm OID: $AlgorithmOid"

    switch ($AlgorithmOid) {

        # RSA
        '1.2.840.113549.1.1.1' {

            $KeyAlgorithm = 'RSA'

            $PrivateKey =
                [Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey(
                    $Certificate
                )
        }

        # EC: ECDSA or ECDH
        '1.2.840.10045.2.1' {

            $PrivateKey =
                [Security.Cryptography.X509Certificates.ECDsaCertificateExtensions]::GetECDsaPrivateKey(
                    $Certificate
                )

            if ($null -eq $PrivateKey) {
                throw 'Unable to access the EC private key.'
            }

            $KeyAlgorithm = 'ECDSA'

            if ($PrivateKey -is [Security.Cryptography.ECDsaCng]) {

                $CngAlgorithm =
                    $PrivateKey.Key.Algorithm.Algorithm

                Write-Verbose "Underlying CNG algorithm: $CngAlgorithm"

                if ($CngAlgorithm -like 'ECDH*') {
                    $KeyAlgorithm = 'ECDH'
                }
                elseif ($CngAlgorithm -like 'ECDSA*') {
                    $KeyAlgorithm = 'ECDSA'
                }
                else {
                    throw "Unsupported CNG EC algorithm: $CngAlgorithm"
                }
            }
        }

        default {
            throw "Unsupported algorithm OID: $AlgorithmOid"
        }
    }

    if ($null -eq $PrivateKey) {
        throw "Unable to access private key for $KeyAlgorithm."
    }

    Write-Verbose "Key algorithm: $KeyAlgorithm"
    Write-Verbose "Provider type: $($PrivateKey.GetType().FullName)"

    # --------------------------------------------------------
    # Check CNG export policy when accessible
    # --------------------------------------------------------

    $CngKey = $null

    if ($PrivateKey -is [Security.Cryptography.RSACng]) {
        $CngKey = $PrivateKey.Key
    }
    elseif ($PrivateKey -is [Security.Cryptography.ECDsaCng]) {
        $CngKey = $PrivateKey.Key
    }
    elseif ($PrivateKey -is [Security.Cryptography.ECDiffieHellmanCng]) {
        $CngKey = $PrivateKey.Key
    }
    if ($null -ne $CngKey) {

        $ExportPolicy = $CngKey.ExportPolicy

        Write-Verbose "CNG export policy: $ExportPolicy"

        $ExportAllowed =
            ($ExportPolicy -band [Security.Cryptography.CngExportPolicies]::AllowExport) -or
            ($ExportPolicy -band [Security.Cryptography.CngExportPolicies]::AllowPlaintextExport)

        if (-not $ExportAllowed) {

            throw @"
The private key is not exportable.

Certificate : $($Certificate.Subject)
Algorithm   : $KeyAlgorithm
ExportPolicy: $ExportPolicy

Request a new certificate with an exportable private key.
"@
        }
    }
    else {
        Write-Verbose 'CNG export policy not directly available; export will be attempted.'
    }

    # --------------------------------------------------------
    # Export certificate
    # --------------------------------------------------------

    $CertificatePem = $Certificate.ExportCertificatePem()

    # --------------------------------------------------------
    # Export private key
    # --------------------------------------------------------

    if ($NoEncryption) {

        Write-Warning 'Exporting an UNENCRYPTED private key.'

        $PrivateKeyPem =
            $PrivateKey.ExportPkcs8PrivateKeyPem()

        $Protection = 'None'
    }
    else {

        $Password = Read-Host `
            -Prompt 'Enter private key encryption password' `
            -AsSecureString

        if ($Password.Length -eq 0) {
            throw 'Encryption password cannot be empty.'
        }

        $BSTR = [IntPtr]::Zero

        try {

            $BSTR =
                [Runtime.InteropServices.Marshal]::SecureStringToBSTR(
                    $Password
                )

            $PlainTextPassword =
                [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
                    $BSTR
                )
        }
        finally {

            if ($BSTR -ne [IntPtr]::Zero) {
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR(
                    $BSTR
                )
            }
        }

        $PbeParameters =
            [Security.Cryptography.PbeParameters]::new(
                [Security.Cryptography.PbeEncryptionAlgorithm]::Aes256Cbc,
                [Security.Cryptography.HashAlgorithmName]::SHA256,
                100000
            )

        $PrivateKeyPem =
            $PrivateKey.ExportEncryptedPkcs8PrivateKeyPem(
                $PlainTextPassword,
                $PbeParameters
            )

        $Protection = 'PKCS#8 / AES-256-CBC'
    }

    # --------------------------------------------------------
    # Verify generated private key PEM
    # --------------------------------------------------------

    Write-Verbose 'Reimporting generated private key PEM.'

    $ImportedKey = Import-PrivateKeyPem `
        -Pem $PrivateKeyPem `
        -Algorithm $KeyAlgorithm `
        -Password $PlainTextPassword `
        -NoEncryption:$NoEncryption

    Write-Verbose 'Private key PEM successfully reimported.'

    # --------------------------------------------------------
    # Compare original and imported key
    # --------------------------------------------------------

    Write-Verbose 'Comparing exported key with original key.'

    $OriginalKeyMatch = Test-PublicKeyMatch `
        -FirstKey $PrivateKey `
        -SecondKey $ImportedKey

    if (-not $OriginalKeyMatch) {
        throw 'Exported private key does not match the original key.'
    }

    Write-Verbose 'Original private key comparison successful.'

    # --------------------------------------------------------
    # Compare imported key with certificate
    # --------------------------------------------------------

    Write-Verbose 'Comparing exported key with certificate public key.'

    $CertificateKeyMatch = Test-CertificateKeyMatch `
        -Certificate $Certificate `
        -PrivateKey $ImportedKey

    if (-not $CertificateKeyMatch) {
        throw 'Exported private key does not match the certificate public key.'
    }

    Write-Verbose 'Certificate/private key verification successful.'

    $ImportedKey.Dispose()
    $ImportedKey = $null

    # --------------------------------------------------------
    # Prepare output directory
    # --------------------------------------------------------

    if (-not (Test-Path -LiteralPath $OutputPath)) {

        New-Item `
            -Path $OutputPath `
            -ItemType Directory `
            -Force | Out-Null
    }

    $OutputPath =
        (Resolve-Path -LiteralPath $OutputPath).Path

    $CertificateFile =
        Join-Path $OutputPath 'certificate.pem'

    $PrivateKeyFile =
        Join-Path $OutputPath 'privatekey.pem'

    foreach ($File in @($CertificateFile, $PrivateKeyFile)) {

        if ((Test-Path -LiteralPath $File) -and -not $Force) {
            throw "Output file exists: $File. Use -Force to overwrite."
        }
    }

    # --------------------------------------------------------
    # Create temporary files
    # --------------------------------------------------------

    $TempCertificate = Join-Path $OutputPath (
        [guid]::NewGuid().ToString() + '.tmp'
    )

    $TempPrivateKey = Join-Path $OutputPath (
        [guid]::NewGuid().ToString() + '.tmp'
    )

    # --------------------------------------------------------
    # Restrict private key file ACL
    # --------------------------------------------------------

    $CurrentUser =
        [Security.Principal.WindowsIdentity]::GetCurrent().User

    $Acl = [Security.AccessControl.FileSecurity]::new()

    $Acl.SetOwner($CurrentUser)
    $Acl.SetAccessRuleProtection($true, $false)

    $Rule = [Security.AccessControl.FileSystemAccessRule]::new(
        $CurrentUser,
        [Security.AccessControl.FileSystemRights]::FullControl,
        [Security.AccessControl.AccessControlType]::Allow
    )

    $Acl.AddAccessRule($Rule)

    $PrivateKeyStream = [IO.File]::Open(
        $TempPrivateKey,
        [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write,
        [IO.FileShare]::None
    )

    try {

        $PrivateKeyStream.Dispose()

        $FileInfo = [IO.FileInfo]::new($TempPrivateKey)

        [IO.FileSystemAclExtensions]::SetAccessControl(
            $FileInfo,
            $Acl
        )

        [IO.File]::WriteAllText(
            $TempPrivateKey,
            $PrivateKeyPem,
            [Text.Encoding]::ASCII
        )
    }
    finally {

        if ($null -ne $PrivateKeyStream) {
            $PrivateKeyStream.Dispose()
        }
    }

    # --------------------------------------------------------
    # Write certificate PEM
    # --------------------------------------------------------

    [IO.File]::WriteAllText(
        $TempCertificate,
        $CertificatePem,
        [Text.Encoding]::ASCII
    )

    # --------------------------------------------------------
    # Verify PEM files on disk
    # --------------------------------------------------------

    Write-Verbose 'Verifying private key PEM written to disk.'

    $DiskPrivateKeyPem =
        [IO.File]::ReadAllText($TempPrivateKey)

    $DiskImportedKey = Import-PrivateKeyPem `
        -Pem $DiskPrivateKeyPem `
        -Algorithm $KeyAlgorithm `
        -Password $PlainTextPassword `
        -NoEncryption:$NoEncryption

    $DiskKeyMatch = Test-CertificateKeyMatch `
        -Certificate $Certificate `
        -PrivateKey $DiskImportedKey

    if (-not $DiskKeyMatch) {
        throw 'Private key PEM on disk does not match the certificate.'
    }

    $DiskImportedKey.Dispose()
    $DiskImportedKey = $null

    $DiskCertificatePem =
        [IO.File]::ReadAllText($TempCertificate)

    $DiskCertificate =
        [Security.Cryptography.X509Certificates.X509Certificate2]::CreateFromPem(
            $DiskCertificatePem
        )

    try {

        if ($DiskCertificate.Thumbprint -ne $Certificate.Thumbprint) {
            throw 'Certificate PEM on disk does not match the original certificate.'
        }
    }
    finally {
        $DiskCertificate.Dispose()
    }

    Write-Verbose 'PEM files on disk successfully verified.'

    # --------------------------------------------------------
    # Publish output files
    # --------------------------------------------------------

    Move-Item `
        -LiteralPath $TempPrivateKey `
        -Destination $PrivateKeyFile `
        -Force:$Force

    $TempPrivateKey = $null

    Move-Item `
        -LiteralPath $TempCertificate `
        -Destination $CertificateFile `
        -Force:$Force

    $TempCertificate = $null

    # --------------------------------------------------------
    # Results
    # --------------------------------------------------------

    Write-Host ''
    Write-Host 'Certificate successfully exported.' -ForegroundColor Green
    Write-Host ''

    Write-Host "Subject        : $($Certificate.Subject)"
    Write-Host "Issuer         : $($Certificate.Issuer)"
    Write-Host "Thumbprint     : $($Certificate.Thumbprint)"
    Write-Host "Key Algorithm  : $KeyAlgorithm"
    Write-Host "Valid From     : $($Certificate.NotBefore)"
    Write-Host "Valid Until    : $($Certificate.NotAfter)"

    Write-Host ''
    Write-Host "Certificate    : $CertificateFile"
    Write-Host "Private Key    : $PrivateKeyFile"
    Write-Host "Key Protection : $Protection"
    Write-Host "Key Match      : Verified" -ForegroundColor Green
    Write-Host "Disk Integrity : Verified" -ForegroundColor Green
    Write-Host ''
}
catch {

    Write-Error "Certificate export failed: $($_.Exception.Message)"
}
finally {

    foreach ($Key in @(
        $DiskImportedKey,
        $ImportedKey,
        $PrivateKey
    )) {

        if ($null -ne $Key) {
            $Key.Dispose()
        }
    }

    if ($null -ne $Certificate) {
        $Certificate.Dispose()
    }

    foreach ($TempFile in @(
        $TempCertificate,
        $TempPrivateKey
    )) {

        if ($TempFile -and (Test-Path -LiteralPath $TempFile)) {

            Remove-Item `
                -LiteralPath $TempFile `
                -Force `
                -ErrorAction SilentlyContinue
        }
    }

    $PrivateKeyPem = $null
    $CertificatePem = $null
    $PlainTextPassword = $null
    $Password = $null
}
