<#
.SYNOPSIS
Gets assembly reference information.

.DESCRIPTION
Not supported for use during task execution. This function is only intended to help developers resolve the minimal set of DLLs that need to be bundled when consuming the VSTS REST SDK or TFS Extended Client SDK. The interface and output may change between patch releases of the VSTS Task SDK.

Only a subset of the referenced assemblies may actually be required, depending on the functionality used by your task. It is best to bundle only the DLLs required for your scenario.

Walks an assembly's references to determine all of it's dependencies. Also walks the references of the dependencies, and so on until all nested dependencies have been traversed. Dependencies are searched for in the directory of the specified assembly. NET Framework assemblies are omitted.

See https://github.com/Microsoft/azure-pipelines-task-lib/tree/master/powershell/Docs/UsingOM.md for reliable usage when working with the TFS extended client SDK from a task.

.PARAMETER LiteralPath
Assembly to walk.

.EXAMPLE
Get-VstsAssemblyReference -LiteralPath C:\nuget\microsoft.teamfoundationserver.client.14.102.0\lib\net45\Microsoft.TeamFoundation.Build2.WebApi.dll
#>
function Get-AssemblyReference {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath)

    $ErrorActionPreference = 'Stop'
    Write-Warning "Not supported for use during task execution. This function is only intended to help developers resolve the minimal set of DLLs that need to be bundled when consuming the VSTS REST SDK or TFS Extended Client SDK. The interface and output may change between patch releases of the VSTS Task SDK."
    Write-Output ''
    Write-Warning "Only a subset of the referenced assemblies may actually be required, depending on the functionality used by your task. It is best to bundle only the DLLs required for your scenario."
    $directory = [System.IO.Path]::GetDirectoryName($LiteralPath)
    $hashtable = @{ }
    $queue = @( [System.Reflection.Assembly]::ReflectionOnlyLoadFrom($LiteralPath).GetName() )
    while ($queue.Count) {
        # Add a blank line between assemblies.
        Write-Output ''

        # Pop.
        $assemblyName = $queue[0]
        $queue = @( $queue | Select-Object -Skip 1 )

        # Attempt to find the assembly in the same directory.
        $assembly = $null
        $path = "$directory\$($assemblyName.Name).dll"
        if ((Test-Path -LiteralPath $path -PathType Leaf)) {
            $assembly = [System.Reflection.Assembly]::ReflectionOnlyLoadFrom($path)
        } else {
            $path = "$directory\$($assemblyName.Name).exe"
            if ((Test-Path -LiteralPath $path -PathType Leaf)) {
                $assembly = [System.Reflection.Assembly]::ReflectionOnlyLoadFrom($path)
            }
        }

        # Make sure the assembly full name matches, not just the file name.
        if ($assembly -and $assembly.GetName().FullName -ne $assemblyName.FullName) {
            $assembly = $null
        }

        # Print the assembly.
        if ($assembly) {
            Write-Output $assemblyName.FullName
        } else {
            if ($assemblyName.FullName -eq 'Newtonsoft.Json, Version=6.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed') {
                Write-Warning "*** NOT FOUND $($assemblyName.FullName) *** This is an expected condition when using the HTTP clients from the 15.x VSTS REST SDK. Use Get-VstsVssHttpClient to load the HTTP clients (which applies a binding redirect assembly resolver for Newtonsoft.Json). Otherwise you will need to manage the binding redirect yourself."
            } else {
                Write-Warning "*** NOT FOUND $($assemblyName.FullName) ***"
            }
    
            continue
        }

        # Walk the references.
        $refAssemblyNames = @( $assembly.GetReferencedAssemblies() )
        for ($i = 0 ; $i -lt $refAssemblyNames.Count ; $i++) {
            $refAssemblyName = $refAssemblyNames[$i]

            # Skip framework assemblies.
            $fxPaths = @(
                "$env:windir\Microsoft.Net\Framework64\v4.0.30319\$($refAssemblyName.Name).dll"
                "$env:windir\Microsoft.Net\Framework64\v4.0.30319\WPF\$($refAssemblyName.Name).dll"
            )
            $fxPath = $fxPaths |
                Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
                Where-Object { [System.Reflection.Assembly]::ReflectionOnlyLoadFrom($_).GetName().FullName -eq $refAssemblyName.FullName }
            if ($fxPath) {
                continue
            }

            # Print the reference.
            Write-Output "    $($refAssemblyName.FullName)"

            # Add new references to the queue.
            if (!$hashtable[$refAssemblyName.FullName]) {
                $queue += $refAssemblyName
                $hashtable[$refAssemblyName.FullName] = $true
            }
        }
    }
}

<#
.SYNOPSIS
Gets a credentials object that can be used with the TFS extended client SDK.

.DESCRIPTION
The agent job token is used to construct the credentials object. The identity associated with the token depends on the scope selected in the build/release definition (either the project collection build/release service identity, or the project build/release service identity).

Refer to Get-VstsTfsService for a more simple to get a TFS service object.

*** DO NOT USE Agent.ServerOMDirectory *** See https://github.com/Microsoft/azure-pipelines-task-lib/tree/master/powershell/Docs/UsingOM.md for reliable usage when working with the TFS extended client SDK from a task.

.PARAMETER OMDirectory
Directory where the extended client object model DLLs are located. If the DLLs for the credential types are not already loaded, an attempt will be made to automatically load the required DLLs from the object model directory.

If not specified, defaults to the directory of the entry script for the task.

*** DO NOT USE Agent.ServerOMDirectory *** See https://github.com/Microsoft/azure-pipelines-task-lib/tree/master/powershell/Docs/UsingOM.md for reliable usage when working with the TFS extended client SDK from a task.

.EXAMPLE
#
# Refer to Get-VstsTfsService for a more simple way to get a TFS service object.
#
$credentials = Get-VstsTfsClientCredentials
Add-Type -LiteralPath "$PSScriptRoot\Microsoft.TeamFoundation.VersionControl.Client.dll"
$tfsTeamProjectCollection = New-Object Microsoft.TeamFoundation.Client.TfsTeamProjectCollection(
    (Get-VstsTaskVariable -Name 'System.TeamFoundationCollectionUri' -Require),
    $credentials)
