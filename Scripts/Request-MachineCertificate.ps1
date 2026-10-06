#Requires -Version 5.1

<#
.SYNOPSIS
    Requests and installs a machine certificate through Active Directory
    enrollment policy or a Certificate Enrollment Policy (CEP) web service.

.DESCRIPTION
    Runs locally in elevated Windows PowerShell 5.1 and uses the built-in
    Windows PKI module to submit a certificate request for a specified template.

    By default, leaves Url unspecified so Windows uses the configured default
    machine enrollment policy, including a default policy configured through GPO.
    CepUrl explicitly selects a CEP endpoint. UseADPolicy forces direct Active
    Directory policy (ldap:) for troubleshooting. These overrides are exclusive.
    Windows handles authentication for the selected policy unless explicit
    credentials are supplied. CEP provides the corresponding CES endpoints.

    Supports one or more DNS Subject Alternative Names (SANs). When SAN is
    provided without SubjectName, the first DNS name is also requested as the
    subject Common Name (CN). An explicit SubjectName overrides this default.
    Without either parameter, subject construction is left to the template.

    If the CA returns Pending, polls the existing request until it is issued,
    the wait times out, or an error occurs. A progress bar shows the next-check
    countdown, elapsed wait and completed checks. Checks are also timestamped.
    Polling never submits a second CSR and does not approve the request.

    After issuance, stages the certificate in Cert:\LocalMachine\My and
    verifies that the installed certificate has an associated private key.
    Places it in CertStoreLocation and returns that certificate object. Writes a
    unique operational log for every invocation.

    A pending request can be resumed on the same machine using its request-store
    thumbprint. The original request contains the enrollment server information;
    Template, SAN, SubjectName, CepUrl and UseADPolicy are not supplied when resuming.
    A saved destination and optional friendly name are restored unless overridden.

.PARAMETER CertStoreLocation
    Final application certificate store. Default: Cert:\LocalMachine\My.
    Supports existing stores under LocalMachine, such as WebHosting or a custom
    application store. Rejects user, trust, revocation and request stores.
    Enrollment always stages in My. After issuance, copies the certificate with
    its key association, verifies the destination, then removes the My entry.
    No private-key export or deletion is performed. On failure, inspect My and
    the destination before submitting a replacement request.
    Pending requests remember this setting in HKLM. Resume restores it unless
    explicitly overridden. Older requests without metadata default to My;
    specify this parameter when resuming if another destination is intended.

.PARAMETER FriendlyName
    Optional local display name for the issued certificate, 1 through 260
    characters. Available for new requests and resume. Whitespace-only names
    and embedded null characters are rejected. Duplicate display names are allowed.
    Applied only after installation in the final store and private-key verification.
    This is local store metadata, not a CSR field or signed certificate extension.
    When omitted, preserves the existing display name; no name is generated.
    Pending requests save this setting alongside the destination in HKLM.
    Resume restores a saved name unless FriendlyName is explicitly supplied.
    If setting or verification fails, warns and logs the error but still returns
    the installed certificate. Do not submit a replacement request for this warning.

.PARAMETER LogDirectory
    Filesystem directory for a unique UTF-8 log per invocation.
    Default: $env:SystemRoot\Temp, normally C:\Windows\Temp.
    Created if missing. Logging must initialize before submission; later write
    failures warn and do not interrupt enrollment. Resume creates a new log.
    Logs operational metadata, not passwords or credential objects. Avoid
    broadly shared directories because subjects and SANs may be sensitive.

.PARAMETER LogLevel
    Info (default) or Debug. Info records submission/retrieval status, pending
    thumbprint, polling attempts, timeout, installation and error identifiers.
    Debug adds retrieval detail. WARNING and ERROR are logged at both levels.
    Countdown updates are displayed only, not logged every second.
    Parser, platform and elevation failures occur before logging initialization.

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
    When omitted, Windows uses the configured default machine enrollment policy
    unless UseADPolicy is set. Cannot be combined with UseADPolicy.
    For SSO, use a Kerberos endpoint. For username/password authentication,
    use compatible CEP and CES endpoints supporting that authentication method.
    Suitable for workgroup machines when used with appropriate credentials.
    Not available in resume mode; the stored request retains endpoint information.

