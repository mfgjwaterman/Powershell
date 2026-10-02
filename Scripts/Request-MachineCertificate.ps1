#Requires -Version 5.1
<#
.SYNOPSIS
    Requests and installs a machine certificate through Active Directory
    enrollment policy or a Certificate Enrollment Policy (CEP) web service.

.DESCRIPTION
    Runs locally in elevated Windows PowerShell 5.1 and uses the built-in
    Windows PKI module to submit a certificate request for a specified template.

    By default, explicitly selects Active Directory enrollment policy (ldap:)
    and uses Windows integrated authentication. A supplied CEP URL selects web
    enrollment policy; CEP provides the corresponding CES enrollment endpoints.

    Supports one or more DNS Subject Alternative Names (SANs). When SAN is
    provided without SubjectName, the first DNS name is also requested as the
    subject Common Name (CN). An explicit SubjectName overrides this default.
    Without either parameter, subject construction is left to the template.

    If the CA returns Pending, polls the existing request until it is issued,
    the wait times out, or an error occurs. A progress bar shows the next-check
    countdown, elapsed wait and completed checks. Checks are also timestamped.
    Polling never submits a second CSR and does not approve the request.

    After issuance, installs the certificate in Cert:\LocalMachine\My and
    verifies that the installed certificate has an associated private key.
    Returns the installed certificate object for further PowerShell processing.

    A pending request can be resumed on the same machine using its request-store
    thumbprint. The original request contains the enrollment server information;
    Template, SAN, SubjectName and CepUrl are not supplied when resuming.

.PARAMETER Template
    Required for a new request. Internal certificate template name (AD common
    name) or template OID; use the template name rather than its display name.
    The template must be published on an available CA and permit enrollment
    by the identity used for the request. Not available in resume mode.

.PARAMETER SAN
    Optional array of DNS names included in the SAN extension.
    Alias: DnsName. Supply separate strings without a DNS= prefix.
    Leading/trailing whitespace is trimmed and duplicate names are removed.
    Only DNS SANs are supported; IP address, UPN and email SANs are not supported.
    The script imposes no explicit entry-count limit.
    If SubjectName is omitted, the first SAN is also used as CN.
    Not available in resume mode.

.PARAMETER SubjectName
    Optional X.500 distinguished name, for example:
    'CN=test.corp.domain.com'
    or 'CN=test.corp.domain.com,OU=Lab,O=Example,C=NL'.
    A bare hostname is not a valid SubjectName: include CN=.
    Overrides automatic CN selection from the first SAN. Does not automatically
    add the subject name to the SAN list. Template/CA policy must permit the
    requested subject and SAN values. Not available in resume mode.

.PARAMETER CepUrl
    Optional absolute HTTPS URL of the CEP policy endpoint, not a CES URL.
    When omitted, the script explicitly uses AD policy through ldap:.
    For SSO, use a Kerberos endpoint. For username/password authentication,
    use compatible CEP and CES endpoints supporting that authentication method.
    Suitable for workgroup machines when used with appropriate credentials.
    Not available in resume mode; the stored request retains endpoint information.

.PARAMETER PendingRequestThumbprint
    Required in resume mode. The 40-character hexadecimal thumbprint of the
    pending request in Cert:\LocalMachine\Request, printed by the script.
    This identifies the local pending request, not the CA's numeric Request ID
    or the thumbprint of the final issued certificate.
    Use on the original requesting machine with the original request/key intact.
    Cannot be combined with Template, SAN, SubjectName or CepUrl.

.PARAMETER Credential
    Optional PSCredential object, for example (Get-Credential).
    Used for submission and subsequent retrieval, including resume mode.
    Cannot be combined with UserName or Password.
    For a new request, username/password credentials require CepUrl.
    If omitted, Windows enrollment uses its integrated authentication behavior;
    retrieval may also use Windows enrollment's existing credential store.