$versionControlServer = $tfsTeamProjectCollection.GetService([Microsoft.TeamFoundation.VersionControl.Client.VersionControlServer])
$versionControlServer.GetItems('$/*').Items | Format-List
#>
function Get-TfsClientCredentials {
    [CmdletBinding()]
    param([string]$OMDirectory)

    Trace-EnteringInvocation -InvocationInfo $MyInvocation
    $originalErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Stop'

        # Get the endpoint.
        $endpoint = Get-Endpoint -Name SystemVssConnection -Require

        # Test if the Newtonsoft.Json DLL exists in the OM directory.
        $newtonsoftDll = [System.IO.Path]::Combine($OMDirectory, "Newtonsoft.Json.dll")
        Write-Verbose "Testing file path: '$newtonsoftDll'"
        if (!(Test-Path -LiteralPath $newtonsoftDll -PathType Leaf)) {
            Write-Verbose 'Not found. Rethrowing exception.'
            throw
        }

        # Add a binding redirect and try again. Parts of the Dev15 preview SDK have a
        # dependency on the 6.0.0.0 Newtonsoft.Json DLL, while other parts reference
        # the 8.0.0.0 Newtonsoft.Json DLL.
        Write-Verbose "Adding assembly resolver."
        $onAssemblyResolve = [System.ResolveEventHandler] {
            param($sender, $e)

            if ($e.Name -like 'Newtonsoft.Json, *') {
                Write-Verbose "Resolving '$($e.Name)' to '$newtonsoftDll'."

                return [System.Reflection.Assembly]::LoadFrom($newtonsoftDll)
            }

            return $null
        }
        [System.AppDomain]::CurrentDomain.add_AssemblyResolve($onAssemblyResolve)

        # Validate the type can be found.
        $null = Get-OMType -TypeName 'Microsoft.TeamFoundation.Client.TfsClientCredentials' -OMKind 'ExtendedClient' -OMDirectory $OMDirectory -Require

        # Construct the credentials.
        $credentials = New-Object Microsoft.TeamFoundation.Client.TfsClientCredentials($false) # Do not use default credentials.
        $credentials.AllowInteractive = $false
        $credentials.Federated = New-Object Microsoft.TeamFoundation.Client.OAuthTokenCredential([string]$endpoint.auth.parameters.AccessToken)
        return $credentials
    } catch {
        $ErrorActionPreference = $originalErrorActionPreference
        Write-Error $_
    } finally {
        Trace-LeavingInvocation -InvocationInfo $MyInvocation
    }
}

<#
.SYNOPSIS
Gets a TFS extended client service.

.DESCRIPTION
Gets an instance of an ITfsTeamProjectCollectionObject.

*** DO NOT USE Agent.ServerOMDirectory *** See https://github.com/Microsoft/azure-pipelines-task-lib/tree/master/powershell/Docs/UsingOM.md for reliable usage when working with the TFS extended client SDK from a task.

.PARAMETER TypeName
Namespace-qualified type name of the service to get.

.PARAMETER OMDirectory
Directory where the extended client object model DLLs are located. If the DLLs for the types are not already loaded, an attempt will be made to automatically load the required DLLs from the object model directory.

If not specified, defaults to the directory of the entry script for the task.

*** DO NOT USE Agent.ServerOMDirectory *** See https://github.com/Microsoft/azure-pipelines-task-lib/tree/master/powershell/Docs/UsingOM.md for reliable usage when working with the TFS extended client SDK from a task.

.PARAMETER Uri
URI to use when initializing the service. If not specified, defaults to System.TeamFoundationCollectionUri.

.PARAMETER TfsClientCredentials
Credentials to use when initializing the service. If not specified, the default uses the agent job token to construct the credentials object. The identity associated with the token depends on the scope selected in the build/release definition (either the project collection build/release service identity, or the project build/release service identity).

.EXAMPLE
$versionControlServer = Get-VstsTfsService -TypeName Microsoft.TeamFoundation.VersionControl.Client.VersionControlServer
$versionControlServer.GetItems('$/*').Items | Format-List
#>
function Get-TfsService {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TypeName,

        [string]$OMDirectory,

        [string]$Uri,

        $TfsClientCredentials)

    Trace-EnteringInvocation -InvocationInfo $MyInvocation
    $originalErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Stop'

        # Default the URI to the collection URI.
        if (!$Uri) {
            $Uri = Get-TaskVariable -Name System.TeamFoundationCollectionUri -Require
        }

        # Default the credentials.
        if (!$TfsClientCredentials) {
            $TfsClientCredentials = Get-TfsClientCredentials -OMDirectory $OMDirectory
        }

        # Validate the project collection type can be loaded.
        $null = Get-OMType -TypeName 'Microsoft.TeamFoundation.Client.TfsTeamProjectCollection' -OMKind 'ExtendedClient' -OMDirectory $OMDirectory -Require

        # Load the project collection object.
        $tfsTeamProjectCollection = New-Object Microsoft.TeamFoundation.Client.TfsTeamProjectCollection($Uri, $TfsClientCredentials)

        # Validate the requested type can be loaded.
        $type = Get-OMType -TypeName $TypeName -OMKind 'ExtendedClient' -OMDirectory $OMDirectory -Require

        # Return the service object.
        return $tfsTeamProjectCollection.GetService($type)
    } catch {
        $ErrorActionPreference = $originalErrorActionPreference
        Write-Error $_
    } finally {
        Trace-LeavingInvocation -InvocationInfo $MyInvocation
    }
}

<#
.SYNOPSIS
Gets a credentials object that can be used with the VSTS REST SDK.

.DESCRIPTION
The agent job token is used to construct the credentials object. The identity associated with the token depends on the scope selected in the build/release definition (either the project collection build/release service identity, or the project service build/release identity).

Refer to Get-VstsVssHttpClient for a more simple to get a VSS HTTP client.

*** DO NOT USE Agent.ServerOMDirectory *** See https://github.com/Microsoft/azure-pipelines-task-lib/tree/master/powershell/Docs/UsingOM.md for reliable usage when working with the VSTS REST SDK from a task.

.PARAMETER OMDirectory
Directory where the REST client object model DLLs are located. If the DLLs for the credential types are not already loaded, an attempt will be made to automatically load the required DLLs from the object model directory.

If not specified, defaults to the directory of the entry script for the task.

*** DO NOT USE Agent.ServerOMDirectory *** See https://github.com/Microsoft/azure-pipelines-task-lib/tree/master/powershell/Docs/UsingOM.md for reliable usage when working with the VSTS REST SDK from a task.

