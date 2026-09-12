. $PSScriptRoot\Expand-EnvVariables.ps1

$featureFlags = @{
    activate  = [System.Convert]::ToBoolean($env:AZP_75787_ENABLE_NEW_LOGIC)
    audit     = [System.Convert]::ToBoolean($env:AZP_75787_ENABLE_NEW_LOGIC_LOG)
    telemetry = [System.Convert]::ToBoolean($env:AZP_75787_ENABLE_COLLECT)
}

Write-Verbose "Feature flag AZP_75787_ENABLE_NEW_LOGIC state: $($featureFlags.activate)"
Write-Verbose "Feature flag AZP_75787_ENABLE_NEW_LOGIC_LOG state: $($featureFlags.audit)"
Write-Verbose "Feature flag AZP_75787_ENABLE_COLLECT state: $($featureFlags.telemetry)"

$taskName = ""

# AST node types that represent code execution (not pure data) and therefore
# must never appear in a relaxed-mode argument. Kept in one module-level place so
# the set is easy to audit and extend.
#   ScriptBlockExpressionAst - { ... }
#   MemberExpressionAst       - property / method access; its subclass
#                               InvokeMemberExpressionAst (method calls) is covered too
#   ConvertExpressionAst      - [type]$x / [type]'s' casts, incl. [ordered]@{} / [pscustomobject]@{}
#   TypeExpressionAst         - a bare [type] reference (also the right side of -is / -isnot)
# The -as conversion operator is handled separately in Test-SanitizerArgumentAst
# because it is a BinaryExpressionAst distinguished by its operator, not a
# dedicated node type.
$script:DangerousAstNodeTypes = @(
    [System.Management.Automation.Language.ScriptBlockExpressionAst],
    [System.Management.Automation.Language.MemberExpressionAst],
    [System.Management.Automation.Language.ConvertExpressionAst],
    [System.Management.Automation.Language.TypeExpressionAst]
)

# public functions - start

function Get-SanitizerFeatureFlags {
    return $featureFlags
}

function Get-SanitizerCallStatus {
    return $featureFlags.activate -or $featureFlags.audit -or $featureFlags.telemetry
}

function Get-SanitizerActivateStatus {
    $activateFlag = $featureFlags.activate
    Write-Verbose "Feature flag AZP_75787_ENABLE_NEW_LOGIC state: $activateFlag"
    return $activateFlag
}

# Checks the AzureFileCopy.EnableSourcePathHardening pipeline feature flag via
# Get-VstsPipelineFeature. That cmdlet was only added in a later VstsTaskSdk
# release, so on an older agent it may not exist yet even though the task's
# own minimumAgentVersion allows the task to run. Calling it unguarded would
# throw command-not-found and break the task outright. Guard for that case by
# checking cmdlet availability first, attempting to re-import the task's local
# VstsTaskSdk copy if needed, and falling back to "disabled" if the cmdlet is
# still unavailable or the flag check itself throws.
function Get-SourcePathHardeningFeatureFlag {
    $hasFeatureFlagCmdlet = Get-Command -Name 'Get-VstsPipelineFeature' -ErrorAction SilentlyContinue

    if (-not $hasFeatureFlagCmdlet) {
        Write-Warning "Get-VstsPipelineFeature cmdlet not found. Attempting to import VstsTaskSdk module..."
        try {
            Import-Module (Join-Path $PSScriptRoot '..\VstsTaskSdk') -ErrorAction Stop
            $hasFeatureFlagCmdlet = Get-Command -Name 'Get-VstsPipelineFeature' -ErrorAction SilentlyContinue
        }
        catch {
            Write-Warning "Failed to import VstsTaskSdk module: $_"
        }
    }

    if (-not $hasFeatureFlagCmdlet) {
        Write-Warning "Get-VstsPipelineFeature cmdlet unavailable (older agent or missing module). SourcePath hardening will remain disabled."
        return $false
    }

    try {
        return (Get-VstsPipelineFeature -FeatureName 'AzureFileCopy.EnableSourcePathHardening' -ErrorAction Stop)
    }
    catch {
        Write-Warning "Failed to check AzureFileCopy.EnableSourcePathHardening feature flag: $_. Defaulting to disabled."
        return $false
    }
}

