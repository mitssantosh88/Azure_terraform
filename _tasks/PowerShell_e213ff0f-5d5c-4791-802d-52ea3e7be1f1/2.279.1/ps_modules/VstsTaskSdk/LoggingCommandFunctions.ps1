$script:loggingCommandPrefix = '##vso['
$script:loggingCommandEscapeMappings = @( # TODO: WHAT ABOUT "="? WHAT ABOUT "%"?
    New-Object psobject -Property @{ Token = ';' ; Replacement = '%3B' }
    New-Object psobject -Property @{ Token = "`r" ; Replacement = '%0D' }
    New-Object psobject -Property @{ Token = "`n" ; Replacement = '%0A' }
    New-Object psobject -Property @{ Token = "]" ; Replacement = '%5D' }
)
# TODO: BUG: Escape % ???
# TODO: Add test to verify don't need to escape "=".

$commandCorrelationId = $env:COMMAND_CORRELATION_ID
if ($null -ne $commandCorrelationId)
{
    [System.Environment]::SetEnvironmentVariable("COMMAND_CORRELATION_ID", $null)
}

$IssueSources = @{
    CustomerScript = "CustomerScript"
    TaskInternal = "TaskInternal"
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-AddAttachment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Type,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'task' -Event 'addattachment' -Data $Path -Properties @{
            'type' = $Type
            'name' = $Name
        } -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-UploadSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'task' -Event 'uploadsummary' -Data $Path -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-SetEndpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,
        [Parameter(Mandatory = $true)]
        [string]$Field,
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [Parameter(Mandatory = $true)]
        [string]$Value,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'task' -Event 'setendpoint' -Data $Value -Properties @{
            'id' = $Id
            'field' = $Field
            'key' = $Key
        } -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-AddBuildTag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'build' -Event 'addbuildtag' -Data $Value -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-AssociateArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Type,
        [hashtable]$Properties,
        [switch]$AsOutput)

    $p = @{ }
    if ($Properties) {
        foreach ($key in $Properties.Keys) {
            $p[$key] = $Properties[$key]
        }
    }

    $p['artifactname'] = $Name
    $p['artifacttype'] = $Type
    Write-LoggingCommand -Area 'artifact' -Event 'associate' -Data $Path -Properties $p -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-LogDetail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [guid]$Id,
        $ParentId,
        [string]$Type,
        [string]$Name,
        $Order,
        $StartTime,
        $FinishTime,
        $Progress,
        [ValidateSet('Unknown', 'Initialized', 'InProgress', 'Completed')]
        [Parameter()]
        $State,
        [ValidateSet('Succeeded', 'SucceededWithIssues', 'Failed', 'Cancelled', 'Skipped')]
        [Parameter()]
        $Result,
        [string]$Message,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'task' -Event 'logdetail' -Data $Message -Properties @{
            'id' = $Id
            'parentid' = $ParentId
            'type' = $Type
            'name' = $Name
            'order' = $Order
            'starttime' = $StartTime
            'finishtime' = $FinishTime
            'progress' = $Progress
            'state' = $State
            'result' = $Result
        } -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-SetProgress {
    [CmdletBinding()]
    param(
        [ValidateRange(0, 100)]
        [Parameter(Mandatory = $true)]
        [int]$Percent,
        [string]$CurrentOperation,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'task' -Event 'setprogress' -Data $CurrentOperation -Properties @{
            'value' = $Percent
        } -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-SetResult {
    [CmdletBinding(DefaultParameterSetName = 'AsOutput')]
    param(
        [ValidateSet("Succeeded", "SucceededWithIssues", "Failed", "Cancelled", "Skipped")]
        [Parameter(Mandatory = $true)]
        [string]$Result,
        [string]$Message,
        [Parameter(ParameterSetName = 'AsOutput')]
        [switch]$AsOutput,
        [Parameter(ParameterSetName = 'DoNotThrow')]
        [switch]$DoNotThrow)

    Write-LoggingCommand -Area 'task' -Event 'complete' -Data $Message -Properties @{
            'result' = $Result
        } -AsOutput:$AsOutput
    if ($Result -eq 'Failed' -and !$AsOutput -and !$DoNotThrow) {
        # Special internal exception type to control the flow. Not currently intended
        # for public usage and subject to change.
        throw (New-Object VstsTaskSdk.TerminationException($Message))
    }
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-SetSecret {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'task' -Event 'setsecret' -Data $Value -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-SetVariable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [string]$Value,
        [switch]$Secret,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'task' -Event 'setvariable' -Data $Value -Properties @{
            'variable' = $Name
            'issecret' = $Secret
        } -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-TaskDebug {
    [CmdletBinding()]
    param(
        [string]$Message,
        [switch]$AsOutput)

    Write-TaskDebug_Internal @PSBoundParameters
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-TaskError {
    [CmdletBinding()]
    param(
        [string]$Message,
        [string]$ErrCode,
        [string]$SourcePath,
        [string]$LineNumber,
        [string]$ColumnNumber,
        [switch]$AsOutput,
        [string]$IssueSource,
        [string]$AuditAction
    )

    Write-LogIssue -Type error @PSBoundParameters
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-TaskVerbose {
    [CmdletBinding()]
    param(
        [string]$Message,
        [switch]$AsOutput)

    Write-TaskDebug_Internal @PSBoundParameters -AsVerbose
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-TaskWarning {
    [CmdletBinding()]
    param(
        [string]$Message,
        [string]$ErrCode,
        [string]$SourcePath,
        [string]$LineNumber,
        [string]$ColumnNumber,
        [switch]$AsOutput,
        [string]$IssueSource,
        [string]$AuditAction
    )

    Write-LogIssue -Type warning @PSBoundParameters
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-UploadFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'task' -Event 'uploadfile' -Data $Path -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-PrependPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'task' -Event 'prependpath' -Data $Path -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-UpdateBuildNumber {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'build' -Event 'updatebuildnumber' -Data $Value -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-UploadArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerFolder,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'artifact' -Event 'upload' -Data $Path -Properties @{
            'containerfolder' = $ContainerFolder
            'artifactname' = $Name
        } -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-UploadBuildLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'build' -Event 'uploadlog' -Data $Path -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-UpdateReleaseName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'release' -Event 'updatereleasename' -Data $Name -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-LoggingCommand {
    [CmdletBinding(DefaultParameterSetName = 'Parameters')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Parameters')]
        [string]$Area,
        [Parameter(Mandatory = $true, ParameterSetName = 'Parameters')]
        [string]$Event,
        [Parameter(ParameterSetName = 'Parameters')]
        [string]$Data,
        [Parameter(ParameterSetName = 'Parameters')]
        [hashtable]$Properties,
        [Parameter(Mandatory = $true, ParameterSetName = 'Object')]
        $Command,
        [switch]$AsOutput)

    if ($PSCmdlet.ParameterSetName -eq 'Object') {
        Write-LoggingCommand -Area $Command.Area -Event $Command.Event -Data $Command.Data -Properties $Command.Properties -AsOutput:$AsOutput
        return
    }

    $command = Format-LoggingCommand -Area $Area -Event $Event -Data $Data -Properties $Properties
    if ($AsOutput) {
        $command
    } else {
        Write-Host $command
    }
}

########################################
# Private functions.
########################################
function Format-LoggingCommandData {
    [CmdletBinding()]
    param([string]$Value, [switch]$Reverse)

    if (!$Value) {
        return ''
    }

    if (!$Reverse) {
        foreach ($mapping in $script:loggingCommandEscapeMappings) {
            $Value = $Value.Replace($mapping.Token, $mapping.Replacement)
        }
    } else {
        for ($i = $script:loggingCommandEscapeMappings.Length - 1 ; $i -ge 0 ; $i--) {
            $mapping = $script:loggingCommandEscapeMappings[$i]
            $Value = $Value.Replace($mapping.Replacement, $mapping.Token)
        }
    }

    return $Value
}

function Format-LoggingCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Area,
        [Parameter(Mandatory = $true)]
        [string]$Event,
        [string]$Data,
        [System.Collections.IDictionary]$Properties)

    # Append the preamble.
    [System.Text.StringBuilder]$sb = New-Object -TypeName System.Text.StringBuilder
    $null = $sb.Append($script:loggingCommandPrefix).Append($Area).Append('.').Append($Event)

    # Append the properties.
    if ($Properties) {
        $first = $true
        foreach ($key in $Properties.Keys) {
            [string]$value = Format-LoggingCommandData $Properties[$key]
            if ($value) {
                if ($first) {
                    $null = $sb.Append(' ')
                    $first = $false
                } else {
                    $null = $sb.Append(';')
                }

                $null = $sb.Append("$key=$value")
            }
        }
    }

    # Append the tail and output the value.
    $Data = Format-LoggingCommandData $Data
    $sb.Append(']').Append($Data).ToString()
}

function Write-LogIssue {
    [CmdletBinding()]
    param(
        [ValidateSet('warning', 'error')]
        [Parameter(Mandatory = $true)]
        [string]$Type,
        [string]$Message,
        [string]$ErrCode,
        [string]$SourcePath,
        [string]$LineNumber,
        [string]$ColumnNumber,
        [switch]$AsOutput,
        [AllowNull()]
        [ValidateSet('CustomerScript', 'TaskInternal')]
        [string]$IssueSource = $IssueSources.TaskInternal,
        [string]$AuditAction
    )

    $properties = [ordered]@{
        'type'          = $Type
        'code'          = $ErrCode
        'sourcepath'    = $SourcePath
        'linenumber'    = $LineNumber
        'columnnumber'  = $ColumnNumber
        'source'        = $IssueSource
        'correlationId' = $commandCorrelationId
        'auditAction'   = $AuditAction
    }
    $command = Format-LoggingCommand -Area 'task' -Event 'logissue' -Data $Message -Properties $properties
    if ($AsOutput) {
        return $command
    }

    if ($Type -eq 'error') {
        $foregroundColor = $host.PrivateData.ErrorForegroundColor
        $backgroundColor = $host.PrivateData.ErrorBackgroundColor
        if ($foregroundColor -isnot [System.ConsoleColor] -or $backgroundColor -isnot [System.ConsoleColor]) {
            $foregroundColor = [System.ConsoleColor]::Red
            $backgroundColor = [System.ConsoleColor]::Black
        }
    } else {
        $foregroundColor = $host.PrivateData.WarningForegroundColor
        $backgroundColor = $host.PrivateData.WarningBackgroundColor
        if ($foregroundColor -isnot [System.ConsoleColor] -or $backgroundColor -isnot [System.ConsoleColor]) {
            $foregroundColor = [System.ConsoleColor]::Yellow
            $backgroundColor = [System.ConsoleColor]::Black
        }
    }

    Write-Host $command -ForegroundColor $foregroundColor -BackgroundColor $backgroundColor
}

function Write-TaskDebug_Internal {
    [CmdletBinding()]
    param(
        [string]$Message,
        [switch]$AsVerbose,
        [switch]$AsOutput)

    $command = Format-LoggingCommand -Area 'task' -Event 'debug' -Data $Message
    if ($AsOutput) {
        return $command
    }

    if ($AsVerbose) {
        $foregroundColor = $host.PrivateData.VerboseForegroundColor
        $backgroundColor = $host.PrivateData.VerboseBackgroundColor
        if ($foregroundColor -isnot [System.ConsoleColor] -or $backgroundColor -isnot [System.ConsoleColor]) {
            $foregroundColor = [System.ConsoleColor]::Cyan
            $backgroundColor = [System.ConsoleColor]::Black
        }
    } else {
        $foregroundColor = $host.PrivateData.DebugForegroundColor
        $backgroundColor = $host.PrivateData.DebugBackgroundColor
        if ($foregroundColor -isnot [System.ConsoleColor] -or $backgroundColor -isnot [System.ConsoleColor]) {
            $foregroundColor = [System.ConsoleColor]::DarkGray
            $backgroundColor = [System.ConsoleColor]::Black
        }
    }

    Write-Host -Object $command -ForegroundColor $foregroundColor -BackgroundColor $backgroundColor
}

# SIG # Begin signature block
# MIInSAYJKoZIhvcNAQcCoIInOTCCJzUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCA1KTPYa+l6ttc7
# b8bj9crj35CZImyQrNtvCrR6j/LV16CCDLowggX1MIID3aADAgECAhMzAAACHU0Z
# yE7XD1dIAAAAAAIdMA0GCSqGSIb3DQEBCwUAMFcxCzAJBgNVBAYTAlVTMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBD
# b2RlIFNpZ25pbmcgUENBIDIwMjQwHhcNMjYwNDE2MTg1OTQzWhcNMjcwNDE1MTg1
# OTQzWjB0MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYD
# VQQDExVNaWNyb3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IB
# DwAwggEKAoIBAQDQvewXxx9gZZFC6Ys1WBay8BJ8kGA4JQnH5CMafqOASlTpK9H8
# o5ZXTXt0caVQTNMUPt445wXYD+dFtaKWTwDn1I52oUSrC9vJin1Gsqt+zyKJL5Dg
# 3eQXbQNR61DmMy20GLTIO3SFed9Rfi/ophgCLGFLDR3r0KvHjwMb/jYWS0celV/4
# Lz27LfAekm8v9E5IXaeiXbAUYZKK090n4CVl3JBtbN+9DtI9SNu/yjvozW52/u7R
# X/Ttpa/KDlpuokZ+Zcbvmtd9ur9gFLvZzh41o9MsE/clQtdaFWGvuo6Jua/ntpgk
# ey3E5/vBFe+MJPG6phdnuo6r57ZudCudiI1bAgMBAAGjggGbMIIBlzAOBgNVHQ8B
# Af8EBAMCB4AwHwYDVR0lBBgwFgYKKwYBBAGCN0wIAQYIKwYBBQUHAwMwHQYDVR0O
# BBYEFH6QuMwqcPG0hQlQ6c5jCtTTLrVeMEUGA1UdEQQ+MDykOjA4MR4wHAYDVQQL
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xFjAUBgNVBAUTDTIzMDAxMis1MDc1NTkw
# HwYDVR0jBBgwFoAUf1k/VCHarU/vBeXmo9ctBpQSCDEwYAYDVR0fBFkwVzBVoFOg
# UYZPaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWljcm9zb2Z0
# JTIwQ29kZSUyMFNpZ25pbmclMjBQQ0ElMjAyMDI0LmNybDBtBggrBgEFBQcBAQRh
# MF8wXQYIKwYBBQUHMAKGUWh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# Y2VydHMvTWljcm9zb2Z0JTIwQ29kZSUyMFNpZ25pbmclMjBQQ0ElMjAyMDI0LmNy
# dDAMBgNVHRMBAf8EAjAAMA0GCSqGSIb3DQEBCwUAA4ICAQBKTbYOjzwTG/DXGaz9
# s6+fQeaTtDcFmMY+5UyVFCyj7Pv+5i37qfX8lSL/tBIfYQfWsMuBQlfZurJD6r4H
# VJ2CeH+1fgiq8dcHdVKoZ3Sa2qXoX3cq9iS8cVb06B7+5/XJ7I0OxHH9fDsvJ3T3
# w5V/ZtAIFmLrl+P0CtG+92uzRsn0nTbdFjOkLMLWPLAU3THohKRlSEMgFJpPkm5n
# 5UAZ35xX6FWCrDLsSKb555bTifwa8mJBwdlof0bmfYidH+dxZ1FdDxvLnNl9zeKs
# A4kejaaIqqIPguhwAti5Ql7BlTNoJNwxCvBmqW2MQLnCkYN/VVUsR3V2x/rcTNzo
# Bf/Z/SpROvdaA2ZOOd1uioXJt3tdLQ7vHpqpib0KfWr/FWXW10q38VxfCnRQBqzb
# SuztR7nEMuzX7Ck+B/XaPDXd1qh72+QYyB0Z2VzWmO9zsnb9Uq/dwu8LGeQqnyu6
# 7SDGACvnXii2fb9+US492VTnXSnFKyqwgzUyFMtZK1/sHYTv6bG4TtQUygQxTN+Z
# V+aJIlKO2MqZ7bKrAnOzS9m6NgoTdWOq11bTOZwKlIEV/EhV9SWkDmdpR/hPPT2v
# 6TEj4F8PT/zHjRezIU5c/DGlt/VhY/pK0XkJtEyMmmS1BMtjU/rqBZVMIm3dnxQs
# /TBByr+Cf8Z1r7aifQVQ+WSqzjCCBr0wggSloAMCAQICEzMAAAA5O7Y3Gb8GHWcA
# AAAAADkwDQYJKoZIhvcNAQEMBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRl
# IEF1dGhvcml0eSAyMDExMB4XDTI0MDgwODIwNTQxOFoXDTM2MDMyMjIyMTMwNFow
# VzELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEo
# MCYGA1UEAxMfTWljcm9zb2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAyNDCCAiIwDQYJ
# KoZIhvcNAQEBBQADggIPADCCAgoCggIBANgBnB7jOMeqlRYHNa265v4IY9fH8TKh
# emHfPINe1gpLaV3dhg324WwH06LcHbpnsBukCDNitryo0dtS/EW6I/yEL/bLSY8h
# KpbfQuWusBPr9qazYcDxCW/qnjb5JsI1s8bNOg3bVATvQVL4tcf03aTycsz8QeCd
# M0l/yHRObJ9QqazM1r6VPEOJ7LL+uEEb73w6QCuhs89a1uv1zerOYMnsneRRwCbp
# yW11IcggU0cRKDDq1pjVJzIbIF6+oiXXbReOsgeI8zu1FyQfK0fVkaya8SmVHQ/t
# Of23mZ4W9k0Ri22QW9p3UgSC5OUDktKxxcCmGL6tXLfOGSWHIIV4YrTJTT6PNty5
# REojHJuZHArkF9VnHTERWoTjAzfI3kP+5b4alUdhgAZ7ttOu1bVnXfHaqPYl2rPs
# 20ji03LOVWsh/radgE17es5hL+t6lV0eVHrVhsssROWJuz2MXMCt7iw7lFPG9LXK
# Gjsmonn2gotGdHIuEg5JnJMJVmixd5LRlkmgYRZKzhxSCwyoGIq0PhaA7Y+VPct5
# pCHkijcIIDm0nlkK+0KyepolcqGm0T/GYQRMhHJlGOOmVQop36wUVUYklUy++vDW
# eEgEo4s7hxN6mIbf2MSIQ/iIfMZgJxC69oukMUXCrOC3SkE/xIkgpfl22MM1itkZ
# 35nNXkMolU1lAgMBAAGjggFOMIIBSjAOBgNVHQ8BAf8EBAMCAYYwEAYJKwYBBAGC
# NxUBBAMCAQAwHQYDVR0OBBYEFH9ZP1Qh2q1P7wXl5qPXLQaUEggxMBkGCSsGAQQB
# gjcUAgQMHgoAUwB1AGIAQwBBMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU
# ci06AjGQQ7kUBU7h6qfHMdEjiTQwWgYDVR0fBFMwUTBPoE2gS4ZJaHR0cDovL2Ny
# bC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0MjAx
# MV8yMDExXzAzXzIyLmNybDBeBggrBgEFBQcBAQRSMFAwTgYIKwYBBQUHMAKGQmh0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljUm9vQ2VyQXV0MjAx
# MV8yMDExXzAzXzIyLmNydDANBgkqhkiG9w0BAQwFAAOCAgEAFJQfOChP7onn6fLI
# MKrSlN1WYKwDFgAddymOUO3FrM8d7B/W/iQ6DxXsDn7D5W4wMwYeLystcEqfkjz4
# NURRgazyMu5yRzQh4LqjA4tStTcJh1opExo7nn5PuPBYnbu0+THSuVHTe0VTTPVh
# ily/piFrDo3axQ9P4C+Ol5yet+2gTfekICS5xS+cYfSIvgn0JksVBVMYVI5QFu/q
# hnLhsEFEUzG8fvv0hjgkO+lkpV9ty6GkN4vdnd7ya6Q6aR9y34aiM1qmxaxBi6OU
# nyNl6fkuun/diTFnYDLTppOkr/mg5WSfCiDVMNCxtj4wPKC5OmHm1DQIt/MNokbb
# H3UGsFP1QbzsLocuSqLCvH09Io3fDPTmscR9Y75G4qX7RTX8AdBPo0I6OEojf39z
# uFZt0qOHm65YWQE69cZM2ueE1MB05dNNgHK9gTE7zKvK/fg8B2qjW88MT/WF5V5u
# vZGtqa9FSL2RazArA+rDPuf6JGYz4HpgMZHB4S6szWSKYBv0VisCzfxgeU+dquXW
# 9bd0auYlOB58DPcOYKdc3Se94g+xL4pcEhbB54JOgAkwYTu/9dLeH2pDqeJZAABV
# DWRQCaXfO5LgyKwKCLYXpigrZYCjUSBcr+Ve8PFWMhVTQl0v4q8J/AUmQN5W4n10
# 1cY2L4A7GTQG1h32HHAvfQESWP0xghnkMIIZ4AIBATBuMFcxCzAJBgNVBAYTAlVT
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMjQCEzMAAAIdTRnITtcPV0gAAAAAAh0w
# DQYJYIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIM6d0jte
# XnEZrpH769Wx1WH7jH9JjtoUs8WR6Gl54jo7MEIGCisGAQQBgjcCAQwxNDAyoBSA
# EgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20w
# DQYJKoZIhvcNAQEBBQAEggEAqd7VJ/y3X9F+ETGP2sImpE8aNImYihJBry3E1Cpo
# 7ezLbUaLbu6VAoqVyN1eoQmNQRvw7Bt+L7pJZvU4VPu+Q+KZPzaPVxwZulCarGQM
# 0CHxYPQAf7qUse/vt5KNtrG9N/9jNPYtXyt0QO98gK/s+L5kZS/NWniiR4BTOdnw
# Ul6ZZXKXHCIl9MtgINM7FL/AGh7g5DEbdIx3GOSqTe3Ts2LBa4C7TuhicpQvDusM
# 28zaoaLRybL8bNNboSxNVDqIy6qQx+H946fwhwpDsy52pBrr0JGXbauh+y3BdZpC
# ce8N8gL41DW/vqMhjimhu35Z6gT3puI8Yy4cOQUmdHp3qaGCF5YwgheSBgorBgEE
# AYI3AwMBMYIXgjCCF34GCSqGSIb3DQEHAqCCF28wghdrAgEDMQ8wDQYJYIZIAWUD
# BAIBBQAwggFRBgsqhkiG9w0BCRABBKCCAUAEggE8MIIBOAIBAQYKKwYBBAGEWQoD
# ATAxMA0GCWCGSAFlAwQCAQUABCChGk29Wx/D49ipFVeLVW1IXQi1LaatQ9eboyDJ
# pitkhAIGaoSSbZnnGBIyMDI2MDgyNDA1MjIxNC4wOVowBIACAfSggdGkgc4wgcsx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1p
# Y3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMxJzAlBgNVBAsTHm5TaGllbGQgVFNT
# IEVTTjpBMDAwLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgU2VydmljZaCCEe0wggcgMIIFCKADAgECAhMzAAACK7sAUP9NO5qhAAEAAAIr
# MA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5n
# dG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4X
# DTI2MDIxOTE5NDAxMVoXDTI3MDUxNzE5NDAxMVowgcsxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBBbWVyaWNh
# IE9wZXJhdGlvbnMxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjpBMDAwLTA1RTAt
# RDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZTCCAiIw
# DQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAJfeaLo4PezJSpCbhCqCSso9tywr
# 9DHd9hy0vz5UzW45jduiiLkbHBq5OBB/okUchNOjFLuCOoqUrw4UvMvpROXSPEQr
# m3oO45yAld2+62KahOU5LQLeTIhNcEBeiP+CnqFFH3PpZGKnUq2SKVvd0lcKNCpP
# 0/YK66Ov5XPyv5n6MOXT2OL+Jz/gbfiveZXCOz/8afH0+7fVXytcWJw2IDPGm5tr
# Clt3ymp/OVZPa+cbeQX2XoyJERu8ndcctTAdCyHS39OtIXH+z/IKqklZgnqgKUbv
# S2+wUfRpE/zAHhw/8IVrYgu+TbqLc5wkGX6moqMdNIHL2a/BM8QOWfNyjQ23xHql
# I9NdmAGyxweGgp8LRZCY7NjaR5dsCZFNxkzJfPm/8AluagjTLTsFrO+3k2Rd10b1
# MStBbC2wXIgqsSUOBZ8d4KhO7XC7ZyIPd0rvbPdxraDOgQPFPaP0FchQpqJPNN1A
# 9GwAxo7d1TTNobAwyXC1InIOHXhgSBmhS7m9Lwy6Ayp2s2OmHIvrnIqGOkBZuFiQ
# gc7/S5mO73m0/zNk2pchGHi119Yck8BOf2v5zGTK6HbHRUt1/HWWYr1fc2MfQ22A
# CzkkH/A6WTK653GYVN9ZXJGsvfuKyk5nxo8AWC/JHpw1OQamQWjfklGNyI2ZmJTi
# pP1S3L5XmC50WTWPAgMBAAGjggFJMIIBRTAdBgNVHQ4EFgQUPhaO5BNQlu1t3eOa
# 9mS7QVnZ5TYwHwYDVR0jBBgwFoAUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXwYDVR0f
# BFgwVjBUoFKgUIZOaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwv
# TWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3JsMGwGCCsG
# AQUFBwEBBGAwXjBcBggrBgEFBQcwAoZQaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAx
# MCgxKS5jcnQwDAYDVR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDAO
# BgNVHQ8BAf8EBAMCB4AwDQYJKoZIhvcNAQELBQADggIBAM78IqxyIQzySvV+ofhO
# V9ProQ2hOPFfDzXSnISrQ92uAvB+BPfH7WDPsJAe1R16+oxDmofIMuGbqlP3XUJi
# QY37qD4xTt8xhOvp3dLGJ4nAEihaR9HiDtKK0bMwpTjrkoRh6N912hSCi8L/FxGl
# oAs7mnf8DbjwHKEmIy20FA0O2xP8doIXBEUJRFvL9/xzWSTLwXzGQJcXP78y1nl3
# WVYWPA4jaB5kdar1eKEM6B57mdLaSijlXqfxcbbbRRN69V/6mCakgfvVcoNUhhMY
# ZkmzrI+V8nZperDUwTg1HqiQ2xjc/UzfUfoMxhF8kY0E16nn3mRcaHdjMDdwKLKD
# 6OYnnyH99O+OeAim5QV84OkOMXHSJzVigsA3GEIXdGFL2pgzsrjQ0SEqyFi5oCQg
# bZcEpiKDev/T9vSyO+MHCznkBiicybcDypxf/qT1V9zSa/122ice5YZ8DZv6oTaq
# kKeHMZt0MeruI5JkTDTWc26kAx/VzjWT0ihNDbPeLDrDhlmgs7KDhMoxunWSulPi
# 2uKn/LfQK/mSHKoIM2ppdCkGQ5g43wuC2hDdqZU5fuLHmN2ufH+9TFNRKKBe+tZ0
# vtSTySmZLTO2jZOjLtpPmgHMJO9+P2In8E38TW+EUGSEkK9ns9W+wxKdNOaTHYVq
# XaVWTO24Ajjh8P+7Isl1oxBLMIIHcTCCBVmgAwIBAgITMwAAABXF52ueAptJmQAA
# AAAAFTANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUg
# QXV0aG9yaXR5IDIwMTAwHhcNMjEwOTMwMTgyMjI1WhcNMzAwOTMwMTgzMjI1WjB8
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1N
# aWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDCCAiIwDQYJKoZIhvcNAQEBBQAD
# ggIPADCCAgoCggIBAOThpkzntHIhC3miy9ckeb0O1YLT/e6cBwfSqWxOdcjKNVf2
# AX9sSuDivbk+F2Az/1xPx2b3lVNxWuJ+Slr+uDZnhUYjDLWNE893MsAQGOhgfWpS
# g0S3po5GawcU88V29YZQ3MFEyHFcUTE3oAo4bo3t1w/YJlN8OWECesSq/XJprx2r
# rPY2vjUmZNqYO7oaezOtgFt+jBAcnVL+tuhiJdxqD89d9P6OU8/W7IVWTe/dvI2k
# 45GPsjksUZzpcGkNyjYtcI4xyDUoveO0hyTD4MmPfrVUj9z6BVWYbWg7mka97aSu
# eik3rMvrg0XnRm7KMtXAhjBcTyziYrLNueKNiOSWrAFKu75xqRdbZ2De+JKRHh09
# /SDPc31BmkZ1zcRfNN0Sidb9pSB9fvzZnkXftnIv231fgLrbqn427DZM9ituqBJR
# 6L8FA6PRc6ZNN3SUHDSCD/AQ8rdHGO2n6Jl8P0zbr17C89XYcz1DTsEzOUyOArxC
# aC4Q6oRRRuLRvWoYWmEBc8pnol7XKHYC4jMYctenIPDC+hIK12NvDMk2ZItboKaD
# IV1fMHSRlJTYuVD5C4lh8zYGNRiER9vcG9H9stQcxWv2XFJRXRLbJbqvUAV6bMUR
# HXLvjflSxIUXk8A8FdsaN8cIFRg/eKtFtvUeh17aj54WcmnGrnu3tz5q4i6tAgMB
# AAGjggHdMIIB2TASBgkrBgEEAYI3FQEEBQIDAQABMCMGCSsGAQQBgjcVAgQWBBQq
# p1L+ZMSavoKRPEY1Kc8Q/y8E7jAdBgNVHQ4EFgQUn6cVXQBeYl2D9OXSZacbUzUZ
# 6XIwXAYDVR0gBFUwUzBRBgwrBgEEAYI3TIN9AQEwQTA/BggrBgEFBQcCARYzaHR0
# cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRt
# MBMGA1UdJQQMMAoGCCsGAQUFBwMIMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBB
# MAsGA1UdDwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFNX2VsuP
# 6KJcYmjRPZSQW9fOmhjEMFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9jcmwubWlj
# cm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dF8yMDEwLTA2
# LTIzLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6Ly93d3cu
# bWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMu
# Y3J0MA0GCSqGSIb3DQEBCwUAA4ICAQCdVX38Kq3hLB9nATEkW+Geckv8qW/qXBS2
# Pk5HZHixBpOXPTEztTnXwnE2P9pkbHzQdTltuw8x5MKP+2zRoZQYIu7pZmc6U03d
# mLq2HnjYNi6cqYJWAAOwBb6J6Gngugnue99qb74py27YP0h1AdkY3m2CDPVtI1Tk
# eFN1JFe53Z/zjj3G82jfZfakVqr3lbYoVSfQJL1AoL8ZthISEV09J+BAljis9/kp
# icO8F7BUhUKz/AyeixmJ5/ALaoHCgRlCGVJ1ijbCHcNhcy4sa3tuPywJeBTpkbKp
# W99Jo3QMvOyRgNI95ko+ZjtPu4b6MhrZlvSP9pEB9s7GdP32THJvEKt1MMU0sHrY
# UP4KWN1APMdUbZ1jdEgssU5HLcEUBHG/ZPkkvnNtyo4JvbMBV0lUZNlz138eW0QB
# jloZkWsNn6Qo3GcZKCS6OEuabvshVGtqRRFHqfG3rsjoiV5PndLQTHa1V1QJsWkB
# RH58oWFsc/4Ku+xBZj1p/cvBQUl+fpO+y/g75LcVv7TOPqUxUYS8vwLBgqJ7Fx0V
# iY1w/ue10CgaiQuPNtq6TPmb/wrpNPgkNWcr4A245oyZ1uEi6vAnQj0llOZ0dFtq
# 0Z4+7X6gMTN9vMvpe784cETRkPHIqzqKOghif9lwY1NNje6CbaUFEMFxBmoQtB1V
# M1izoXBm8qGCA1AwggI4AgEBMIH5oYHRpIHOMIHLMQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBP
# cGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046QTAwMC0wNUUwLUQ5
# NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WiIwoBATAH
# BgUrDgMCGgMVAAmsP3TKQemj/QAZvuWbC+wK2pE5oIGDMIGApH4wfDELMAkGA1UE
# BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAc
# BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0
# IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJKoZIhvcNAQELBQACBQDuNlBPMCIYDzIw
# MjYwODI0MDUwODMxWhgPMjAyNjA4MjUwNTA4MzFaMHcwPQYKKwYBBAGEWQoEATEv
# MC0wCgIFAO42UE8CAQAwCgIBAAICIVECAf8wBwIBAAICGuUwCgIFAO43oc8CAQAw
# NgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAqAKMAgCAQACAwehIKEKMAgC
# AQACAwGGoDANBgkqhkiG9w0BAQsFAAOCAQEAOROs/U5QglEhy+ZtXu6gWa6eZI76
# UORgwEHtELFraECseA5jT8JjJ4p3qzbEI8uHqiaIYicQgZuJ2ZvISVH+taFM52sq
# 4N/man01PAROG74y67KFSyLJq5OGhyp9FbSI9syHZJIWUX+D5PB9UpUlFpVK5qqz
# wxaJT33JEC6fd+rHfwbD1SDkzPeXaoPFQdIoIJnj8L9gotdFjp5/psgt3sHjL+UQ
# Q4aItLdlquOfhVu7fEcH1m+gpLkLJfuOy1yp1th4HVYn9Eftu+AOwJpJQwbi2QUs
# eQhCU8JbZtdrOY4/Hvkm6aKUK4oybhJ05TR16Q0r44EEYupl2MvfHVrWoTGCBA0w
# ggQJAgEBMIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAw
# DgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24x
# JjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAACK7sA
# UP9NO5qhAAEAAAIrMA0GCWCGSAFlAwQCAQUAoIIBSjAaBgkqhkiG9w0BCQMxDQYL
# KoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEIGgbp5oKmY9xD2pKWisF2TunrJ/8
# jztLmKPnBEAvGhknMIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB5DCBvQQgcg4j9D+Q
# V+1gD4zY5j7UHHdqMEPr9YMC09Pa8WS/blIwgZgwgYCkfjB8MQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBQQ0EgMjAxMAITMwAAAiu7AFD/TTuaoQABAAACKzAiBCDZ83VoIqQC
# GmxFcKuY9OKFDHIogPhDdDnsH/sOKE2gbzANBgkqhkiG9w0BAQsFAASCAgCSApFO
# kRvEIsYjWZH4dHBTWeM/OhvlNAboRacSxCC5AGN8Jiuk/2D4ovTyyjmJr7WKXBO3
# Bf1pyNgGvWQkZjZ068ZRu9ktFweDYRqfKF0pT8WjbJ33r7BWpeEPxDmHiKvylUil
# bUr3Eoxi1+3gwdlAUpR4OGQOKu8LRoWBZZFakP4QUeB/WUtTtaKMD8i28PwNDD11
# xqxWGGh1A/OKxl4MQ8mKEGQEDsNIY0V6V8cD5QN9bxU1b83MC65+zPHS9OyPTZju
# oyteN5TTgGmr6xkmdDPUc9SvL1ytssVsVyPLCOi7aLTfjVyCamtyd1QlJusewCyJ
# 0csnVkxeT2roq9r0gIBhnFp9F+IIGI7Kc9gUceeKh7Q4j6PwEhRN66J48AfQ45ar
# VbctdVdFgf2KvZje1DIfLIRZaQjTjScHDI4j9pOPc8hHgATmue7P2Pu4Y2F355vf
# oXyC4VbxcYt9Lxl0pW9aWBGbXMKJ2SJJRdPoYPjvaen7ACT6Ne37j8CuRWnIhOml
# ieIB8UJ2psvd8Dw3CuF9TfCHWp9/T5ROKqfhOnSkIpU45MHHN+Bq/IG2oPG0i9mS
# Yu0DXEA1keShIIzE7Opj4Yxumy3Ntqi0bUK3tM7oXEjJctSnK3knujsoh37KJMKU
# CEXEZDlRM41UJmkmX3GbWqFDJU/QHeghoN7E9g==
# SIG # End signature block