.EXAMPLE
#
# Refer to Get-VstsTfsService for a more simple way to get a TFS service object.
#
# This example works using the 14.x .NET SDK. A Newtonsoft.Json 6.0 to 8.0 binding
# redirect may be required when working with the 15.x SDK. Or use Get-VstsVssHttpClient
# to avoid managing the binding redirect.
#
$vssCredentials = Get-VstsVssCredentials
$collectionUrl = New-Object System.Uri((Get-VstsTaskVariable -Name 'System.TeamFoundationCollectionUri' -Require))
Add-Type -LiteralPath "$PSScriptRoot\Microsoft.TeamFoundation.Core.WebApi.dll"
$projectHttpClient = New-Object Microsoft.TeamFoundation.Core.WebApi.ProjectHttpClient($collectionUrl, $vssCredentials)
$projectHttpClient.GetProjects().Result
#>
function Get-VssCredentials {
    [CmdletBinding()]
    param([string]$OMDirectory)

    Trace-EnteringInvocation -InvocationInfo $MyInvocation
    $originalErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Stop'

        # Get the endpoint.
        $endpoint = Get-Endpoint -Name SystemVssConnection -Require

        # Check if the VssOAuthAccessTokenCredential type is available.
        if ((Get-OMType -TypeName 'Microsoft.VisualStudio.Services.OAuth.VssOAuthAccessTokenCredential' -OMKind 'WebApi' -OMDirectory $OMDirectory)) {
            # Create the federated credential.
            $federatedCredential = New-Object Microsoft.VisualStudio.Services.OAuth.VssOAuthAccessTokenCredential($endpoint.auth.parameters.AccessToken)
        } else {
            # Validate the fallback type can be loaded.
            $null = Get-OMType -TypeName 'Microsoft.VisualStudio.Services.Client.VssOAuthCredential' -OMKind 'WebApi' -OMDirectory $OMDirectory -Require

            # Create the federated credential.
            $federatedCredential = New-Object Microsoft.VisualStudio.Services.Client.VssOAuthCredential($endpoint.auth.parameters.AccessToken)
        }

        # Return the credentials.
        return New-Object Microsoft.VisualStudio.Services.Common.VssCredentials(
            (New-Object Microsoft.VisualStudio.Services.Common.WindowsCredential($false)), # Do not use default credentials.
            $federatedCredential,
            [Microsoft.VisualStudio.Services.Common.CredentialPromptType]::DoNotPrompt)
    } catch {
        $ErrorActionPreference = $originalErrorActionPreference
        Write-Error $_
    } finally {
        Trace-LeavingInvocation -InvocationInfo $MyInvocation
    }
}

<#
.SYNOPSIS
Gets a VSS HTTP client.

.DESCRIPTION
Gets an instance of an VSS HTTP client.

*** DO NOT USE Agent.ServerOMDirectory *** See https://github.com/Microsoft/azure-pipelines-task-lib/tree/master/powershell/Docs/UsingOM.md for reliable usage when working with the VSTS REST SDK from a task.

.PARAMETER TypeName
Namespace-qualified type name of the HTTP client to get.

.PARAMETER OMDirectory
Directory where the REST client object model DLLs are located. If the DLLs for the credential types are not already loaded, an attempt will be made to automatically load the required DLLs from the object model directory.

If not specified, defaults to the directory of the entry script for the task.

*** DO NOT USE Agent.ServerOMDirectory *** See https://github.com/Microsoft/azure-pipelines-task-lib/tree/master/powershell/Docs/UsingOM.md for reliable usage when working with the VSTS REST SDK from a task.

# .PARAMETER Uri
# URI to use when initializing the HTTP client. If not specified, defaults to System.TeamFoundationCollectionUri.

# .PARAMETER VssCredentials
# Credentials to use when initializing the HTTP client. If not specified, the default uses the agent job token to construct the credentials object. The identity associated with the token depends on the scope selected in the build/release definition (either the project collection build/release service identity, or the project build/release service identity).

# .PARAMETER WebProxy
# WebProxy to use when initializing the HTTP client. If not specified, the default uses the proxy configuration agent current has.

# .PARAMETER ClientCert
# ClientCert to use when initializing the HTTP client. If not specified, the default uses the client certificate agent current has.

# .PARAMETER IgnoreSslError
# Skip SSL server certificate validation on all requests made by this HTTP client. If not specified, the default is to validate SSL server certificate.

.EXAMPLE
$projectHttpClient = Get-VstsVssHttpClient -TypeName Microsoft.TeamFoundation.Core.WebApi.ProjectHttpClient
$projectHttpClient.GetProjects().Result
#>
function Get-VssHttpClient {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TypeName,

        [string]$OMDirectory,

        [string]$Uri,

        $VssCredentials,
        
        $WebProxy = (Get-WebProxy),
        
        $ClientCert = (Get-ClientCertificate),
        
        [switch]$IgnoreSslError)

    Trace-EnteringInvocation -InvocationInfo $MyInvocation
    $originalErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Stop'

        # Default the URI to the collection URI.
        if (!$Uri) {
            $Uri = Get-TaskVariable -Name System.TeamFoundationCollectionUri -Require
        }

        # Cast the URI.
        [uri]$Uri = New-Object System.Uri($Uri)

        # Default the credentials.
        if (!$VssCredentials) {
            $VssCredentials = Get-VssCredentials -OMDirectory $OMDirectory
        }

        # Validate the type can be loaded.
        $null = Get-OMType -TypeName $TypeName -OMKind 'WebApi' -OMDirectory $OMDirectory -Require

        # Update proxy setting for vss http client
        [Microsoft.VisualStudio.Services.Common.VssHttpMessageHandler]::DefaultWebProxy = $WebProxy
        
        # Update client certificate setting for vss http client
        $null = Get-OMType -TypeName 'Microsoft.VisualStudio.Services.Common.VssHttpRequestSettings' -OMKind 'WebApi' -OMDirectory $OMDirectory -Require
        $null = Get-OMType -TypeName 'Microsoft.VisualStudio.Services.WebApi.VssClientHttpRequestSettings' -OMKind 'WebApi' -OMDirectory $OMDirectory -Require
        [Microsoft.VisualStudio.Services.Common.VssHttpRequestSettings]$Settings = [Microsoft.VisualStudio.Services.WebApi.VssClientHttpRequestSettings]::Default.Clone()

        if ($ClientCert) {
            $null = Get-OMType -TypeName 'Microsoft.VisualStudio.Services.WebApi.VssClientCertificateManager' -OMKind 'WebApi' -OMDirectory $OMDirectory -Require
            $null = [Microsoft.VisualStudio.Services.WebApi.VssClientCertificateManager]::Instance.ClientCertificates.Add($ClientCert)
            
            $Settings.ClientCertificateManager = [Microsoft.VisualStudio.Services.WebApi.VssClientCertificateManager]::Instance
        }        

        # Skip SSL server certificate validation
        [bool]$SkipCertValidation = (Get-TaskVariable -Name Agent.SkipCertValidation -AsBool) -or $IgnoreSslError
        if ($SkipCertValidation) {
            if ($Settings.GetType().GetProperty('ServerCertificateValidationCallback')) {
                Write-Verbose "Ignore any SSL server certificate validation errors.";
                $Settings.ServerCertificateValidationCallback = [VstsTaskSdk.VstsHttpHandlerSettings]::UnsafeSkipServerCertificateValidation
            }
            else {
                # OMDirectory has older version of Microsoft.VisualStudio.Services.Common.dll
                Write-Verbose "The version of 'Microsoft.VisualStudio.Services.Common.dll' does not support skip SSL server certificate validation."
            }
        }

        # Try to construct the HTTP client.
        Write-Verbose "Constructing HTTP client."
        try {
            return New-Object $TypeName($Uri, $VssCredentials, $Settings)
        } catch {
            # Rethrow if the exception is not due to Newtonsoft.Json DLL not found.
            if ($_.Exception.InnerException -isnot [System.IO.FileNotFoundException] -or
                $_.Exception.InnerException.FileName -notlike 'Newtonsoft.Json, *') {

                throw
            }

            # Default the OMDirectory to the directory of the entry script for the task.
            if (!$OMDirectory) {
                $OMDirectory = [System.IO.Path]::GetFullPath("$PSScriptRoot\..\..")
                Write-Verbose "Defaulted OM directory to: '$OMDirectory'"
            }

            # Test if the Newtonsoft.Json DLL exists in the OM directory.
            $newtonsoftDll = [System.IO.Path]::Combine($OMDirectory, "Newtonsoft.Json.dll")
            Write-Verbose "Testing file path: '$newtonsoftDll'"
            if (!(Test-Path -LiteralPath $newtonsoftDll -PathType Leaf)) {
                Write-Verbose 'Not found. Rethrowing exception.'
                throw
            }

            # Add a binding redirect and try again. Parts of the Dev15 preview SDK have a
            # dependency on the 6.0.0.0 Newtonsoft.Json DLL, while other parts reference
            # the 8.0.0.0 Newtonsoft.Json DLL.
            Write-Verbose "Adding assembly resolver."
            $onAssemblyResolve = [System.ResolveEventHandler] {
                param($sender, $e)

                if ($e.Name -like 'Newtonsoft.Json, *') {
                    Write-Verbose "Resolving '$($e.Name)'"
                    return [System.Reflection.Assembly]::LoadFrom($newtonsoftDll)
                }

                Write-Verbose "Unable to resolve assembly name '$($e.Name)'"
                return $null
            }
            [System.AppDomain]::CurrentDomain.add_AssemblyResolve($onAssemblyResolve)
            try {
                # Try again to construct the HTTP client.
                Write-Verbose "Trying again to construct the HTTP client."
                return New-Object $TypeName($Uri, $VssCredentials, $Settings)
            } finally {
                # Unregister the assembly resolver.
                Write-Verbose "Removing assemlby resolver."
                [System.AppDomain]::CurrentDomain.remove_AssemblyResolve($onAssemblyResolve)
            }
        }
    } catch {
        $ErrorActionPreference = $originalErrorActionPreference
        Write-Error $_
    } finally {
        Trace-LeavingInvocation -InvocationInfo $MyInvocation
    }
}