.PARAMETER UserName
    Optional username such as 'CORP\enrollmentuser' or a UPN.
    Without Password, opens a credential prompt with this username prefilled.
    With Password, constructs a PSCredential without prompting.
    Cannot be combined with Credential. For a new request, requires CepUrl.
    Can also be supplied when resuming a username/password request.

.PARAMETER Password
    Optional System.Security.SecureString password; requires UserName.
    A plain string is not accepted. Prefer Read-Host -AsSecureString.
    For lab automation, ConvertTo-SecureString -AsPlainText -Force can construct
    the variable, but the original literal remains exposed in the script/history.
    Cannot be combined with Credential.

.PARAMETER PollIntervalSeconds
    Seconds between completed pending responses and the next retrieval attempt.
    Default: 30. Valid range: 5 through 3600.
    The countdown updates approximately once per second; network-call duration
    is additional to the waiting interval. Applies to new requests and resume.

.PARAMETER TimeoutMinutes
    Approval-wait limit in minutes. Default: 0, meaning wait indefinitely.
    Valid range: 0 through 525600. The timer starts after the initial submission
    or initial resume retrieval, and restarts for each script invocation.
    This is an approval-wait limit, not a timeout for individual network calls.
    On timeout, throws an error and retains the pending request/private key.
    Resume using PendingRequestThumbprint.

.EXAMPLE
    .\Request-MachineCertificate.ps1 -Template Computer

    Requests a machine certificate using AD policy and integrated authentication.
    The template determines the subject. Run as a local administrator.

.EXAMPLE
    .\Request-MachineCertificate.ps1 `
        -Template RequestLabActiveDirectoryTLSCertificate `
        -SAN 'test.corp.domain.com'

    Requests both CN=test.corp.domain.com and the matching DNS SAN.
    Waits if the CA returns Pending, then installs the issued certificate.

.EXAMPLE
    .\Request-MachineCertificate.ps1 `
        -Template RequestLabActiveDirectoryTLSCertificate `
        -SubjectName 'CN=app.corp.domain.com' `
        -SAN 'test.corp.domain.com','alias.corp.domain.com'

    Explicitly sets the CN and requests two different DNS SANs.
    To also include pietje in SAN, add that name to the SAN array.

.EXAMPLE
    .\Request-MachineCertificate.ps1 `
        -Template RequestLabActiveDirectoryTLSCertificate `
        -SAN 'test.corp.domain.com' `
        -CepUrl 'https://cep.domain.com/ADPolicyProvider_CEP_Kerberos/service.svc/CEP'

    Uses a CEP Kerberos endpoint with default integrated authentication.

.EXAMPLE
    $cred = Get-Credential
    .\Request-MachineCertificate.ps1 `
        -Template RequestLabActiveDirectoryTLSCertificate `
        -SAN 'test.corp.domain.com' `
        -CepUrl 'https://cep.domain.com/ADPolicyProvider_CEP_UsernamePassword/service.svc/CEP' `
        -Credential $cred

    Uses explicit credentials with CEP/CES username/password authentication.
    Can be used on a workgroup machine with DNS connectivity and trusted CA chains.

.EXAMPLE
    .\Request-MachineCertificate.ps1 `
        -Template RequestLabActiveDirectoryTLSCertificate `
        -SAN 'test.corp.domain.com' `
        -CepUrl 'https://cep.example.com/ADPolicyProvider_CEP_UsernamePassword/service.svc/CEP' `
        -UserName 'CORP\enrollmentuser'

    Prompts for the password using the supplied username.

.EXAMPLE
    $password = Read-Host 'Enrollment password' -AsSecureString
    .\Request-MachineCertificate.ps1 `
        -Template RequestLabActiveDirectoryTLSCertificate `
        -SAN 'test.corp.domain.com' `
        -CepUrl 'https://cep.example.com/ADPolicyProvider_CEP_UsernamePassword/service.svc/CEP' `
        -UserName 'CORP\enrollmentuser' -Password $password

    Supplies the password through a SecureString variable.