# This is a wrapper for Get-SanitizedArguments to handle feature flags in one place
# It will return sanitized arguments string if feature flag is enabled
function Protect-ScriptArguments([string]$inputArgs, [string]$taskName, [switch]$AllowDataConstructors) {
    $script:taskName = $taskName

    # In the relaxed mode, run the structural AST backstop on the RAW arguments
    # first. This module only validates - it does not rewrite what the task runs -
    # so the raw string is exactly what PowerShell parses at the dot-source sink.
    # The relaxed allow-list permits @ { } [ ], which re-enables expressions that
    # evaluate at bind time (a hashtable value, cast or sub-expression);
    # Test-SanitizerArgumentAst rejects those while still allowing pure data
    # literals such as @{ Port = 8080 }.
    $astSafe = $true
    if ($AllowDataConstructors) {
        $astSafe = Test-SanitizerArgumentAst $inputArgs
    }

    $expandedArgs, $expandTelemetry = Expand-EnvVariables $inputArgs;

    $sanitizedArgs, $sanitizeTelemetry = Get-SanitizedArguments -InputArgs $expandedArgs -AllowDataConstructors:$AllowDataConstructors

    if (($sanitizedArgs -eq $inputArgs) -and $astSafe) {
        Write-Debug 'Arguments passed sanitization without change.'
    }
    else {
        if ($featureFlags.telemetry) {
            $telemetry = $expandTelemetry;
            if ($null -ne $sanitizeTelemetry) {
                $telemetry += $sanitizeTelemetry;
            }
            if (-not $astSafe) {
                if ($null -eq $telemetry) {
                    $telemetry = @{}
                }
                $telemetry.astBackstopRejected = $true
            }
            Publish-Telemetry $telemetry;
        }

        if (($sanitizedArgs -ne $expandedArgs) -or (-not $astSafe)) {
            $message = (Get-VstsLocString -Key 'PS_ScriptArgsSanitized');

            if ($featureFlags.activate) {
                Write-Error $message
                throw $message
            }
            elseif ($featureFlags.audit) {
                Write-VstsTaskWarning -Message $message -AuditAction 1
            }
        }
    }

    $arrayOfArguments = Split-Arguments -Arguments $sanitizedArgs
    return $arrayOfArguments
}

# public functions - end

# !ATTENTION: don't write any console output in this method, because it will break result
function Get-SanitizedArguments([string]$inputArgs, [switch]$AllowDataConstructors) {
    $removedSymbolSign = '_#removed#_';
    $argsSplitSymbols = '``';
    [string[][]]$matchesChunks = @()

    ## PowerShell Regex is case insensitive by default, so we don't need to specify a-zA-Z.
    ## ('?<!`') - checking if before character no backtick.
    ## ([^\w` _'"-=\/:\.*,+~?%\n#]) - checking if character is allowed. Instead replacing to #removed#
    ## (?!true|false) - checking if after characters sequence no $true or $false.
    ##
    ## Two validation modes exist because there are two groups of tasks:
    ##   * Strict (default) - the regex below. Used by the long-standing direct
    ##     callers; their behavior must stay exactly the same.
    ##   * Relaxed (-AllowDataConstructors) - additionally allows the data-
    ##     constructor characters @ { } [ ] so legitimate hashtable params are not
    ##     mangled. Any code execution those characters could re-enable (e.g.
    ##     @{ k = cmd }) is blocked structurally by Test-SanitizerArgumentAst,
    ##     not by this allow-list. (@(...) arrays stay blocked in both modes -
    ##     parentheses are never allowed.)
    ## Long-term these two modes should be unified into one consistent validation.
    if ($AllowDataConstructors) {
        $regex = '(?<!`)([^\w\\` _''"\-=\/:\.*,+~?%\n#@{}\[\]])(?!true|false)'
    }
    else {
        $regex = '(?<!`)([^\w\\` _''"\-=\/:\.*,+~?%\n#])(?!true|false)'
    }

    # We're splitting by ``, removing all suspicious characters and then join
    $argsArr = $inputArgs -split $argsSplitSymbols;

    for ($i = 0; $i -lt $argsArr.Length; $i++ ) {
        [string[]]$matches = (Select-String $regex -input $argsArr[$i] -AllMatches) | ForEach-Object { $_.Matches }
        if ($null -ne $matches ) {
            $matchesChunks += , $matches;
            $argsArr[$i] = $argsArr[$i] -replace $regex, $removedSymbolSign;
        }
    }

    $resultArgs = $argsArr -join $argsSplitSymbols;

    $telemetry = $null
    if ( $resultArgs -ne $inputArgs) {
        $argMatches = $matchesChunks | ForEach-Object { $_ } | Where-Object { $_ -ne $null }
        $telemetry = @{
            removedSymbols      = Join-Matches -Matches $argMatches
            removedSymbolsCount = $argMatches.Count
        }
    }

    return $($resultArgs, $telemetry);
}