<#
.SYNOPSIS
Gets a VstsTaskSdk.VstsWebProxy

.DESCRIPTION
Gets an instance of a VstsTaskSdk.VstsWebProxy that has same proxy configuration as Build/Release agent.

VstsTaskSdk.VstsWebProxy implement System.Net.IWebProxy interface.

.EXAMPLE
$webProxy = Get-VstsWebProxy
$webProxy.GetProxy(New-Object System.Uri("https://github.com/Microsoft/azure-pipelines-task-lib"))
#>
function Get-WebProxy {
    [CmdletBinding()]
    param()

    Trace-EnteringInvocation -InvocationInfo $MyInvocation
    try {
        # Min agent version that supports proxy
        Assert-Agent -Minimum '2.105.7'

        $proxyUrl = Get-TaskVariable -Name Agent.ProxyUrl
        $proxyUserName = Get-TaskVariable -Name Agent.ProxyUserName
        $proxyPassword = Get-TaskVariable -Name Agent.ProxyPassword
        $proxyBypassListJson = Get-TaskVariable -Name Agent.ProxyBypassList
        [string[]]$ProxyBypassList = ConvertFrom-Json -InputObject $ProxyBypassListJson
        
        return New-Object -TypeName VstsTaskSdk.VstsWebProxy -ArgumentList @($proxyUrl, $proxyUserName, $proxyPassword, $proxyBypassList)
    }
    finally {
        Trace-LeavingInvocation -InvocationInfo $MyInvocation
    }
}

<#
.SYNOPSIS
Gets a client certificate for current connected TFS instance

.DESCRIPTION
Gets an instance of a X509Certificate2 that is the client certificate Build/Release agent used.

.EXAMPLE
$x509cert = Get-ClientCertificate
WebRequestHandler.ClientCertificates.Add(x509cert)
#>
function Get-ClientCertificate {
    [CmdletBinding()]
    param()

    Trace-EnteringInvocation -InvocationInfo $MyInvocation
    try {
        # Min agent version that supports client certificate
        Assert-Agent -Minimum '2.122.0'

        [string]$clientCert = Get-TaskVariable -Name Agent.ClientCertArchive
        [string]$clientCertPassword = Get-TaskVariable -Name Agent.ClientCertPassword
        
        if ($clientCert -and (Test-Path -LiteralPath $clientCert -PathType Leaf)) {
            return New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList @($clientCert, $clientCertPassword)
        }        
    }
    finally {
        Trace-LeavingInvocation -InvocationInfo $MyInvocation
    }
}