.EXAMPLE
    $password = ConvertTo-SecureString 'REPLACE-WITH-PASSWORD' -AsPlainText -Force
    .\Request-MachineCertificate.ps1 `
        -Template RequestLabActiveDirectoryTLSCertificate `
        -SAN 'test.corp.domain.com' `
        -CepUrl 'https://cep.domain.com/ADPolicyProvider_CEP_UsernamePassword/service.svc/CEP' `
        -UserName 'CORP\enrollmentuser' -Password $password

    Lab-only example without a password prompt. The literal password remains
    readable in the script or command history; SecureString does not hide it there.

.EXAMPLE
    .\Request-MachineCertificate.ps1 `
        -Template RequestLabActiveDirectoryTLSCertificate `
        -SAN 'test.corp.domain.com' `
        -PollIntervalSeconds 10 -TimeoutMinutes 5

    Checks every 10 seconds, with an approval-wait limit of five minutes.

.EXAMPLE
    .\Request-MachineCertificate.ps1 `
        -PendingRequestThumbprint 'F47AD2BFAF82ACA16005569392DB3D5D40696024'

    Retrieves the original pending request and resumes waiting without a new CSR.

.EXAMPLE
    .\Request-MachineCertificate.ps1 `
        -PendingRequestThumbprint 'F47AD2BFAF82ACA16005569392DB3D5D40696024' `
        -Credential (Get-Credential) -PollIntervalSeconds 10 -TimeoutMinutes 60

    Resumes a username/password request with a new 60-minute approval-wait limit.
    No CEP URL or template is needed.

.EXAMPLE
    $cert = .\Request-MachineCertificate.ps1 `
        -Template RequestLabActiveDirectoryTLSCertificate `
        -SAN 'test.corp.domain.com'
    $cert | Select-Object Subject, Thumbprint, NotAfter, HasPrivateKey

    Captures the installed certificate object and displays its key properties.

.INPUTS
    None. Parameters are supplied explicitly; pipeline input is not accepted.

.OUTPUTS
    System.Security.Cryptography.X509Certificates.X509Certificate2
    The issued certificate installed in the local machine's Personal store.

.NOTES
    Requirements:
    - Windows PowerShell 5.1 (powershell.exe), run locally as administrator.
    - Built-in Windows PKI module and certificate provider.
    - Appropriate template Read/Enroll permissions and CA enrollment permissions.
    - For direct AD enrollment: domain policy/CA discovery and LDAP/RPC connectivity.
    - For CEP/CES: working DNS, HTTPS connectivity, trusted server certificate
      chains and matching authentication support on the discovered CES endpoints.
    - A template configured to permit supplied subject/SAN values when requested.

    Approval is governed by template/CA policy. Adding SANs does not itself
    require approval. The script waits on any Pending response, with or without SANs.

    The script relies on Windows integrated authentication for SSO; it does not
    independently force or verify the negotiated Kerberos protocol.

    Timeout, cancellation or retrieval failure does not intentionally delete the
    pending request or key. Fix the issue and resume the original local request.
    An already submitted CSR cannot have its subject or SANs changed by resuming.

    Lab feedback during development confirmed SAN population, approval waiting,
    ten DNS SAN entries and timeout/resume behavior. A bare SubjectName produced
    CRYPT_E_INVALID_X500_STRING; use a valid X.500 name including CN=.

    Troubleshooting enrollment policy cache (run elevated on the requesting host):
        certutil -f -policyserver * -policycache delete

    View this help:
        Get-Help .\Request-MachineCertificate.ps1 -Full
        Get-Help .\Request-MachineCertificate.ps1 -Examples

.LINK
    https://learn.microsoft.com/powershell/module/pki/get-certificate
#>