# Structural backstop for the relaxed validation mode.
#
# A character allow-list alone cannot tell a data literal from code: once
# @ { } [ ] are permitted, an argument such as @{ k = New-Item ... },
# @{ k = $(...) } or @{ k = [type]::Member() } passes the regex yet is an
# evaluated expression at the dot-source sink - a hashtable value, cast or
# sub-expression inside a data constructor runs, whereas the same tokens at
# top-level argument position are inert literal strings.
#
# This function parses the raw arguments exactly as the sink does - as the
# argument list of a command invocation - and rejects anything that is not a
# plain data literal:
#   * a parse error,
#   * a script block, member access / method call, type-cast, the -as
#     conversion operator, or a bare type reference,
#   * a nested command (more than the single placeholder CommandAst), which
#     covers commands embedded in a hashtable value or a chained statement.
# Pure data literals (@{ Port = 8080 }), variables including $env:VAR, quoted
# strings and numbers are accepted. (@(...) arrays pass this check but are still
# rejected by the character allow-list, which does not permit parentheses.)
#
# Returns $true when the arguments are safe, $false when a dangerous construct
# is present.
function Test-SanitizerArgumentAst([string]$inputArgs) {
    if ([string]::IsNullOrWhiteSpace($inputArgs)) {
        return $true
    }

    $tokens = $null
    $parseErrors = $null
    # A literal placeholder command name keeps the parse focused on the argument
    # expressions and mirrors how the arguments reach the sink.
    $ast = [System.Management.Automation.Language.Parser]::ParseInput(
        "& placeholder $inputArgs", [ref]$tokens, [ref]$parseErrors)

    if ($parseErrors -and $parseErrors.Count -gt 0) {
        return $false
    }

    # $script:DangerousAstNodeTypes lists the node types that execute code (see its
    # definition for the rationale). InvokeMemberExpressionAst derives from
    # MemberExpressionAst, so method calls are covered by that single entry. The -as
    # conversion operator (a BinaryExpressionAst with the 'As' operator) is the
    # semantically equivalent form of a [type] cast and likewise invokes the target
    # type's constructor / type-converter at the sink - verified to execute with both
    # a [type] literal and a string/variable right operand - so it is rejected here
    # too. (Top-level type literals passed as plain arguments do not parse as
    # TypeExpressionAst and remain allowed.)
    $dangerous = $ast.FindAll({
            param($node)
            $isDangerousType = $false
            foreach ($t in $script:DangerousAstNodeTypes) {
                if ($node -is $t) { $isDangerousType = $true; break }
            }
            $isDangerousType -or
            (($node -is [System.Management.Automation.Language.BinaryExpressionAst]) -and
             ($node.Operator -eq [System.Management.Automation.Language.TokenKind]::As))
        }, $true)
    if ($dangerous -and $dangerous.Count -gt 0) {
        return $false
    }

    # Exactly one CommandAst is expected - our placeholder. Any additional
    # CommandAst means a command nested inside a data constructor or a chained
    # statement.
    $commandAsts = $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst]
        }, $true)
    if ($commandAsts.Count -gt 1) {
        return $false
    }

    return $true
}