########################################
# Private functions.
########################################
function Get-OMType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TypeName,

        [ValidateSet('ExtendedClient', 'WebApi')]
        [Parameter(Mandatory = $true)]
        [string]$OMKind,

        [string]$OMDirectory,

        [switch]$Require)

    Trace-EnteringInvocation -InvocationInfo $MyInvocation
    try {
        # Default the OMDirectory to the directory of the entry script for the task.
        if (!$OMDirectory) {
            $OMDirectory = [System.IO.Path]::GetFullPath("$PSScriptRoot\..\..")
            Write-Verbose "Defaulted OM directory to: '$OMDirectory'"
        }

        # Try to load the type.
        $errorRecord = $null
        Write-Verbose "Testing whether type can be loaded: '$TypeName'"
        $ErrorActionPreference = 'Ignore'
        try {
            # Failure when attempting to cast a string to a type, transfers control to the
            # catch handler even when the error action preference is ignore. The error action
            # is set to Ignore so the $Error variable is not polluted.
            $type = [type]$TypeName

            # Success.
            Write-Verbose "The type was loaded successfully."
            return $type
        } catch {
            # Store the error record.
            $errorRecord = $_
        }

        $ErrorActionPreference = 'Stop'
        Write-Verbose "The type was not loaded."

        # Build a list of candidate DLL file paths from the namespace.
        $dllPaths = @( )
        $namespace = $TypeName
        while ($namespace.LastIndexOf('.') -gt 0) {
            # Trim the next segment from the namespace.
            $namespace = $namespace.SubString(0, $namespace.LastIndexOf('.'))

            # Derive potential DLL file paths based on the namespace and OM kind (i.e. extended client vs web API).
            if ($OMKind -eq 'ExtendedClient') {
                if ($namespace -like 'Microsoft.TeamFoundation.*') {
                    $dllPaths += [System.IO.Path]::Combine($OMDirectory, "$namespace.dll")
                }
            } else {
                if ($namespace -like 'Microsoft.TeamFoundation.*' -or
                    $namespace -like 'Microsoft.VisualStudio.Services' -or
                    $namespace -like 'Microsoft.VisualStudio.Services.*') {

                    $dllPaths += [System.IO.Path]::Combine($OMDirectory, "$namespace.WebApi.dll")
                    $dllPaths += [System.IO.Path]::Combine($OMDirectory, "$namespace.dll")
                }
            }
        }

        foreach ($dllPath in $dllPaths) {
            # Check whether the DLL exists.
            Write-Verbose "Testing leaf path: '$dllPath'"
            if (!(Test-Path -PathType Leaf -LiteralPath "$dllPath")) {
                Write-Verbose "Not found."
                continue
            }

            # Load the DLL.
            Write-Verbose "Loading assembly: $dllPath"
            try {
                Add-Type -LiteralPath $dllPath
            } catch {
                # Write the information to the verbose stream and proceed to attempt to load the requested type.
                #
                # The requested type may successfully load now. For example, the type used with the 14.0 Web API for the
                # federated credential (VssOAuthCredential) resides in Microsoft.VisualStudio.Services.Client.dll. Even
                # though loading the DLL results in a ReflectionTypeLoadException when Microsoft.ServiceBus.dll (approx 3.75mb)
                # is not present, enough types are loaded to use the VssOAuthCredential federated credential with the Web API
                # HTTP clients.
                Write-Verbose "$($_.Exception.GetType().FullName): $($_.Exception.Message)"
                if ($_.Exception -is [System.Reflection.ReflectionTypeLoadException]) {
                    for ($i = 0 ; $i -lt $_.Exception.LoaderExceptions.Length ; $i++) {
                        $loaderException = $_.Exception.LoaderExceptions[$i]
                        Write-Verbose "LoaderExceptions[$i]: $($loaderException.GetType().FullName): $($loaderException.Message)"
                    }
                }
            }

            # Try to load the type.
            Write-Verbose "Testing whether type can be loaded: '$TypeName'"
            $ErrorActionPreference = 'Ignore'
            try {
                # Failure when attempting to cast a string to a type, transfers control to the
                # catch handler even when the error action preference is ignore. The error action
                # is set to Ignore so the $Error variable is not polluted.
                $type = [type]$TypeName

                # Success.
                Write-Verbose "The type was loaded successfully."
                return $type
            } catch {
                $errorRecord = $_
            }

            $ErrorActionPreference = 'Stop'
            Write-Verbose "The type was not loaded."
        }

        # Check whether to propagate the error.
        if ($Require) {
            Write-Error $errorRecord
        }
    } finally {
        Trace-LeavingInvocation -InvocationInfo $MyInvocation
    }
}