[CmdletBinding(DefaultParameterSetName = 'Enroll')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Enroll')]
    [ValidateNotNullOrEmpty()]
    [string]$Template,

    [Parameter(ParameterSetName = 'Enroll')]
    [Alias('DnsName')]
    [ValidateNotNullOrEmpty()]
    [string[]]$SAN,

    [Parameter(ParameterSetName = 'Enroll')]
    [ValidateNotNullOrEmpty()]
    [string]$SubjectName,

    [Parameter(ParameterSetName = 'Enroll')]
    [uri]$CepUrl,

    [Parameter(Mandatory, ParameterSetName = 'Resume')]
    [ValidatePattern('^[a-fA-F0-9]{40}$')]
    [string]$PendingRequestThumbprint,

    [System.Management.Automation.PSCredential]$Credential,
    [ValidateNotNullOrEmpty()]
    [string]$UserName,
    [System.Security.SecureString]$Password,
    [ValidateRange(5, 3600)]
    [int]$PollIntervalSeconds = 30,
    [ValidateRange(0, 525600)]
    [int]$TimeoutMinutes = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'This script requires Windows and Windows PowerShell 5.1.'
}
if ($PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'Run this script in Windows PowerShell 5.1 (powershell.exe).'
}
$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Start Windows PowerShell with Run as administrator and try again.'
}
if ($Credential -and ($PSBoundParameters.ContainsKey('UserName') -or $PSBoundParameters.ContainsKey('Password'))) {
    throw 'Use Credential OR UserName/Password, not both.'
}
if ($PSBoundParameters.ContainsKey('Password') -and -not $UserName) {
    throw 'Password requires UserName.'
}
if ($CepUrl -and (-not $CepUrl.IsAbsoluteUri -or $CepUrl.Scheme -ne 'https')) {
    throw 'CepUrl must be an absolute HTTPS CEP policy URL.'
}
if ($PSCmdlet.ParameterSetName -eq 'Enroll' -and -not $CepUrl -and ($Credential -or $UserName)) {
    throw 'Username/password enrollment requires a CEP URL with compatible CEP and CES endpoints. Direct AD enrollment uses Windows integrated authentication.'
}
if ($UserName) {
    if ($Password) {
        $Credential = New-Object System.Management.Automation.PSCredential($UserName, $Password)
    } else {
        $Credential = Get-Credential -UserName $UserName -Message 'Certificate enrollment credentials'
        if (-not $Credential) { throw 'No credentials supplied.' }
    }
}
Import-Module PKI -ErrorAction Stop

# Keep retrieval separate from submission: never create another CSR while polling.
$retrieveParameters = @{ ErrorAction = 'Stop' }
if ($Credential) { $retrieveParameters.Credential = $Credential }