.PARAMETER UseADPolicy
    Optional switch forcing direct Active Directory enrollment policy via ldap:.
    Useful for comparing direct AD enrollment with a configured default CEP policy.
    Does not change Windows or GPO policy configuration; affects this request only.
    Cannot be combined with CepUrl. Explicit username/password credentials are
    not supported for this direct AD route; use Windows integrated authentication.
    Available only for a new request, not when resuming a stored request.

.PARAMETER PendingRequestThumbprint
    Required in resume mode. The 40-character hexadecimal thumbprint of the
    pending request in Cert:\LocalMachine\Request, printed by the script.
    This identifies the local pending request, not the CA's numeric Request ID
    or the thumbprint of the final issued certificate.
    Use on the original requesting machine with the original request/key intact.
    Cannot be combined with Template, SAN, SubjectName, CepUrl or UseADPolicy.

.PARAMETER Credential
    Optional PSCredential object, for example (Get-Credential).
    Used for submission and subsequent retrieval, including resume mode.
    Cannot be combined with UserName or Password.
    Works with CepUrl or a compatible configured default policy. Cannot be
    combined with UseADPolicy. The selected CEP/CES endpoints must support it.
    If omitted, Windows enrollment uses its integrated authentication behavior;
    retrieval may also use Windows enrollment's existing credential store.

.PARAMETER UserName
    Optional username such as 'CORP\enrollmentuser' or a UPN.
    Without Password, opens a credential prompt with this username prefilled.
    With Password, constructs a PSCredential without prompting.
    Cannot be combined with Credential or UseADPolicy. May be used with CepUrl
    or a compatible configured default machine enrollment policy.
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

    Requests a machine certificate using the configured default machine policy.
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
    To also include the SubjectName in SAN, add that name to the SAN array.

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

.EXAMPLE
    .\Request-MachineCertificate.ps1 `
        -Template RequestLabActiveDirectoryTLSCertificate `
        -SAN 'app.corp.example' `
        -CertStoreLocation 'Cert:\LocalMachine\WebHosting' `
        -LogDirectory 'C:\Logs\CertificateEnrollment' -LogLevel Debug

    Places the issued certificate in an existing WebHosting store and enables
    detailed logging in the specified directory. No IIS binding is created.

.EXAMPLE
    .\Request-MachineCertificate.ps1 `
        -PendingRequestThumbprint 'F47AD2BFAF82ACA16005569392DB3D5D40696024'

    Automatically restores a destination saved by this version of the script.
    Supply CertStoreLocation explicitly for older pending requests without state.

.EXAMPLE
    .\Request-MachineCertificate.ps1 `
        -Template RequestLabActiveDirectoryTLSCertificate -UseADPolicy

    Forces direct Active Directory enrollment via ldap: for this new request.
    The configured default policy is not changed.

.EXAMPLE
    .\Request-MachineCertificate.ps1 `
        -Template RequestLabActiveDirectoryTLSCertificate `
        -Credential (Get-Credential)

    Uses explicit credentials with the configured default policy. The policy and
    discovered enrollment endpoints must support username/password authentication.

.EXAMPLE
    .\Request-MachineCertificate.ps1 `
        -Template RequestLabActiveDirectoryTLSCertificate `
        -SAN 'test.corp.domain.com' `
        -CertStoreLocation 'Cert:\LocalMachine\WebHosting' `
        -FriendlyName 'Lab TLS - test.corp.domain.com'

    Sets the display name on the issued certificate in WebHosting.
    The supplied name is remembered if the request remains pending.

.EXAMPLE
    .\Request-MachineCertificate.ps1 `
        -PendingRequestThumbprint 'F47AD2BFAF82ACA16005569392DB3D5D40696024' `
        -FriendlyName 'Lab TLS - updated display name'

    Resumes the original request and overrides any saved friendly name.
    Omit FriendlyName to restore the previously saved value automatically.

.INPUTS
    None. Parameters are supplied explicitly; pipeline input is not accepted.

.OUTPUTS
    System.Security.Cryptography.X509Certificates.X509Certificate2
    The issued certificate installed in the selected local machine application store.