function Publish-Telemetry($telemetry) {
    $area = 'TaskHub'
    $feature = $script:taskName
    $telemetryJson = $telemetry | ConvertTo-Json -Compress
    Write-Host "##vso[telemetry.publish area=$area;feature=$feature]$telemetryJson"
}

# Splits a string into array of arguments, considering quotes.
function Split-Arguments {
    [OutputType([String[]])]
    param(
        [string]$arguments
    )

    # If the incoming arguments string is null or empty or space, return an empty array
    if ([string]::IsNullOrWhiteSpace($arguments)) {
        return New-Object string[] 0
    }

    # Use regular expression to match all possible formats of arguments:
    # 1) "arg" (enclosed in double quotes)
    # 2) 'arg' (enclosed in single quotes)
    # 3) arg (not enclosed in quotes)
    # Each match found by the regular expression will have several groups.
    # Group[0] is the whole match, Group[1] is the match for "arg", Group[2] is the match for 'arg'.
    $matchesList = [System.Text.RegularExpressions.Regex]::Matches($arguments, "`"([^`"]*)`"|'([^']*)'|[^ ]+")

    $result = @()

    foreach ($match in $matchesList) {
        # Attempt to get the argument from Group[1] (for "arg").
        $arg = $match.Groups[1].Value

        # If Group[1] didn't have a match (was not "arg" format), try Group[2] (for 'arg').
        if ([string]::IsNullOrEmpty($arg)) {
            $arg = $match.Groups[2].Value
        }

        # If neither Group[1] nor Group[2] had a match (was not enclosed in quotes), use the whole match (Group[0]).
        if ([string]::IsNullOrEmpty($arg)) {
            $arg = $match.Groups[0].Value
        }

        # Add the extracted argument to the result array.
        $result += $arg
    }

    return $result
}

function Split-AdditionalArguments
{
    param([string]$additionalArguments)

    $tokens = New-Object System.Collections.Generic.List[string]
    $current = New-Object System.Text.StringBuilder
    $hasToken = $false
    $i = 0
    $length = $additionalArguments.Length

    while ($i -lt $length)
    {
        $char = $additionalArguments[$i]

        if ($char -eq '"' -or $char -eq "'")
        {
            $quoteChar = $char
            $hasToken = $true
            $i++
            # A doubled quote char inside the quoted section (e.g. "" inside a
            # double-quoted token) is an escaped literal quote, not the
            # terminator - mirrors the escaping Join-SanitizedArguments applies
            # when re-quoting a token whose original value contains an embedded
            # quote character. Without this, such a token would be mis-split.
            while ($i -lt $length)
            {
                if ($additionalArguments[$i] -eq $quoteChar)
                {
                    if (($i + 1) -lt $length -and $additionalArguments[$i + 1] -eq $quoteChar)
                    {
                        [void]$current.Append($quoteChar)
                        $i += 2
                        continue
                    }
                    $i++
                    break
                }
                [void]$current.Append($additionalArguments[$i])
                $i++
            }
        }
        elseif ([char]::IsWhiteSpace($char))
        {
            if ($hasToken)
            {
                $tokens.Add($current.ToString())
                [void]$current.Clear()
                $hasToken = $false
            }
            $i++
        }
        else
        {
            [void]$current.Append($char)
            $hasToken = $true
            $i++
        }
    }

    if ($hasToken)
    {
        $tokens.Add($current.ToString())
    }

    return $tokens.ToArray()
}

# Joins an array of already-tokenized arguments (e.g. the output of
# Protect-ScriptArguments/Split-Arguments, whose original quote characters
# have already been stripped) back into a single string, re-quoting any
# token that contains whitespace.
#
# This is required whenever sanitized tokens are subsequently re-split by
# Split-AdditionalArguments (the SourcePath-hardening call-operator path):
# without re-quoting, a token such as "sub folder\a.txt" would be rejoined as
# an unquoted "sub folder\a.txt" and then incorrectly re-split into two
# separate tokens ("sub" and "folder\a.txt"), corrupting the value passed to
# AzCopy.
function Join-SanitizedArguments
{
    param([string[]]$arguments)

    if (-not $arguments -or $arguments.Count -eq 0)
    {
        return ''
    }

    # A token needs re-quoting if it contains whitespace (or it would be
    # re-split into multiple tokens by Split-AdditionalArguments) or an
    # embedded quote character (or that character would be silently swallowed
    # as an unmatched quote). Any embedded double quote is escaped by
    # doubling it - the same escape convention Split-AdditionalArguments
    # understands - so the original token round-trips intact instead of
    # being corrupted or mis-split (e.g. a"b c would otherwise rejoin as
    # "a"b c" and re-split into ab, c).
    $quoted = $arguments | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + $_.Replace('"', '""') + '"' } else { $_ }
    }

    return ($quoted -join ' ')
}