# SIG # Begin signature block
# MIInbgYJKoZIhvcNAQcCoIInXzCCJ1sCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAUzS4jcGbPcbP5
# huWBLXFskogpcnM4uaxHq7HUnQj8cKCCDMkwggYEMIID7KADAgECAhMzAAACHPrN
# xZvoL37EAAAAAAIcMA0GCSqGSIb3DQEBCwUAMFcxCzAJBgNVBAYTAlVTMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBD
# b2RlIFNpZ25pbmcgUENBIDIwMjQwHhcNMjYwNDE2MTg1OTQxWhcNMjcwNDE1MTg1
# OTQxWjB0MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYD
# VQQDExVNaWNyb3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IB
# DwAwggEKAoIBAQDVsZfgOKmM31HPfoWOoNEiw0SlCiIxUMC0I9NMWbucKOw/e9lP
# oAoehQVu6SG65V4EPzrYsnBnFPNoi4/HoOdjhz1qkrEt4I6tEcxXU6oOeY9zGveC
# /3iBeuhLYxM3M/PkcUoebF+Nednm8OkdSPoDu8imViHPQq/8CQUu0WRR4rE+dMRf
# rpVqfmNi2qWCX94T4MsepijGVkwE//tJg0ryAiYdHT34LSnlG/RSBZmQRGWZ5g8j
# qnKjRParSqMft1gvjuUTVgtWNZfgcLFSK5Wa0myrq8OPcgTGGsRgun+tnSS+IxDT
# xVsAPH1OzvPjwomguByhUe/OcvUN0D5Wmp7xAgMBAAGjggGqMIIBpjAOBgNVHQ8B
# Af8EBAMCB4AwHwYDVR0lBBgwFgYKKwYBBAGCN0wIAQYIKwYBBQUHAwMwHQYDVR0O
# BBYEFNoH7a2YDjOSwpkp6DHcmUS7J+0yMFQGA1UdEQRNMEukSTBHMS0wKwYDVQQL
# EyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxFjAUBgNVBAUT
# DTIzMDAxMis1MDc1NjkwHwYDVR0jBBgwFoAUf1k/VCHarU/vBeXmo9ctBpQSCDEw
# YAYDVR0fBFkwVzBVoFOgUYZPaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9w
# cy9jcmwvTWljcm9zb2Z0JTIwQ29kZSUyMFNpZ25pbmclMjBQQ0ElMjAyMDI0LmNy
# bDBtBggrBgEFBQcBAQRhMF8wXQYIKwYBBQUHMAKGUWh0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwQ29kZSUyMFNpZ25pbmcl
# MjBQQ0ElMjAyMDI0LmNydDAMBgNVHRMBAf8EAjAAMA0GCSqGSIb3DQEBCwUAA4IC
# AQAUnEqhaRXe0T3hIJjvdQErEkrA/7bByjn6t5IArODkkRjzkYwtKMc2yYj2quaN
# rLutWw2YZcngKPy1b71YyDJQTy4NDRwaSh9Tw5thrk3NmcPrAHia5vtcBJ1CgtKK
# 7mQbIcQ22d/N3813ayCDDFewu1+jsZmX+r/aTEqaOM4TVxVtRSkuCy8nAXKuChOK
# Li/zA4XuH8iEYqIsj2YoNaeSxVmeGiERXpKdo3dDmYi0kO5w2D8VS4c3+9h6gElY
# BaAAg/dYErBg27qT3vv0zRDJhJufvCNylA8S7/+8H5E/PV5cng6na9VV/w9OV3qu
# uND6zdGa2EX38Glp50F9AIQk3p2xXmcvorDeM4XJ7UlWYBi6g80J1SSOQnInCYFE
# msfUNn3+1AaTJKSJL83quKArTac2pKhu0Yzzzrzo6HrsRiQKzpnRBb1/dMa6P3hz
# 75XbMRBctNsFhZC07WCmjExdLg2eHW5uV0TY8D5+6wozJf7vF3+WHkYPO85Z+BC6
# U4FkNbYNycZ9cE4j1tXRdyDCfml6c0HWPHjNVDObrv9lKt3qUqFpX38VCqVCyNOO
# 1UcXfQiVjJw32U2WUKZjt/neJKHEBsm9kFsLuWzkQ53+qcaSaytmsCnk2gOglrlD
# 5d3kKyvvAw+rzm0lT8K38P6PLxfZQHhu4W8dV7Av8N2ZmDCCBr0wggSloAMCAQIC
# EzMAAAA5O7Y3Gb8GHWcAAAAAADkwDQYJKoZIhvcNAQEMBQAwgYgxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBS
# b290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDExMB4XDTI0MDgwODIwNTQxOFoX
# DTM2MDMyMjIyMTMwNFowVzELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9zb2Z0IENvZGUgU2lnbmluZyBQ
# Q0EgMjAyNDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBANgBnB7jOMeq
# lRYHNa265v4IY9fH8TKhemHfPINe1gpLaV3dhg324WwH06LcHbpnsBukCDNitryo
# 0dtS/EW6I/yEL/bLSY8hKpbfQuWusBPr9qazYcDxCW/qnjb5JsI1s8bNOg3bVATv
# QVL4tcf03aTycsz8QeCdM0l/yHRObJ9QqazM1r6VPEOJ7LL+uEEb73w6QCuhs89a
# 1uv1zerOYMnsneRRwCbpyW11IcggU0cRKDDq1pjVJzIbIF6+oiXXbReOsgeI8zu1
# FyQfK0fVkaya8SmVHQ/tOf23mZ4W9k0Ri22QW9p3UgSC5OUDktKxxcCmGL6tXLfO
# GSWHIIV4YrTJTT6PNty5REojHJuZHArkF9VnHTERWoTjAzfI3kP+5b4alUdhgAZ7
# ttOu1bVnXfHaqPYl2rPs20ji03LOVWsh/radgE17es5hL+t6lV0eVHrVhsssROWJ
# uz2MXMCt7iw7lFPG9LXKGjsmonn2gotGdHIuEg5JnJMJVmixd5LRlkmgYRZKzhxS
# CwyoGIq0PhaA7Y+VPct5pCHkijcIIDm0nlkK+0KyepolcqGm0T/GYQRMhHJlGOOm
# VQop36wUVUYklUy++vDWeEgEo4s7hxN6mIbf2MSIQ/iIfMZgJxC69oukMUXCrOC3
# SkE/xIkgpfl22MM1itkZ35nNXkMolU1lAgMBAAGjggFOMIIBSjAOBgNVHQ8BAf8E
# BAMCAYYwEAYJKwYBBAGCNxUBBAMCAQAwHQYDVR0OBBYEFH9ZP1Qh2q1P7wXl5qPX
# LQaUEggxMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMA8GA1UdEwEB/wQFMAMB
# Af8wHwYDVR0jBBgwFoAUci06AjGQQ7kUBU7h6qfHMdEjiTQwWgYDVR0fBFMwUTBP
# oE2gS4ZJaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMv
# TWljUm9vQ2VyQXV0MjAxMV8yMDExXzAzXzIyLmNybDBeBggrBgEFBQcBAQRSMFAw
# TgYIKwYBBQUHMAKGQmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMv
# TWljUm9vQ2VyQXV0MjAxMV8yMDExXzAzXzIyLmNydDANBgkqhkiG9w0BAQwFAAOC
# AgEAFJQfOChP7onn6fLIMKrSlN1WYKwDFgAddymOUO3FrM8d7B/W/iQ6DxXsDn7D
# 5W4wMwYeLystcEqfkjz4NURRgazyMu5yRzQh4LqjA4tStTcJh1opExo7nn5PuPBY
# nbu0+THSuVHTe0VTTPVhily/piFrDo3axQ9P4C+Ol5yet+2gTfekICS5xS+cYfSI
# vgn0JksVBVMYVI5QFu/qhnLhsEFEUzG8fvv0hjgkO+lkpV9ty6GkN4vdnd7ya6Q6
# aR9y34aiM1qmxaxBi6OUnyNl6fkuun/diTFnYDLTppOkr/mg5WSfCiDVMNCxtj4w
# PKC5OmHm1DQIt/MNokbbH3UGsFP1QbzsLocuSqLCvH09Io3fDPTmscR9Y75G4qX7
# RTX8AdBPo0I6OEojf39zuFZt0qOHm65YWQE69cZM2ueE1MB05dNNgHK9gTE7zKvK
# /fg8B2qjW88MT/WF5V5uvZGtqa9FSL2RazArA+rDPuf6JGYz4HpgMZHB4S6szWSK
# YBv0VisCzfxgeU+dquXW9bd0auYlOB58DPcOYKdc3Se94g+xL4pcEhbB54JOgAkw
# YTu/9dLeH2pDqeJZAABVDWRQCaXfO5LgyKwKCLYXpigrZYCjUSBcr+Ve8PFWMhVT
# Ql0v4q8J/AUmQN5W4n101cY2L4A7GTQG1h32HHAvfQESWP0xghn7MIIZ9wIBATBu
# MFcxCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# KDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMjQCEzMAAAIc
# +s3Fm+gvfsQAAAAAAhwwDQYJYIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwG
# CisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZI
# hvcNAQkEMSIEIHLOSaITPAWZ8BiCGnQoV2gLlk62WcowDli/aYs7P1gXMEIGCisG
# AQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEAIC9o98Gfh2HoIjJbeAng
# z34438ZLZTXDUjFEQjcqgY28YikBVRm70px5HbqLLCXSG3ILtnUfIgSqu8bN40vP
# xoVS/z2A518aZjBjekvc+9644rEckxZDIKtt6RI6q7awETG18DgOccj4+odv9yOz
# 6TyuBcWoWqD8k+Kuo3fqzElbXvF+HXr1X3xRy4BjKCJir8uDiiLefHkWXAYg5T7v
# 5e3Dt59vONyPNsBy/yG8IgGCfIo1WdL5rq2uBQ6A0ScwKeSsPGd/0r9EOvmPpvWt
# N9CNznLWogDytrNhi625PLmKEyQQ3zjDgNCZSEyVpQNBz0Rr0uAIucO0SKTMp2Bp
# VqGCF60wghepBgorBgEEAYI3AwMBMYIXmTCCF5UGCSqGSIb3DQEHAqCCF4YwgheC
# AgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIB
# QQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCB0nDjEM4eyT4G2Ml5v
# i4NyKWSKCMHsJ12Sl9L7630NIgIGaohOnk+7GBMyMDI2MDgyODEwMTQ0MC41Mzda
# MASAAgH0oIHZpIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0
# ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjozNjA1LTA1RTAtRDk0NzElMCMG
# A1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCEfswggcoMIIFEKAD
# AgECAhMzAAACE7BDNWbPr5XoAAEAAAITMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTI1MDgxNDE4NDgxN1oXDTI2MTExMzE4
# NDgxN1owgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTAr
# BgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUG
# A1UECxMeblNoaWVsZCBUU1MgRVNOOjM2MDUtMDVFMC1EOTQ3MSUwIwYDVQQDExxN
# aWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOC
# Ag8AMIICCgKCAgEA9Jl64LoZxDINSFgz+9KS5Ozv5m548ePVzc9RXWe4T4/Mplfg
# a4eq12RGdp5cVvnjde5vxfq2ax/jnu7vUW4rZN4mOUm5vh+kcYsQlYQ53FwgIB3n
# EjcQHomrG3mZe/ozjFSAr6JbglKtIeAySPzAcFzyAer5lLNUHBEvQMM8BOjMyapC
# vh0xsg4xKFcVEJQLKEfCGBffMZI/amutHFb3CUTZ7aVpG2KHEFUNlZ1vwMKvxXTP
# RDnbwPGzyyqJJznfsLNHQ4vXt2ttS1PeCoGI0hN1Peq8yGsIXM9oocwC06DGNSM/
# 4LAx2uKvwmUn6NwLc0+tmvny6w28rZLejskRfnVWofEv1mWY0jHUnHrwSGBS8gVP
# 9gcBs6P5g0OpJPMfxdUkHXRkcMPPW0hIP8NbW8W5Sup8HuwnSKbjpyAlGBUdM/V5
# rZb0sZmkn714r6ULGK+cLLAN6R3FhX6N0nj64F27LTK2BbS0pJZaXjo0eDNz1Qcx
# eIFLUgF+RBsLYDn8E8cCkexK8Nlt3Gi9zJf55w6UfTZ+kwTMxMqFxh7+Tfx7+aBO
# bZ+nx961AtiqAy7zVV69o/LWRdKPZdvZn9ESyGbTnPfjkBERv22prSlETlRwzP6b
# mEVOKWLWVwxuwh7bUWUuUb1cj93zvttQYGQat5E9ALLJNmlvLKCskB7raLsCAwEA
# AaOCAUkwggFFMB0GA1UdDgQWBBQTnhBKx+FryphQWMRipH49sMFAOjAfBgNVHSME
# GDAWgBSfpxVdAF5iXYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1l
# LVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsG
# AQUFBzAChlBodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01p
# Y3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMB
# Af8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDAN
# BgkqhkiG9w0BAQsFAAOCAgEAgmxaJrGqQ2D6UJhZ6Ql2SZFOaNuGbW3LzB+ES+l2
# BB1MJtBRSFdi/hVY33NpxsJQhQ5TLVp0DXYOkIoPQc17rH+IVhemO8jCt+U6I1TI
# w6cR7c+tEo/Jjp6EqEU1c4/mraMjgHhQ+raC/OUAm98A1r4bIPHtsBmLROGmeE5X
# LIFaBIZWHvh2COXITKObXVd5wGtJ1dZZdwaHACXF506jta+uoUdyzAeuNlTPLTrZ
# 8nyhxGwk9Vh6eiDQ7CQMWSSa8DJS9PUXjeoi9vTdS7ZMXqu+tv6Qz3xtoBF5+YFK
# 4uE+miGs90Fxm0VK2lWrmFhjkRl5zyoHOdwG7spNYkDomCPNWIudUQmQYKpt/Hss
# pfcb+xpnWIDQdMzgE8pj1vpwLgWEnH7LtT4dZCeoDo9PK40RxBD8kKJ769ngkEwf
# wCD2EX/MQk79eIvOhpnH12GuVByvaKZk5XZvqtPONNwr8q/qA3877IuWwWgnaeX+
# prpw0dZ/QLtbGGVrgP+TRQjt+2dcZA5P3X4LwANhiPsy0Ol4XCdj7OxBLFvOzsCP
# DPaVnkp+dfDFG+NOBir7aqTJ68622pymg1V+6gc/1RvxC/wgvYyG033ecJqv0On0
# ZRNYr+i/OkwgA3HP1aLD0aHrEpw6lt0263iRkCvrcdcOW8w3jC8TJuaGWyC2S9jE
# jzgwggdxMIIFWaADAgECAhMzAAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3DQEB
# CwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYD
# VQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAxMDAe
# Fw0yMTA5MzAxODIyMjVaFw0zMDA5MzAxODMyMjVaMHwxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFBDQSAyMDEwMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA5OGm
# TOe0ciELeaLL1yR5vQ7VgtP97pwHB9KpbE51yMo1V/YBf2xK4OK9uT4XYDP/XE/H
# ZveVU3Fa4n5KWv64NmeFRiMMtY0Tz3cywBAY6GB9alKDRLemjkZrBxTzxXb1hlDc
# wUTIcVxRMTegCjhuje3XD9gmU3w5YQJ6xKr9cmmvHaus9ja+NSZk2pg7uhp7M62A
# W36MEBydUv626GIl3GoPz130/o5Tz9bshVZN7928jaTjkY+yOSxRnOlwaQ3KNi1w
# jjHINSi947SHJMPgyY9+tVSP3PoFVZhtaDuaRr3tpK56KTesy+uDRedGbsoy1cCG
# MFxPLOJiss254o2I5JasAUq7vnGpF1tnYN74kpEeHT39IM9zfUGaRnXNxF803RKJ
# 1v2lIH1+/NmeRd+2ci/bfV+AutuqfjbsNkz2K26oElHovwUDo9Fzpk03dJQcNIIP
# 8BDyt0cY7afomXw/TNuvXsLz1dhzPUNOwTM5TI4CvEJoLhDqhFFG4tG9ahhaYQFz
# ymeiXtcodgLiMxhy16cg8ML6EgrXY28MyTZki1ugpoMhXV8wdJGUlNi5UPkLiWHz
# NgY1GIRH29wb0f2y1BzFa/ZcUlFdEtsluq9QBXpsxREdcu+N+VLEhReTwDwV2xo3
# xwgVGD94q0W29R6HXtqPnhZyacaue7e3PmriLq0CAwEAAaOCAd0wggHZMBIGCSsG
# AQQBgjcVAQQFAgMBAAEwIwYJKwYBBAGCNxUCBBYEFCqnUv5kxJq+gpE8RjUpzxD/
# LwTuMB0GA1UdDgQWBBSfpxVdAF5iXYP05dJlpxtTNRnpcjBcBgNVHSAEVTBTMFEG
# DCsGAQQBgjdMg30BATBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5odG0wEwYDVR0lBAwwCgYIKwYB
# BQUHAwgwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8G
# A1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186aGMQw
# VgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9j
# cmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsGAQUF
# BwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3Br
# aS9jZXJ0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcnQwDQYJKoZIhvcNAQEL
# BQADggIBAJ1VffwqreEsH2cBMSRb4Z5yS/ypb+pcFLY+TkdkeLEGk5c9MTO1OdfC
# cTY/2mRsfNB1OW27DzHkwo/7bNGhlBgi7ulmZzpTTd2YurYeeNg2LpypglYAA7AF
# vonoaeC6Ce5732pvvinLbtg/SHUB2RjebYIM9W0jVOR4U3UkV7ndn/OOPcbzaN9l
# 9qRWqveVtihVJ9AkvUCgvxm2EhIRXT0n4ECWOKz3+SmJw7wXsFSFQrP8DJ6LGYnn
# 8AtqgcKBGUIZUnWKNsIdw2FzLixre24/LAl4FOmRsqlb30mjdAy87JGA0j3mSj5m
# O0+7hvoyGtmW9I/2kQH2zsZ0/fZMcm8Qq3UwxTSwethQ/gpY3UA8x1RtnWN0SCyx
# TkctwRQEcb9k+SS+c23Kjgm9swFXSVRk2XPXfx5bRAGOWhmRaw2fpCjcZxkoJLo4
# S5pu+yFUa2pFEUep8beuyOiJXk+d0tBMdrVXVAmxaQFEfnyhYWxz/gq77EFmPWn9
# y8FBSX5+k77L+DvktxW/tM4+pTFRhLy/AsGConsXHRWJjXD+57XQKBqJC4822rpM
# +Zv/Cuk0+CQ1ZyvgDbjmjJnW4SLq8CdCPSWU5nR0W2rRnj7tfqAxM328y+l7vzhw
# RNGQ8cirOoo6CGJ/2XBjU02N7oJtpQUQwXEGahC0HVUzWLOhcGbyoYIDVjCCAj4C
# AQEwggEBoYHZpIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0
# ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjozNjA1LTA1RTAtRDk0NzElMCMG
# A1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIa
# AxUAmBE8SCjxgjacmy8/VEdk7NxpR6aggYMwgYCkfjB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0BAQsFAAIFAO47XiMwIhgPMjAyNjA4Mjgw
# MTA4NTFaGA8yMDI2MDgyOTAxMDg1MVowdDA6BgorBgEEAYRZCgQBMSwwKjAKAgUA
# 7jteIwIBADAHAgEAAgIkfzAHAgEAAgISUDAKAgUA7jyvowIBADA2BgorBgEEAYRZ
# CgQCMSgwJjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0G
# CSqGSIb3DQEBCwUAA4IBAQCj4QG1jO8s48iM/SZmd5497M9xEGvGdWCa+RFAUj+f
# WGJzUoB6LHnGcinCR8HluXf2XKJlhiCXkkhq9KttYK6aSIhaD4J4cJd7FZ5gEu1l
# m98kDDYhG/lr0/+OmEvxALxIFRaM0Hw4pffSKBI/rcB0yfukd035/2D+EcNxnRdD
# Eg9YLFjgse6/Yvbtj796FHywJtlfUwyd+e1VLvp5w8FTzAJHkatvhuyWG84yvyqG
# Q2tmceqzF/Foh8UQFigtk6W68f1v48i/YgvfVvDeiAI1cd+pgYFuMK27Q0aCCWRo
# E2ZmDP+mdrj77ur01OOiGnjF3NhHTgR3/P2YbE+G0Vi3MYIEDTCCBAkCAQEwgZMw
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAITsEM1Zs+vlegAAQAA
# AhMwDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRAB
# BDAvBgkqhkiG9w0BCQQxIgQgna3gaR124hl8IODTLuv/sL/e3VHHYz1N4b/2vmYM
# k/kwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCDM4QltFIUz8J4DjAzP4nVo
# dZvQxYGleUIfp86Oa5xYaDCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBD
# QSAyMDEwAhMzAAACE7BDNWbPr5XoAAEAAAITMCIEIEsqYSkavq9w/YM39a54jDAg
# QoonnGwu0cjcsJ5hgjxfMA0GCSqGSIb3DQEBCwUABIICAD9+s+whkqsJZUi75Pzk
# GQAsW8SUHxewtxUrj0eaF5fBTQxqAeiQqKzkl7f5sdNkhk/z5ULvub+upiEqAq2+
# Q3gkJ5FaN14hCer1KGcSAWE0ugAoARsU9rFV+uZAATkJ2Z6iTGl3bxqeCBaIzVV3
# 83BySS4vrkhy15tbvQvQTWI3qFaQK1BLXNhCVxEAwuC1JL/BbdafuywRP3ouYdp/
# SQcqk/BSMtq7PsXDLCQk+gDmDZbtkNRlA13Oxg2xd5sSmrjwIqfWnOpa4gB17mWr
# WpfUbm2tjucgVqLnqNBdZp86O0CjsTNtIQiXdAKYP7IgyHEueTjsl/JXJnunhFjf
# M0c2vfCg6sjbsbqQqzyaMs6CBdtANUaAQpD802H45Jh8uBpK1yjPkSvVzmZpizn6
# UXbH5lTVbK4H/413hAIju7tMu+2kYTAAKDRGBD2wZVC/U7qpaUgTo2WqdHqj2FqV
# M+vLvgaUgoYYPiFREFLWKGJgTkAkVAvXa3H4OOptXOgQK4uBU5GUZ1+e2YQ02q+F
# c7wBbE4lrrUuACatJ+8c1SiNUUR2UCAixo4OCQ7743pYDqQubmGxzDUH8wLYfw4A
# 9zBtqGJ+zm4mZll4tnzZhdi5ymIwxGKbOp5sIg9XwqCpPrJdHSEViGxzuUcWMdkz
# +OjLXFur1Wh9mK39dZ3C9Uf0
# SIG # End signature block