.NOTES
    Author       : Michael Waterman
    Website      : https://michaelwaterman.nl
    Version      : 1.3.0.0
    Script ID    : 2bc8c7ad-463e-4b91-965a-46d99da1a0cb
    Last updated : 2026-10-06

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

    Without Credential or UserName, Windows manages authentication according to
    the selected policy and enrollment endpoints. Kerberos endpoints use the
    Windows integrated path. The script does not independently force or verify
    the negotiated protocol. Default policy selection does not mean merging all
    configured policies; Windows selects its configured default policy.

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

    [Parameter(ParameterSetName = 'Enroll')]
    [switch]$UseADPolicy,

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
    [int]$TimeoutMinutes = 0,
    [ValidateNotNullOrEmpty()]
    [string]$CertStoreLocation = 'Cert:\LocalMachine\My',
    [ValidateNotNullOrEmpty()]
    [ValidateLength(1, 260)]
    [ValidateScript({
        if ([string]::IsNullOrWhiteSpace($_) -or $_.Contains([string][char]0)) {
            throw 'FriendlyName must contain visible text and cannot contain null characters.'
        }
        $true
    })]
    [string]$FriendlyName,
    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory = "$env:SystemRoot\Temp",
    [ValidateSet('Info', 'Debug')]
    [string]$LogLevel = 'Info'
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

# Dedicated files rather than transcripts: never serialize credentials or arguments.
$script:LogFile = $null
$script:LogWriteFailed = $false
$script:LogThreshold = $LogLevel

function Write-EnrollmentLog {
    param([string]$Message, [ValidateSet('DEBUG','INFO','WARNING','ERROR')][string]$Level = 'INFO')
    if ($Level -eq 'DEBUG' -and $script:LogThreshold -ne 'Debug') { return }
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffzzz'), $Level, ($Message -replace '[\r\n]+',' ')
    try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 -ErrorAction Stop }
    catch {
        if (-not $script:LogWriteFailed) {
            Write-Warning 'Log write failed. Enrollment continues; check log directory access and free space.'
            $script:LogWriteFailed = $true
        }
    }
    Write-Verbose $line
}

function Get-TargetStoreName {
    param([string]$Path)
    if ($Path -notmatch '^Cert:\\LocalMachine\\([A-Za-z0-9_-]+)\\?$') {
        throw 'CertStoreLocation must be Cert:\LocalMachine\<store>, for example My or WebHosting.'
    }
    $name = $Matches[1]
    if ($name -in @('Root','CA','AuthRoot','TrustedPublisher','TrustedPeople','Disallowed','Request','AddressBook','Trust')) {
        throw "Store '$name' is not an application certificate destination. Use My, WebHosting or an existing custom application store."
    }
    $name
}

function Open-ApplicationStore {
    param([string]$Name)
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($Name, 'LocalMachine')
    try {
        $flags = [System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite -bor [System.Security.Cryptography.X509Certificates.OpenFlags]::OpenExistingOnly
        $store.Open($flags)
    } catch { $store.Close(); throw "Cannot open existing LocalMachine\$Name for writing. Create/configure the destination store before enrollment." }
    $store
}

# HKLM protects pending destination/display-name metadata from normal user writes. No secrets.
$stateRoot = 'HKLM:\SOFTWARE\MW\RequestMachineCertificate\Pending'
$statePath = $null
$locationPushed = $false
try {
    $logFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogDirectory)
    if (-not [System.IO.Path]::IsPathRooted($logFolder)) { throw 'LogDirectory must resolve to an absolute filesystem directory.' }
    [void][System.IO.Directory]::CreateDirectory($logFolder)
    $script:LogFile = Join-Path $logFolder ('Request-MachineCertificate_{0}_{1}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss'), [guid]::NewGuid().ToString('N'))
    New-Item -Path $script:LogFile -ItemType File -ErrorAction Stop | Out-Null
} catch { throw 'Cannot initialize the log file. Check LogDirectory and filesystem permissions. No enrollment was submitted.' }
Write-Host "Log file: $script:LogFile"
Write-EnrollmentLog "Starting mode=$($PSCmdlet.ParameterSetName); poll=$PollIntervalSeconds seconds; timeout=$TimeoutMinutes minutes."