function Join-Matches {
    param (
        [Parameter(Mandatory = $true)]
        [String[]]$Matches
    )

    $matchesData = @{}
    foreach ($m in $Matches) {
        if ($matchesData.ContainsKey($m)) {
            $matchesData[$m]++
        }
        else {
            $matchesData[$m] = 1
        }
    }

    return $matchesData
}

# SIG # Begin signature block
# MIInRAYJKoZIhvcNAQcCoIInNTCCJzECAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCC0fo6aw39hLrDB
# yQjBsE/aTwPK/D97aIQpddzrRrUAPqCCDLowggX1MIID3aADAgECAhMzAAACHU0Z
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
# 1cY2L4A7GTQG1h32HHAvfQESWP0xghngMIIZ3AIBATBuMFcxCzAJBgNVBAYTAlVT
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMjQCEzMAAAIdTRnITtcPV0gAAAAAAh0w
# DQYJYIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIFxEe7Rw
# 2wuwRnBIlSYaBYLoWhcexMBl38vk/TWnNJM+MEIGCisGAQQBgjcCAQwxNDAyoBSA
# EgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20w
# DQYJKoZIhvcNAQEBBQAEggEADL+5YYwoX5wS6WwUVeTjtVc5DVsh6Cotigy3m963
# OdhoGO64geAgtbsWkXxZf6MhoQfJKBkeANBVSc7rOlx6HT08IB86jJZ27vn7liGS
# JewGwya+poyKjpdzauBzyBzYkIkz94iOEOPU/p13sQh3J4Q8b9vLxjTGJOMBuwvt
# sARIB3RQW+HU89z8f1wZs/zH5G0mq04S81BS0GpMOPKZfbVFXILSgbIsxR5uuX0Z
# vQKZnvzKj88/Vk4k1ubCWKisXP6dJn3jCXT3EiueM17BPo5jpYPqt64nLteemCwb
# U7SftNoe36iEJ4flnkU+hBeLTtMCtpX24er9IdfYx321paGCF5IwgheOBgorBgEE
# AYI3AwMBMYIXfjCCF3oGCSqGSIb3DQEHAqCCF2swghdnAgEDMQ8wDQYJYIZIAWUD
# BAIBBQAwggFQBgsqhkiG9w0BCRABBKCCAT8EggE7MIIBNwIBAQYKKwYBBAGEWQoD
# ATAxMA0GCWCGSAFlAwQCAQUABCCcCNGYISK7hy9jmM1XHnLfw5dLuyic2ebrENgg
# My1lTQIGaoUdTSyCGBEyMDI2MDgyNDA1MjIxMy40WjAEgAIB9KCB0aSBzjCByzEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWlj
# cm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1Mg
# RVNOOjg5MDAtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFt
# cCBTZXJ2aWNloIIR6jCCByAwggUIoAMCAQICEzMAAAIiQdL2qv/Itf8AAQAAAiIw
# DQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0
# b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
# dGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwHhcN
# MjYwMjE5MTkzOTU2WhcNMjcwNTE3MTkzOTU2WjCByzELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2Eg
# T3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjg5MDAtMDVFMC1E
# OTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIICIjAN
# BgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAtbniibpCLlLAACaPwGOQ2Uah+24Y
# L+wlhjZRHW0RqCE63ROlrJ+ezWjbtQU3YwWxXL+0X4sbXtMfh0b10qrA/lnkl/+v
# 8vcBNDM/sUT0xiGNtCu2kA2uvDss1clHlAsqcmQv4Fv98rTv2Tp1PR9q4u+5CT/A
# Aa6sstVMV/zrHhILx7I/MopFk9AEba41m1zBxc0jqOYUHH1JjFyqlls+vjdPlMp4
# RstZ/naFuFmYKR/GOVu4aUqJFo9TPy7uMIt6Og8/b1VrpHIFBRoywJeGGaToWoex
# 7ogv2pVyJjEH/AtwPKv+v9YRaHiGQeFBpMsMQfzkkzkrC+vt/aQ6szOwoDqX+Fe/
# fZDfeMjPblySOU/0ogOTHSGSIRFtPm4fOUag4eWFt/6Gr+eET8cOTj5R+uEFeiiZ
# JdBSBJTFaCzaPFFkUHDA9e/ce1gEowui7GjWe8itKnBEiLC9cIkJnX0AcXKqxQqS
# EH55kBZDqfSMl1Fqs2vLZqc/BOml4PW9XogE9z1U4KzpT4v4WGQnz8V/+oxrcj48
# tQosDpiWpqIZklP/wjgHp30U9hthzEVKQl9c7PgJg5nUDNV0Wm+GEgCywJQ8xgrI
# CO+557iY6FwJYiZr+zX671gHAOSqglDlkOpEj7ea9vDHyl1iSaUl7RXkvzJA8ycv
# 4iUVch3BcvwfjLcCAwEAAaOCAUkwggFFMB0GA1UdDgQWBBRZB8BqAyeWWxBIrvCr
# LYrrKmqM0DAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJlpxtTNRnpcjBfBgNVHR8E
# WDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9N
# aWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcmwwbAYIKwYB
# BQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20v
# cGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEw
# KDEpLmNydDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4G
# A1UdDwEB/wQEAwIHgDANBgkqhkiG9w0BAQsFAAOCAgEAYgDPp6q6cBtvbcUl7+Nq
# PgrE3tguG6GkXxY7vSWlpC0x8Ku6ZJzTjS95/lBt8fwdPNxCl4hWKwJrpewUxwhl
# 1Ot/8UbGdsI92ZkdAOHfZ3/bGgiVZuI7j1RQWov6JLTjmB9o/tfszO9MKDeaJ4Af
# 6b8u1/AH2OiQeFz72/NEM+32OXnXW58I84NbGYVDxW23MHlngAiDa86hSutpjHly
# pobbnzK2qKICXiV31mN8eP6W7m4BDU9/qV0+udtNwjxfZH3ShOxigCEWMt8ZAUw7
# xXfHbn4zqQp9/JyuqjJVbZwYw4VkBtDzNxP6MQbOVAayOqQWJJiB7W44nw6rh0/k
# 4WlVe8R3OiJ6EnN2jc1+PSR1IEJrrw3TIy5G2F3gNP9auSMUoNlPsnGQTrwIt7nW
# TyoQOVczg43/7nLv7xbV62HEZJhijd47o2it/8jGYtibuTRC9yElqK8Ke0Y3mYPi
# TCCtH6LLlY/mApua+uCx/w/UCQwI/l32WjXhXb/dCuQNEEURj/6aAfckyFYxF4/7
# ic6fC+A3eOLAKrqgzoh3ZC4MXyvJz6qQklj2fRvkQj5vOaPXAH8RDba0rjsHKcis
# 8bEQmAi/jyuPvfKK4rfRFSfyy6Anhvoy5Y9Cmg+EMurGXuK1jK9W60C6LEwWTcBZ
# 18TYyJwlgXdIu4rNck0v+KkwggdxMIIFWaADAgECAhMzAAAAFcXna54Cm0mZAAAA
# AAAVMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBB
# dXRob3JpdHkgMjAxMDAeFw0yMTA5MzAxODIyMjVaFw0zMDA5MzAxODMyMjVaMHwx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMIICIjANBgkqhkiG9w0BAQEFAAOC
# Ag8AMIICCgKCAgEA5OGmTOe0ciELeaLL1yR5vQ7VgtP97pwHB9KpbE51yMo1V/YB
# f2xK4OK9uT4XYDP/XE/HZveVU3Fa4n5KWv64NmeFRiMMtY0Tz3cywBAY6GB9alKD
# RLemjkZrBxTzxXb1hlDcwUTIcVxRMTegCjhuje3XD9gmU3w5YQJ6xKr9cmmvHaus
# 9ja+NSZk2pg7uhp7M62AW36MEBydUv626GIl3GoPz130/o5Tz9bshVZN7928jaTj
# kY+yOSxRnOlwaQ3KNi1wjjHINSi947SHJMPgyY9+tVSP3PoFVZhtaDuaRr3tpK56
# KTesy+uDRedGbsoy1cCGMFxPLOJiss254o2I5JasAUq7vnGpF1tnYN74kpEeHT39
# IM9zfUGaRnXNxF803RKJ1v2lIH1+/NmeRd+2ci/bfV+AutuqfjbsNkz2K26oElHo
# vwUDo9Fzpk03dJQcNIIP8BDyt0cY7afomXw/TNuvXsLz1dhzPUNOwTM5TI4CvEJo
# LhDqhFFG4tG9ahhaYQFzymeiXtcodgLiMxhy16cg8ML6EgrXY28MyTZki1ugpoMh
# XV8wdJGUlNi5UPkLiWHzNgY1GIRH29wb0f2y1BzFa/ZcUlFdEtsluq9QBXpsxREd
# cu+N+VLEhReTwDwV2xo3xwgVGD94q0W29R6HXtqPnhZyacaue7e3PmriLq0CAwEA
# AaOCAd0wggHZMBIGCSsGAQQBgjcVAQQFAgMBAAEwIwYJKwYBBAGCNxUCBBYEFCqn
# Uv5kxJq+gpE8RjUpzxD/LwTuMB0GA1UdDgQWBBSfpxVdAF5iXYP05dJlpxtTNRnp
# cjBcBgNVHSAEVTBTMFEGDCsGAQQBgjdMg30BATBBMD8GCCsGAQUFBwIBFjNodHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5odG0w
# EwYDVR0lBAwwCgYIKwYBBQUHAwgwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEw
# CwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU1fZWy4/o
# olxiaNE9lJBb186aGMQwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNy
# b3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYt
# MjMuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5t
# aWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5j
# cnQwDQYJKoZIhvcNAQELBQADggIBAJ1VffwqreEsH2cBMSRb4Z5yS/ypb+pcFLY+
# TkdkeLEGk5c9MTO1OdfCcTY/2mRsfNB1OW27DzHkwo/7bNGhlBgi7ulmZzpTTd2Y
# urYeeNg2LpypglYAA7AFvonoaeC6Ce5732pvvinLbtg/SHUB2RjebYIM9W0jVOR4
# U3UkV7ndn/OOPcbzaN9l9qRWqveVtihVJ9AkvUCgvxm2EhIRXT0n4ECWOKz3+SmJ
# w7wXsFSFQrP8DJ6LGYnn8AtqgcKBGUIZUnWKNsIdw2FzLixre24/LAl4FOmRsqlb
# 30mjdAy87JGA0j3mSj5mO0+7hvoyGtmW9I/2kQH2zsZ0/fZMcm8Qq3UwxTSwethQ
# /gpY3UA8x1RtnWN0SCyxTkctwRQEcb9k+SS+c23Kjgm9swFXSVRk2XPXfx5bRAGO
# WhmRaw2fpCjcZxkoJLo4S5pu+yFUa2pFEUep8beuyOiJXk+d0tBMdrVXVAmxaQFE
# fnyhYWxz/gq77EFmPWn9y8FBSX5+k77L+DvktxW/tM4+pTFRhLy/AsGConsXHRWJ
# jXD+57XQKBqJC4822rpM+Zv/Cuk0+CQ1ZyvgDbjmjJnW4SLq8CdCPSWU5nR0W2rR
# nj7tfqAxM328y+l7vzhwRNGQ8cirOoo6CGJ/2XBjU02N7oJtpQUQwXEGahC0HVUz
# WLOhcGbyoYIDTTCCAjUCAQEwgfmhgdGkgc4wgcsxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBBbWVyaWNhIE9w
# ZXJhdGlvbnMxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo4OTAwLTA1RTAtRDk0
# NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcG
# BSsOAwIaAxUAu8nF1Wcd27A6SZK+1bnIKZLKM7iggYMwgYCkfjB8MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQg
# VGltZS1TdGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0BAQsFAAIFAO42MoUwIhgPMjAy
# NjA4MjQwMzAxMjVaGA8yMDI2MDgyNTAzMDEyNVowdDA6BgorBgEEAYRZCgQBMSww
# KjAKAgUA7jYyhQIBADAHAgEAAgIUfTAHAgEAAgISrDAKAgUA7jeEBQIBADA2Bgor
# BgEEAYRZCgQCMSgwJjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAID
# AYagMA0GCSqGSIb3DQEBCwUAA4IBAQCO7wPK7MnQmbcSnSZojZB4C1Zil+0kgSI/
# MuGyNU9nb0LBPewkcnPDPBnvTrIo7o21EbZ57fqMNshZxVPQlBBJ4heGvlJagY5u
# bEkBVKlBBsjgFAGQwI/OqdAFT5V0MwVSiNu+DkUtNLpCcepddl5OrM3OEv96PAkm
# IkGDm0z7OnskgzL5UHTk6N5gU0yLdUB3kIbyOMJbjHTKma4ZTng3XDdZ28pnTAHH
# M/DH+cYuMP82WnGL/EQJfYGPEdUYDKniJ8bd65Jva4+vfyT38srz3236Of6/5Yiq
# Vk3NlqqjeajdDbQKEV7yciLJH2rJKldUpmgcNgKHY9VhIYuZRL2xMYIEDTCCBAkC
# AQEwgZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQG
# A1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIiQdL2qv/I
# tf8AAQAAAiIwDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG
# 9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQgAwqrDld1g1NggriahXhGOg+Nq1D24w3H
# N3DS7nK60ocwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCAFYF0BCgTnxoIz
# bJJgzpm3BCDpxxjcAPkHEbnw0eQJEzCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFBDQSAyMDEwAhMzAAACIkHS9qr/yLX/AAEAAAIiMCIEINhPRXwgopUbENPZ
# lBDj/ZWW+QUN23beDMIDQHFzQl4SMA0GCSqGSIb3DQEBCwUABIICAFmsvo/+tA7x
# YouZOKrX/LsX0gs0BBSYN065Q/PU/XxeAFEzbnq1clXZworQhbNyHtAkzeEZIkie
# 2y6f+no/pFeW39Wc0nkT8Gwvmk60KAQLOw78tP3kfaxFVqpBQjhwjlAE9jWFftIz
# w2D24rErG0wH1X2utR1bU+Dqi+GRulMP+XPNvWw4AZZRDyR8l/Px6U7Xzxs32T0o
# JQTtDuir32cr3tWBz3Z0lVf7H8jFVXgEB91i18tkJUpj9OAi0wSWVYplSdrQdY4+
# K20MR812/h00LRRmGrR72VvYRnRsklZYDgk+uyOS2DEsOa1kO2FBg48s3+yTkFz/
# dW2ydP6TYZsJWpjbC7uJWyL8mXZdFNbkvhdMpnkh1Mn/xUoUwb60FI0J0P1vLwvZ
# SsquYR2qdFBTh+5H1fFDMgiS5UWqD1VG25p406VwpdBgKZxpyiwkJkre0OxAKpR6
# 4Rkm3jZx8SLFgiqrw8o+vG6/Nw2rbs+laA8b8w538qqCyTfihELdsUjv9qSP6JaX
# CxMct3NFnwZYydRkcAOOsP+NT4X1Ac4C8SbpLrcwSsD6TASKed+yl7uQOZ30MMH9
# mEYKHpmEGLZuBpLFJLQQ3Z2N3r26T6+IyUr+L1c6ZQM1QSm5Iy/XKDG/DmcUECuy
# m0IGn5Upmi/fJ+eAmamKB6QdJYvS721a
# SIG # End signature block