Push-Location -Path 'Cert:\LocalMachine\My'
try {
    if ($PSCmdlet.ParameterSetName -eq 'Resume') {
        $requestPath = "Cert:\LocalMachine\Request\$PendingRequestThumbprint"
        $pendingRequest = Get-Item -LiteralPath $requestPath -ErrorAction Stop
        $result = Get-Certificate -Request $pendingRequest @retrieveParameters
    } else {
        $submitParameters = @{
            Template = $Template
            CertStoreLocation = 'Cert:\LocalMachine\My'
            Url = [uri]'ldap:'
            ErrorAction = 'Stop'
        }
        if ($CepUrl) { $submitParameters.Url = $CepUrl }
        if ($Credential) { $submitParameters.Credential = $Credential }
        if ($PSBoundParameters.ContainsKey('SubjectName')) {
            $submitParameters.SubjectName = $SubjectName
        }
        if ($SAN) {
            $names = @($SAN | ForEach-Object {
                $name = $_.Trim()
                if ([string]::IsNullOrWhiteSpace($name)) { throw 'SAN contains an empty DNS name.' }
                if ($name -match '[\s,/:=\\"+;<>]') { throw "Invalid DNS SAN '$name'. Supply individual DNS names, without DNS= prefixes." }
                $name
            } | Select-Object -Unique)
            $submitParameters.DnsName = $names
            if (-not $PSBoundParameters.ContainsKey('SubjectName')) {
                $submitParameters.SubjectName = "CN=$($names[0])"
            }
        }
        Write-Host "Requesting template '$Template' using $($submitParameters.Url)."
        if ($submitParameters.ContainsKey('SubjectName')) {
            Write-Host "Requested subject: $($submitParameters.SubjectName)"
        }
        $result = Get-Certificate @submitParameters
    }

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $pollAttempt = 0
    while ([string]$result.Status -eq 'Pending') {
        if (-not $result.Request) { throw 'CA returned Pending without a request object.' }
        $pendingRequest = $result.Request
        $thumbprint = $pendingRequest.Thumbprint
        Write-Host "Pending approval. Request store thumbprint: $thumbprint"
        Write-Verbose "Resume with: .\Request-MachineCertificate.ps1 -PendingRequestThumbprint '$thumbprint' (add credentials if required)."
        if ($TimeoutMinutes -gt 0 -and $timer.Elapsed.TotalMinutes -ge $TimeoutMinutes) {
            throw "Approval wait timed out. Request retained in Cert:\LocalMachine\Request\$thumbprint. Resume with -PendingRequestThumbprint '$thumbprint'."
        }
        $delay = $PollIntervalSeconds
        if ($TimeoutMinutes -gt 0) {
            $remaining = ($TimeoutMinutes * 60) - $timer.Elapsed.TotalSeconds
            $delay = [Math]::Min($delay, [Math]::Max(1, [Math]::Ceiling($remaining)))
        }
        $nextCheck = Get-Date
        $nextCheck = $nextCheck.AddSeconds($delay)
        do {
            $secondsLeft = [int][Math]::Max(0, [Math]::Ceiling(($nextCheck - (Get-Date)).TotalSeconds))
            $percent = [int][Math]::Min(100, [Math]::Max(0, 100 * (1 - ($secondsLeft / [double]$delay))))
            Write-Progress -Id 716 -Activity 'Waiting for certificate approval' `
                -Status "Next check in $secondsLeft seconds | Checks completed: $pollAttempt" `
                -CurrentOperation "Request: $thumbprint | Waiting: $($timer.Elapsed.ToString('hh\:mm\:ss'))" `
                -SecondsRemaining $secondsLeft -PercentComplete $percent
            if ($secondsLeft -gt 0) { Start-Sleep -Seconds 1 }
        } while ($secondsLeft -gt 0)
        if ($TimeoutMinutes -gt 0 -and $timer.Elapsed.TotalMinutes -ge $TimeoutMinutes) {
            throw "Approval wait timed out. Request retained. Resume with -PendingRequestThumbprint '$thumbprint'."
        }
        # The stored request carries the original enrollment server information.
        # PendingRetrieval has no Url parameter; no new submission is made.
        $pollAttempt++
        Write-Progress -Id 716 -Activity 'Waiting for certificate approval' `
            -Status "Checking CA (attempt $pollAttempt)..." -SecondsRemaining -1
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Checking approval (attempt $pollAttempt)..."
        $result = Get-Certificate -Request $pendingRequest @retrieveParameters
    }
    if ([string]$result.Status -ne 'Issued' -or -not $result.Certificate) {
        throw "Enrollment did not issue a certificate. Status: $($result.Status)."
    }
    $certificate = $result.Certificate
    $installed = Get-Item -LiteralPath "Cert:\LocalMachine\My\$($certificate.Thumbprint)"
    if (-not $installed.HasPrivateKey) { throw 'Issued certificate does not have an associated private key.' }
    Write-Host "Certificate installed in LocalMachine\My: $($installed.Thumbprint)"
    # Return the actual certificate so callers can pipe it or assign it to a variable.
    $installed
} catch {
    # Do not automatically retry failures or resubmit a CSR. Pending requests remain
    # available for explicit resumption after fixing connectivity/authentication.
    Write-Verbose 'Enrollment stopped. Any existing pending request and key have been retained.'
    throw
} finally {
    Write-Progress -Id 716 -Activity 'Waiting for certificate approval' -Completed
    Pop-Location
}