try {
    if ($PSCmdlet.ParameterSetName -eq 'Resume') {
        $statePath = Join-Path $stateRoot $PendingRequestThumbprint.ToUpperInvariant()
        if (-not $PSBoundParameters.ContainsKey('CertStoreLocation') -and (Test-Path -LiteralPath $statePath)) {
            $CertStoreLocation = (Get-ItemProperty -LiteralPath $statePath -Name CertStoreLocation).CertStoreLocation
            Write-EnrollmentLog "Restored pending destination $CertStoreLocation."
        }
        if (-not $PSBoundParameters.ContainsKey('FriendlyName') -and (Test-Path -LiteralPath $statePath)) {
            # Older pending requests may have no FriendlyName property.
            $savedState = Get-ItemProperty -LiteralPath $statePath
            $savedName = $savedState.PSObject.Properties['FriendlyName']
            if ($savedName -and -not [string]::IsNullOrEmpty([string]$savedName.Value)) {
                $FriendlyName = [string]$savedName.Value
                Write-EnrollmentLog 'Restored pending friendly name.'
            }
        }
    }
    # Validate restored metadata too; parameter validators only run on bound values.
    if ($FriendlyName -and ($FriendlyName.Length -gt 260 -or [string]::IsNullOrWhiteSpace($FriendlyName) -or $FriendlyName.Contains([string][char]0))) {
        throw 'Saved FriendlyName is invalid. Supply a valid -FriendlyName when resuming.'
    }
    $targetName = Get-TargetStoreName $CertStoreLocation
    $CertStoreLocation = "Cert:\LocalMachine\$targetName"
    $preflightStore = Open-ApplicationStore $targetName
    $preflightStore.Close()
    Write-EnrollmentLog "Destination validated: $CertStoreLocation. Enrollment staging store: LocalMachine\My."

    if ($Credential -and ($PSBoundParameters.ContainsKey('UserName') -or $PSBoundParameters.ContainsKey('Password'))) {
        throw 'Use Credential OR UserName/Password, not both.'
    }
    if ($PSBoundParameters.ContainsKey('Password') -and -not $UserName) {
        throw 'Password requires UserName.'
    }
    if ($CepUrl -and (-not $CepUrl.IsAbsoluteUri -or $CepUrl.Scheme -ne 'https')) {
        throw 'CepUrl must be an absolute HTTPS CEP policy URL.'
    }
    if ($UseADPolicy -and $CepUrl) {
        throw 'Use either UseADPolicy or CepUrl, not both.'
    }
    if ($UseADPolicy -and ($Credential -or $UserName)) {
        throw 'UseADPolicy uses Windows integrated authentication; explicit credentials require a compatible default policy or CepUrl.'
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
    $locationPushed = $true
    if ($PSCmdlet.ParameterSetName -eq 'Resume') {
        $requestPath = "Cert:\LocalMachine\Request\$PendingRequestThumbprint"
        $pendingRequest = Get-Item -LiteralPath $requestPath -ErrorAction Stop
        Write-EnrollmentLog 'Retrieving existing request.' 'DEBUG'
        $result = Get-Certificate -Request $pendingRequest @retrieveParameters
        Write-EnrollmentLog "Retrieval status: $($result.Status)."
    } else {
        $submitParameters = @{
            Template = $Template
            CertStoreLocation = 'Cert:\LocalMachine\My'
            ErrorAction = 'Stop'
        }
        $policyDescription = 'Configured default machine enrollment policy'
        if ($UseADPolicy) {
            $submitParameters.Url = [uri]'ldap:'
            $policyDescription = 'Direct Active Directory policy (ldap:)'
        } elseif ($CepUrl) {
            $submitParameters.Url = $CepUrl
            $policyDescription = "Explicit CEP policy: $CepUrl"
        }
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
        Write-Host "Requesting template '$Template' using $policyDescription."
        if ($submitParameters.ContainsKey('SubjectName')) {
            Write-Host "Requested subject: $($submitParameters.SubjectName)"
        }
        Write-EnrollmentLog "Submitting template=$Template; policy=$policyDescription; authentication=$(if ($Credential) {'Explicit credential'} else {'Windows-managed'})."
        if ($submitParameters.ContainsKey('SubjectName')) { Write-EnrollmentLog "Subject: $($submitParameters.SubjectName)." }
        if ($submitParameters.ContainsKey('DnsName')) { Write-EnrollmentLog "DNS SANs: $($submitParameters.DnsName -join ', ')." }
        $result = Get-Certificate @submitParameters
        Write-EnrollmentLog "Submission status: $($result.Status)."
    }

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $pollAttempt = 0
    while ([string]$result.Status -eq 'Pending') {
        if (-not $result.Request) { throw 'CA returned Pending without a request object.' }
        $pendingRequest = $result.Request
        $thumbprint = $pendingRequest.Thumbprint
        if ($thumbprint -notmatch '^[A-Fa-f0-9]{40}$') { throw 'Invalid pending request thumbprint.' }
        $statePath = Join-Path $stateRoot $thumbprint.ToUpperInvariant()
        try {
            New-Item -Path $statePath -Force -ErrorAction Stop | Out-Null
            New-ItemProperty -LiteralPath $statePath -Name CertStoreLocation -Value $CertStoreLocation -PropertyType String -Force -ErrorAction Stop | Out-Null
            if ($FriendlyName) {
                New-ItemProperty -LiteralPath $statePath -Name FriendlyName -Value $FriendlyName -PropertyType String -Force -ErrorAction Stop | Out-Null
            }
        } catch {
            if ($FriendlyName) {
                Write-EnrollmentLog 'Pending metadata could not be fully saved. Supply FriendlyName and CertStoreLocation explicitly when resuming.' 'WARNING'
                Write-Warning 'Pending metadata was not fully saved. When resuming, also supply -FriendlyName with the intended display name.'
            }
            Write-EnrollmentLog "Could not persist destination. Resume must specify -CertStoreLocation '$CertStoreLocation'." 'WARNING'
            Write-Warning "Destination was not saved. When resuming, include -CertStoreLocation '$CertStoreLocation'."
        }
        Write-EnrollmentLog "Pending request=$thumbprint; destination=$CertStoreLocation."
        Write-Host "Pending approval. Request store thumbprint: $thumbprint"
        Write-Verbose "Resume with: .\Request-MachineCertificate.ps1 -PendingRequestThumbprint '$thumbprint' (add credentials if required)."
        if ($TimeoutMinutes -gt 0 -and $timer.Elapsed.TotalMinutes -ge $TimeoutMinutes) {
            Write-EnrollmentLog "Approval wait timed out; retained request=$thumbprint; destination=$CertStoreLocation." 'WARNING'
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
            Write-EnrollmentLog "Approval wait timed out; retained request=$thumbprint; destination=$CertStoreLocation." 'WARNING'
            throw "Approval wait timed out. Request retained. Resume with -PendingRequestThumbprint '$thumbprint'."
        }
        # The stored request carries the original enrollment server information.
        # PendingRetrieval has no Url parameter; no new submission is made.
        $pollAttempt++
        Write-EnrollmentLog "Checking approval attempt=$pollAttempt; elapsed=$($timer.Elapsed)."
        Write-Progress -Id 716 -Activity 'Waiting for certificate approval' `
            -Status "Checking CA (attempt $pollAttempt)..." -SecondsRemaining -1
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Checking approval (attempt $pollAttempt)..."
        Write-EnrollmentLog 'Retrieving existing request.' 'DEBUG'
        $result = Get-Certificate -Request $pendingRequest @retrieveParameters
        Write-EnrollmentLog "Retrieval status: $($result.Status)."
    }
    if ([string]$result.Status -ne 'Issued' -or -not $result.Certificate) {
        throw "Enrollment did not issue a certificate. Status: $($result.Status)."
    }
    $certificate = $result.Certificate
    $installed = Get-Item -LiteralPath "Cert:\LocalMachine\My\$($certificate.Thumbprint)"
    if (-not $installed.HasPrivateKey) { throw 'Issued certificate does not have an associated private key.' }
    Write-EnrollmentLog "Issued certificate=$($installed.Thumbprint); staging private key confirmed."
    if ($targetName -ne 'My') {
        $destination = Open-ApplicationStore $targetName
        $sourceStore = $null
        try {
            # Copy the certificate context and key association; no PFX export.
            $destination.Add($installed)
            $verified = @($destination.Certificates.Find([System.Security.Cryptography.X509Certificates.X509FindType]::FindByThumbprint, $installed.Thumbprint, $false))
            if ($verified.Count -ne 1 -or -not $verified[0].HasPrivateKey) {
                throw "Destination certificate verification failed. Source certificate retained in LocalMachine\My."
            }
            $finalCertificate = $verified[0]
            $sourceStore = Open-ApplicationStore 'My'
            # Remove only the source store entry, never delete the underlying key.
            $sourceStore.Remove($installed)
            $installed = $finalCertificate
            Write-EnrollmentLog "Moved issued certificate to $CertStoreLocation; private key association confirmed."
        } finally {
            if ($sourceStore) { $sourceStore.Close() }
            $destination.Close()
        }
    }
    if ($FriendlyName) {
        # Reopen the final store and select by thumbprint, never by display name.
        $nameStore = $null
        try {
            $nameStore = Open-ApplicationStore $targetName
            $matchesByThumbprint = @($nameStore.Certificates.Find([System.Security.Cryptography.X509Certificates.X509FindType]::FindByThumbprint, $installed.Thumbprint, $false))
            if ($matchesByThumbprint.Count -ne 1 -or -not $matchesByThumbprint[0].HasPrivateKey) {
                throw 'Final certificate/private-key verification failed before setting FriendlyName.'
            }
            $matchesByThumbprint[0].FriendlyName = $FriendlyName
            $nameStore.Close()
            $nameStore = $null
            # Read back through a fresh store context to verify persistence.
            $nameStore = Open-ApplicationStore $targetName
            $namedCertificate = @($nameStore.Certificates.Find([System.Security.Cryptography.X509Certificates.X509FindType]::FindByThumbprint, $installed.Thumbprint, $false))
            if ($namedCertificate.Count -ne 1 -or -not $namedCertificate[0].HasPrivateKey -or $namedCertificate[0].FriendlyName -cne $FriendlyName) {
                throw 'FriendlyName persistence/private-key verification failed.'
            }
            $installed = $namedCertificate[0]
            Write-Host "Friendly name: $FriendlyName"
            Write-EnrollmentLog "Friendly name verified in ${CertStoreLocation}: $FriendlyName."
        } catch {
            Write-EnrollmentLog ('Certificate installed, but FriendlyName could not be set or verified: exception={0}; HRESULT={1}.' -f $_.Exception.GetType().FullName, $_.Exception.HResult) 'WARNING'
            Write-Warning "Certificate $($installed.Thumbprint) is already installed in $CertStoreLocation, but its friendly name could not be set or verified. Check the store and update the name locally; do not submit another request. $($_.Exception.Message)"
        } finally {
            if ($nameStore) { $nameStore.Close() }
        }
    }
    if ($statePath -and (Test-Path -LiteralPath $statePath)) {
        try { Remove-Item -LiteralPath $statePath -ErrorAction Stop }
        catch { Write-EnrollmentLog 'Certificate installed, but pending destination metadata cleanup failed.' 'WARNING' }
    }
    Write-Host "Certificate installed in ${CertStoreLocation}: $($installed.Thumbprint)"
    Write-EnrollmentLog "Success: subject=$($installed.Subject); certificate=$($installed.Thumbprint); expires=$($installed.NotAfter.ToString('o')); store=$CertStoreLocation."
    # Return the actual certificate so callers can pipe it or assign it to a variable.
    $installed
} catch {
    # Do not automatically retry failures or resubmit a CSR. Pending requests remain
    # available for explicit resumption after fixing connectivity/authentication.
    Write-EnrollmentLog ('Enrollment stopped: errorId={0}; exception={1}; HRESULT={2}. Check the console error. Existing requests and keys are retained; if already issued, inspect LocalMachine\My and the target store before submitting another request.' -f $_.FullyQualifiedErrorId, $_.Exception.GetType().FullName, $_.Exception.HResult) 'ERROR'
    Write-Verbose 'Enrollment stopped. Any existing pending request and key have been retained.'
    throw
} finally {
    Write-Progress -Id 716 -Activity 'Waiting for certificate approval' -Completed
    if ($locationPushed) { Pop-Location }
    Write-EnrollmentLog 'Execution finished.'
}
