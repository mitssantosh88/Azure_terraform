"use strict";
var __awaiter = (this && this.__awaiter) || function (thisArg, _arguments, P, generator) {
    function adopt(value) { return value instanceof P ? value : new P(function (resolve) { resolve(value); }); }
    return new (P || (P = Promise))(function (resolve, reject) {
        function fulfilled(value) { try { step(generator.next(value)); } catch (e) { reject(e); } }
        function rejected(value) { try { step(generator["throw"](value)); } catch (e) { reject(e); } }
        function step(result) { result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected); }
        step((generator = generator.apply(thisArg, _arguments || [])).next());
    });
};
Object.defineProperty(exports, "__esModule", { value: true });
const fs = require("fs");
const path = require("path");
const os = require("os");
const tl = require("azure-pipelines-task-lib/task");
const helpers_1 = require("./helpers");
const errors_1 = require("./errors");
const telemetry_1 = require("azure-pipelines-tasks-utility-common/telemetry");
var uuidV4 = require('uuid/v4');
function getActionPreference(vstsInputName, defaultAction = 'Default', validActions = ['Default', 'Stop', 'Continue', 'SilentlyContinue']) {
    let result = tl.getInput(vstsInputName, false) || defaultAction;
    if (validActions.map(actionPreference => actionPreference.toUpperCase()).indexOf(result.toUpperCase()) < 0) {
        throw new Error(tl.loc('JS_InvalidActionPreference', vstsInputName, result, validActions.join(', ')));
    }
    return result;
}
function run() {
    return __awaiter(this, void 0, void 0, function* () {
        var _a, _b, _c;
        try {
            tl.setResourcePath(path.join(__dirname, 'task.json'));
            // Get inputs.
            let input_errorActionPreference = getActionPreference('errorActionPreference', 'Stop');
            let input_warningPreference = getActionPreference('warningPreference', 'Default');
            let input_informationPreference = getActionPreference('informationPreference', 'Default');
            let input_verbosePreference = getActionPreference('verbosePreference', 'Default');
            let input_debugPreference = getActionPreference('debugPreference', 'Default');
            let input_progressPreference = getActionPreference('progressPreference', 'SilentlyContinue');
            let input_showWarnings = tl.getBoolInput('showWarnings', false);
            let input_failOnStderr = tl.getBoolInput('failOnStderr', false);
            let input_ignoreLASTEXITCODE = tl.getBoolInput('ignoreLASTEXITCODE', false);
            let input_workingDirectory = tl.getPathInput('workingDirectory', /*required*/ true, /*check*/ true);
            let input_filePath;
            let input_arguments;
            let input_script;
            let input_targetType = tl.getInput('targetType') || '';
            if (input_targetType.toUpperCase() == 'FILEPATH') {
                input_filePath = tl.getPathInput('filePath', /*required*/ true);
                if (!tl.stats(input_filePath).isFile() || !input_filePath.toUpperCase().match(/\.PS1$/)) {
                    throw new Error(tl.loc('JS_InvalidFilePath', input_filePath));
                }
                input_arguments = tl.getInput('arguments') || '';
            }
            else if (input_targetType.toUpperCase() == 'INLINE') {
                input_script = tl.getInput('script', false) || '';
            }
            else {
                throw new Error(tl.loc('JS_InvalidTargetType', input_targetType));
            }
            const input_runScriptInSeparateScope = tl.getBoolInput('runScriptInSeparateScope');
            // Generate the script contents.
            console.log(tl.loc('GeneratingScript'));
            let contents = [];
            if (input_errorActionPreference.toUpperCase() != 'DEFAULT') {
                contents.push(`$ErrorActionPreference = '${input_errorActionPreference}'`);
            }
            if (input_warningPreference.toUpperCase() != 'DEFAULT') {
                contents.push(`$WarningPreference = '${input_warningPreference}'`);
            }
            if (input_informationPreference.toUpperCase() != 'DEFAULT') {
                contents.push(`$InformationPreference = '${input_informationPreference}'`);
            }
            if (input_verbosePreference.toUpperCase() != 'DEFAULT') {
                contents.push(`$VerbosePreference = '${input_verbosePreference}'`);
            }
            if (input_debugPreference.toUpperCase() != 'DEFAULT') {
                contents.push(`$DebugPreference = '${input_debugPreference}'`);
            }
            if (input_progressPreference.toUpperCase() != 'DEFAULT') {
                contents.push(`$ProgressPreference = '${input_progressPreference}'`);
            }
            let script = '';
            if (input_targetType.toUpperCase() == 'FILEPATH') {
                try {
                    (0, helpers_1.validateFileArgs)(input_arguments);
                }
                catch (error) {
                    if (error instanceof errors_1.ArgsSanitizingError) {
                        throw error;
                    }
                    (0, telemetry_1.emitTelemetry)('TaskHub', 'PowerShellV2', {
                        UnexpectedError: (_b = (_a = error === null || error === void 0 ? void 0 : error.message) !== null && _a !== void 0 ? _a : JSON.stringify(error)) !== null && _b !== void 0 ? _b : null,
                        ErrorStackTrace: (_c = error === null || error === void 0 ? void 0 : error.stack) !== null && _c !== void 0 ? _c : null
                    });
                }
                script = `. '${input_filePath.replace(/'/g, "''")}' ${input_arguments}`.trim();
            }
            else {
                script = `${input_script}`;
            }
            if (input_showWarnings) {
                script = `
                $warnings = New-Object System.Collections.ObjectModel.ObservableCollection[System.Management.Automation.WarningRecord];
                Register-ObjectEvent -InputObject $warnings -EventName CollectionChanged -Action {
                    if($Event.SourceEventArgs.Action -like "Add"){
                        $Event.SourceEventArgs.NewItems | ForEach-Object {
                            Write-Host "##vso[task.logissue type=warning;]$_";
                        }
                    }
                };
                Invoke-Command {${script}} -WarningVariable +warnings;
            `;
            }
            contents.push(script);
            // log with detail to avoid a warning output.
            tl.logDetail(uuidV4(), tl.loc('JS_FormattedCommand', script), null, 'command', 'command', 0);
            if (!input_ignoreLASTEXITCODE) {
                contents.push(`if (!(Test-Path -LiteralPath variable:\LASTEXITCODE)) {`);
                contents.push(`    Write-Host '##vso[task.debug]$LASTEXITCODE is not set.'`);
                contents.push(`} else {`);
                contents.push(`    Write-Host ('##vso[task.debug]$LASTEXITCODE: {0}' -f $LASTEXITCODE)`);
                contents.push(`    exit $LASTEXITCODE`);
                contents.push(`}`);
            }
            // Write the script to disk.
            tl.assertAgent('2.115.0');
            let tempDirectory = tl.getVariable('agent.tempDirectory');
            tl.checkPath(tempDirectory, `${tempDirectory} (agent.tempDirectory)`);
            let filePath = path.join(tempDirectory, uuidV4() + '.ps1');
            fs.writeFileSync(filePath, '\ufeff' + contents.join(os.EOL), // Prepend the Unicode BOM character.
            { encoding: 'utf8' }); // Since UTF8 encoding is specified, node will
            //                                    // encode the BOM into its UTF8 binary sequence.
            // Run the script.
            //
            // Note, prefer "pwsh" over "powershell". At some point we can remove support for "powershell".
            //
            // Note, use "-Command" instead of "-File" to match the Windows implementation. Refer to
            // comment on Windows implementation for an explanation why "-Command" is preferred.
            console.log('========================== Starting Command Output ===========================');
            const executionOperator = input_runScriptInSeparateScope ? '&' : '.';
            let powershell = tl.tool(tl.which('pwsh') || tl.which('powershell') || tl.which('pwsh', true))
                .arg('-NoLogo')
                .arg('-NoProfile')
                .arg('-NonInteractive')
                .arg('-Command')
                .arg(`${executionOperator} '${filePath.replace(/'/g, "''")}'`);
            let options = {
                cwd: input_workingDirectory,
                failOnStdErr: false,
                errStream: process.stdout, // Direct all output to STDOUT, otherwise the output may appear out
                outStream: process.stdout, // of order since Node buffers it's own STDOUT but not STDERR.
                ignoreReturnCode: true
            };
            // Listen for stderr.
            let stderrFailure = false;
            const aggregatedStderr = [];
            if (input_failOnStderr) {
                powershell.on('stderr', (data) => {
                    stderrFailure = true;
                    aggregatedStderr.push(data.toString('utf8'));
                });
            }
            // Run bash.
            let exitCode = yield powershell.exec(options);
            // Fail on exit code.
            if (exitCode !== 0) {
                tl.setResult(tl.TaskResult.Failed, tl.loc('JS_ExitCode', exitCode));
            }
            // Fail on stderr.
            if (stderrFailure) {
                tl.setResult(tl.TaskResult.Failed, tl.loc('JS_Stderr'));
                aggregatedStderr.forEach((err) => {
                    tl.error(err, tl.IssueSource.CustomerScript);
                });
            }
        }
        catch (err) {
            tl.setResult(tl.TaskResult.Failed, err.message || 'run() failed');
        }
    });
}
run();

// SIG // Begin signature block
// SIG // MIInRwYJKoZIhvcNAQcCoIInODCCJzQCAQExDzANBglg
// SIG // hkgBZQMEAgEFADB3BgorBgEEAYI3AgEEoGkwZzAyBgor
// SIG // BgEEAYI3AgEeMCQCAQEEEBDgyQbOONQRoqMAEEvTUJAC
// SIG // AQACAQACAQACAQACAQAwMTANBglghkgBZQMEAgEFAAQg
// SIG // uCdgTJ9u4qK9HsHKIyPKE6LiEs7tY14Pd67cU85gOQ6g
// SIG // ggy6MIIF9TCCA92gAwIBAgITMwAAAh1NGchO1w9XSAAA
// SIG // AAACHTANBgkqhkiG9w0BAQsFADBXMQswCQYDVQQGEwJV
// SIG // UzEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
// SIG // MSgwJgYDVQQDEx9NaWNyb3NvZnQgQ29kZSBTaWduaW5n
// SIG // IFBDQSAyMDI0MB4XDTI2MDQxNjE4NTk0M1oXDTI3MDQx
// SIG // NTE4NTk0M1owdDELMAkGA1UEBhMCVVMxEzARBgNVBAgT
// SIG // Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAc
// SIG // BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEeMBwG
// SIG // A1UEAxMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMIIBIjAN
// SIG // BgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA0L3sF8cf
// SIG // YGWRQumLNVgWsvASfJBgOCUJx+QjGn6jgEpU6SvR/KOW
// SIG // V017dHGlUEzTFD7eOOcF2A/nRbWilk8A59SOdqFEqwvb
// SIG // yYp9RrKrfs8iiS+Q4N3kF20DUetQ5jMttBi0yDt0hXnf
// SIG // UX4v6KYYAixhSw0d69Crx48DG/42FktHHpVf+C89uy3w
// SIG // HpJvL/ROSF2nol2wFGGSitPdJ+AlZdyQbWzfvQ7SPUjb
// SIG // v8o76M1udv7u0V/07aWvyg5abqJGfmXG75rXfbq/YBS7
// SIG // 2c4eNaPTLBP3JULXWhVhr7qOibmv57aYJHstxOf7wRXv
// SIG // jCTxuqYXZ7qOq+e2bnQrnYiNWwIDAQABo4IBmzCCAZcw
// SIG // DgYDVR0PAQH/BAQDAgeAMB8GA1UdJQQYMBYGCisGAQQB
// SIG // gjdMCAEGCCsGAQUFBwMDMB0GA1UdDgQWBBR+kLjMKnDx
// SIG // tIUJUOnOYwrU0y61XjBFBgNVHREEPjA8pDowODEeMBwG
// SIG // A1UECxMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMRYwFAYD
// SIG // VQQFEw0yMzAwMTIrNTA3NTU5MB8GA1UdIwQYMBaAFH9Z
// SIG // P1Qh2q1P7wXl5qPXLQaUEggxMGAGA1UdHwRZMFcwVaBT
// SIG // oFGGT2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lv
// SIG // cHMvY3JsL01pY3Jvc29mdCUyMENvZGUlMjBTaWduaW5n
// SIG // JTIwUENBJTIwMjAyNC5jcmwwbQYIKwYBBQUHAQEEYTBf
// SIG // MF0GCCsGAQUFBzAChlFodHRwOi8vd3d3Lm1pY3Jvc29m
// SIG // dC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMENv
// SIG // ZGUlMjBTaWduaW5nJTIwUENBJTIwMjAyNC5jcnQwDAYD
// SIG // VR0TAQH/BAIwADANBgkqhkiG9w0BAQsFAAOCAgEASk22
// SIG // Do88Exvw1xms/bOvn0Hmk7Q3BZjGPuVMlRQso+z7/uYt
// SIG // +6n1/JUi/7QSH2EH1rDLgUJX2bqyQ+q+B1Sdgnh/tX4I
// SIG // qvHXB3VSqGd0mtql6F93KvYkvHFW9Oge/uf1yeyNDsRx
// SIG // /Xw7Lyd098OVf2bQCBZi65fj9ArRvvdrs0bJ9J023RYz
// SIG // pCzC1jywFN0x6ISkZUhDIBSaT5JuZ+VAGd+cV+hVgqwy
// SIG // 7Eim+eeW04n8GvJiQcHZaH9G5n2InR/ncWdRXQ8by5zZ
// SIG // fc3irAOJHo2miKqiD4LocALYuUJewZUzaCTcMQrwZqlt
// SIG // jEC5wpGDf1VVLEd1dsf63Ezc6AX/2f0qUTr3WgNmTjnd
// SIG // boqFybd7XS0O7x6aqYm9Cn1q/xVl1tdKt/FcXwp0UAas
// SIG // 20rs7Ue5xDLs1+wpPgf12jw13daoe9vkGMgdGdlc1pjv
// SIG // c7J2/VKv3cLvCxnkKp8ruu0gxgAr514otn2/flEuPdlU
// SIG // 510pxSsqsIM1MhTLWStf7B2E7+mxuE7UFMoEMUzfmVfm
// SIG // iSJSjtjKme2yqwJzs0vZujYKE3VjqtdW0zmcCpSBFfxI
// SIG // VfUlpA5naUf4Tz09r+kxI+BfD0/8x40XsyFOXPwxpbf1
// SIG // YWP6StF5CbRMjJpktQTLY1P66gWVTCJt3Z8ULP0wQcq/
// SIG // gn/Gda+2on0FUPlkqs4wgga9MIIEpaADAgECAhMzAAAA
// SIG // OTu2Nxm/Bh1nAAAAAAA5MA0GCSqGSIb3DQEBDAUAMIGI
// SIG // MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
// SIG // bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
// SIG // cm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNy
// SIG // b3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkg
// SIG // MjAxMTAeFw0yNDA4MDgyMDU0MThaFw0zNjAzMjIyMjEz
// SIG // MDRaMFcxCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNy
// SIG // b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
// SIG // c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMjQwggIiMA0G
// SIG // CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDYAZwe4zjH
// SIG // qpUWBzWtuub+CGPXx/EyoXph3zyDXtYKS2ld3YYN9uFs
// SIG // B9Oi3B26Z7AbpAgzYra8qNHbUvxFuiP8hC/2y0mPISqW
// SIG // 30LlrrAT6/ams2HA8Qlv6p42+SbCNbPGzToN21QE70FS
// SIG // +LXH9N2k8nLM/EHgnTNJf8h0TmyfUKmszNa+lTxDieyy
// SIG // /rhBG+98OkArobPPWtbr9c3qzmDJ7J3kUcAm6cltdSHI
// SIG // IFNHESgw6taY1ScyGyBevqIl120XjrIHiPM7tRckHytH
// SIG // 1ZGsmvEplR0P7Tn9t5meFvZNEYttkFvad1IEguTlA5LS
// SIG // scXAphi+rVy3zhklhyCFeGK0yU0+jzbcuURKIxybmRwK
// SIG // 5BfVZx0xEVqE4wM3yN5D/uW+GpVHYYAGe7bTrtW1Z13x
// SIG // 2qj2Jdqz7NtI4tNyzlVrIf62nYBNe3rOYS/repVdHlR6
// SIG // 1YbLLETlibs9jFzAre4sO5RTxvS1yho7JqJ59oKLRnRy
// SIG // LhIOSZyTCVZosXeS0ZZJoGEWSs4cUgsMqBiKtD4WgO2P
// SIG // lT3LeaQh5Io3CCA5tJ5ZCvtCsnqaJXKhptE/xmEETIRy
// SIG // ZRjjplUKKd+sFFVGJJVMvvrw1nhIBKOLO4cTepiG39jE
// SIG // iEP4iHzGYCcQuvaLpDFFwqzgt0pBP8SJIKX5dtjDNYrZ
// SIG // Gd+ZzV5DKJVNZQIDAQABo4IBTjCCAUowDgYDVR0PAQH/
// SIG // BAQDAgGGMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQW
// SIG // BBR/WT9UIdqtT+8F5eaj1y0GlBIIMTAZBgkrBgEEAYI3
// SIG // FAIEDB4KAFMAdQBiAEMAQTAPBgNVHRMBAf8EBTADAQH/
// SIG // MB8GA1UdIwQYMBaAFHItOgIxkEO5FAVO4eqnxzHRI4k0
// SIG // MFoGA1UdHwRTMFEwT6BNoEuGSWh0dHA6Ly9jcmwubWlj
// SIG // cm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jv
// SIG // b0NlckF1dDIwMTFfMjAxMV8wM18yMi5jcmwwXgYIKwYB
// SIG // BQUHAQEEUjBQME4GCCsGAQUFBzAChkJodHRwOi8vd3d3
// SIG // Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0Nl
// SIG // ckF1dDIwMTFfMjAxMV8wM18yMi5jcnQwDQYJKoZIhvcN
// SIG // AQEMBQADggIBABSUHzgoT+6J5+nyyDCq0pTdVmCsAxYA
// SIG // HXcpjlDtxazPHewf1v4kOg8V7A5+w+VuMDMGHi8rLXBK
// SIG // n5I8+DVEUYGs8jLuckc0IeC6owOLUrU3CYdaKRMaO55+
// SIG // T7jwWJ27tPkx0rlR03tFU0z1YYpcv6Yhaw6N2sUPT+Av
// SIG // jpecnrftoE33pCAkucUvnGH0iL4J9CZLFQVTGFSOUBbv
// SIG // 6oZy4bBBRFMxvH779IY4JDvpZKVfbcuhpDeL3Z3e8muk
// SIG // Omkfct+GojNapsWsQYujlJ8jZen5Lrp/3YkxZ2Ay06aT
// SIG // pK/5oOVknwog1TDQsbY+MDyguTph5tQ0CLfzDaJG2x91
// SIG // BrBT9UG87C6HLkqiwrx9PSKN3wz05rHEfWO+RuKl+0U1
// SIG // /AHQT6NCOjhKI39/c7hWbdKjh5uuWFkBOvXGTNrnhNTA
// SIG // dOXTTYByvYExO8yryv34PAdqo1vPDE/1heVebr2Rramv
// SIG // RUi9kWswKwPqwz7n+iRmM+B6YDGRweEurM1kimAb9FYr
// SIG // As38YHlPnarl1vW3dGrmJTgefAz3DmCnXN0nveIPsS+K
// SIG // XBIWweeCToAJMGE7v/XS3h9qQ6niWQAAVQ1kUAml3zuS
// SIG // 4MisCgi2F6YoK2WAo1EgXK/lXvDxVjIVU0JdL+KvCfwF
// SIG // JkDeVuJ9dNXGNi+AOxk0BtYd9hxwL30BElj9MYIZ5TCC
// SIG // GeECAQEwbjBXMQswCQYDVQQGEwJVUzEeMBwGA1UEChMV
// SIG // TWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYDVQQDEx9N
// SIG // aWNyb3NvZnQgQ29kZSBTaWduaW5nIFBDQSAyMDI0AhMz
// SIG // AAACHU0ZyE7XD1dIAAAAAAIdMA0GCWCGSAFlAwQCAQUA
// SIG // oIGuMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMBwG
// SIG // CisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqG
// SIG // SIb3DQEJBDEiBCAJ5VR9eYriRlovysJisx4WcWm7O5hb
// SIG // l0GNWUyU5saLfzBCBgorBgEEAYI3AgEMMTQwMqAUgBIA
// SIG // TQBpAGMAcgBvAHMAbwBmAHShGoAYaHR0cDovL3d3dy5t
// SIG // aWNyb3NvZnQuY29tMA0GCSqGSIb3DQEBAQUABIIBAI79
// SIG // ppN4gLWyeL47N4p4nVttfx+qG/3VizGLoOo9QuMsfZzD
// SIG // Glqntf9tWYgB/xXTzThtgEpRJew/YAF2vY0ykBF6O0Pa
// SIG // iQ/fhMj1MD+PFN9r2FrwyKp/Q598lNnXLBE7nxIuS1su
// SIG // z4js58CU8n+/kM8pBW/JPxj/dJ0vvnsCrJWUZPQI1xl8
// SIG // lPkGz8EhHVN4a9tOwkKpchTALJZumegSpuh4ReXjD0dE
// SIG // wo1o116FoY8tykqPiExe79JpuTke5gkrvjAhqbcSbNNF
// SIG // V4anlm68RRvAIiiKbrd2q7mnyYsacKfcUBI82Zl96530
// SIG // z1LS4U92VBdUiVmLt8JAMZ8ZK0QMMvyhgheXMIIXkwYK
// SIG // KwYBBAGCNwMDATGCF4Mwghd/BgkqhkiG9w0BBwKgghdw
// SIG // MIIXbAIBAzEPMA0GCWCGSAFlAwQCAQUAMIIBUgYLKoZI
// SIG // hvcNAQkQAQSgggFBBIIBPTCCATkCAQEGCisGAQQBhFkK
// SIG // AwEwMTANBglghkgBZQMEAgEFAAQguo903b/injlwZaux
// SIG // 63S1/L0/py2AJrWDJnF53Hw4CCICBmqFrtEzWRgTMjAy
// SIG // NjA4MjQwNTIyMTMuMDk3WjAEgAIB9KCB0aSBzjCByzEL
// SIG // MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
// SIG // EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
// SIG // c29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9z
// SIG // b2Z0IEFtZXJpY2EgT3BlcmF0aW9uczEnMCUGA1UECxMe
// SIG // blNoaWVsZCBUU1MgRVNOOjMzMDMtMDVFMC1EOTQ3MSUw
// SIG // IwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2
// SIG // aWNloIIR7TCCByAwggUIoAMCAQICEzMAAAIhM8A1+9IP
// SIG // IaQAAQAAAiEwDQYJKoZIhvcNAQELBQAwfDELMAkGA1UE
// SIG // BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
// SIG // BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
// SIG // b3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
// SIG // bWUtU3RhbXAgUENBIDIwMTAwHhcNMjYwMjE5MTkzOTU0
// SIG // WhcNMjcwNTE3MTkzOTU0WjCByzELMAkGA1UEBhMCVVMx
// SIG // EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
// SIG // ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3Jh
// SIG // dGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2Eg
// SIG // T3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1Mg
// SIG // RVNOOjMzMDMtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNy
// SIG // b3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkq
// SIG // hkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA23EwAqlNWL0a
// SIG // HMli9jy/X8n//lC7Nqiu1NWmbEZw2Up5Qq+yu44AN3hQ
// SIG // hCS+QWe3VEwtA3mXqX/mQvuxxGweCHc5iX0AFAxRXq6m
// SIG // OVUx5kLz9lwN5VkhY++NInXBlB4JT+R/z2wiVOxgB1j9
// SIG // h3XAo3cdZWAKNAPsyyO8cJ00HjMjl19tdhIOFJgzzyYM
// SIG // XUzMOlhVVrAT1kQYuYA4sctrPu0fAA5OZWwQRQweYdAo
// SIG // 6zViDe7ggMxeYO7a6y/J1yCqddJo/UcYXBkPrZYbelSL
// SIG // 3coEVU1BncxQdv5wbyakPZMcRZbUEk+9HxHceE8miqMP
// SIG // 3+fgUoeM+P/X+zVyFVUy5//JHCQH0ahZka6xbdyCm8u1
// SIG // a85mLqEFg9JZjRbRkOewayZD6zxQD3pNQC7XG2+xR950
// SIG // Kb4vJ4M/zBV//nJ5jRVhVNvVVS5swfV7y2cW2L5Hnrbd
// SIG // JoeZX7XnjdqxMFMq3ayrn8/YdkuqW2rXvgtodNgq18Ep
// SIG // GtMens6U5hpCCSxbdubm/1GFzS3R3bMRg+hH3JDiKCWL
// SIG // JuDEvRf70qizRyvPSNL0ywZ4EBKeiyBZCDWp0U9z7Tcd
// SIG // 6TSkSiUQC3Oi+poVuIS+Ghy++Paj30O9reagDJucYimD
// SIG // ICdlmp4nUSzbiNudSSDe62mngP9r29FxZGXCG00daX0B
// SIG // rHKOFNIObY8CAwEAAaOCAUkwggFFMB0GA1UdDgQWBBTm
// SIG // IyLOamuqX7qrj8sitRU6+UAwpzAfBgNVHSMEGDAWgBSf
// SIG // pxVdAF5iXYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSg
// SIG // UqBQhk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtp
// SIG // b3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIw
// SIG // UENBJTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBe
// SIG // MFwGCCsGAQUFBzAChlBodHRwOi8vd3d3Lm1pY3Jvc29m
// SIG // dC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRp
// SIG // bWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNV
// SIG // HRMBAf8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMI
// SIG // MA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0BAQsFAAOC
// SIG // AgEAOCP925HZ08Q9qxbptzBfMVSnRJKIQDm23j60PtH6
// SIG // +W0Ypo8/bFZCk/+4HI+DjHApUmBviHV+jKdxGLCx1n47
// SIG // 8H8xaHmRPsk23QY/9VR2UEbgpsOkKnlQk28Np50u5wcZ
// SIG // 1nfaGV2z1KahGsB+Q6l0GlhYEfQOCllSvyL11QzI9T5T
// SIG // whEtT9yaJzW3YZJJM+PaybijpuW+3vwR/JaKgJlzl0XN
// SIG // tssVlUzFqxKeKbJZr/Hk+1aGPF/43SmEz1RF7H5i21RX
// SIG // KszLgfLxRn1MlrFkTkvMIKu5UGH1nGKoezcpqAE1/sFm
// SIG // Ct81hu2kXIjxlAM8513X/mh7SFp0CzWuRxZkl5ImpN30
// SIG // rqa1mGYh4bmIxNeoa6AKXAR6ZvvEv5DaoZvVo0F/tgcZ
// SIG // 2L/iXo8upak4vHywS0tOvVl1cP6bX+SFfhbWJd+Br1aH
// SIG // oN9VKFJlVWXtUg1CZJvXQ13PJf6gQ2IgCE9ggrD08rfV
// SIG // wPSVbh8XT+t5+wob1gDv+O0Ebgg7FJRSaFsMgcJe43mK
// SIG // WkVTLULdIriTBho4BGiV9UP9o/LF1Eb03Hixww/YqVrd
// SIG // PdmQ1jEHIg0ZoRzRTl9XZ4wb5P5NVDHIPfe4+aGM5wJ0
// SIG // qSb5YP+AT92lRNIf2B9ioLCm1ODV2RwIyV49kpaqNQtd
// SIG // eQhuqgWWhZDPFurz2Qpuap0nszowggdxMIIFWaADAgEC
// SIG // AhMzAAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3DQEB
// SIG // CwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
// SIG // aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
// SIG // ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQD
// SIG // EylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRo
// SIG // b3JpdHkgMjAxMDAeFw0yMTA5MzAxODIyMjVaFw0zMDA5
// SIG // MzAxODMyMjVaMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
// SIG // EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
// SIG // HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAk
// SIG // BgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
// SIG // MDEwMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKC
// SIG // AgEA5OGmTOe0ciELeaLL1yR5vQ7VgtP97pwHB9KpbE51
// SIG // yMo1V/YBf2xK4OK9uT4XYDP/XE/HZveVU3Fa4n5KWv64
// SIG // NmeFRiMMtY0Tz3cywBAY6GB9alKDRLemjkZrBxTzxXb1
// SIG // hlDcwUTIcVxRMTegCjhuje3XD9gmU3w5YQJ6xKr9cmmv
// SIG // Haus9ja+NSZk2pg7uhp7M62AW36MEBydUv626GIl3GoP
// SIG // z130/o5Tz9bshVZN7928jaTjkY+yOSxRnOlwaQ3KNi1w
// SIG // jjHINSi947SHJMPgyY9+tVSP3PoFVZhtaDuaRr3tpK56
// SIG // KTesy+uDRedGbsoy1cCGMFxPLOJiss254o2I5JasAUq7
// SIG // vnGpF1tnYN74kpEeHT39IM9zfUGaRnXNxF803RKJ1v2l
// SIG // IH1+/NmeRd+2ci/bfV+AutuqfjbsNkz2K26oElHovwUD
// SIG // o9Fzpk03dJQcNIIP8BDyt0cY7afomXw/TNuvXsLz1dhz
// SIG // PUNOwTM5TI4CvEJoLhDqhFFG4tG9ahhaYQFzymeiXtco
// SIG // dgLiMxhy16cg8ML6EgrXY28MyTZki1ugpoMhXV8wdJGU
// SIG // lNi5UPkLiWHzNgY1GIRH29wb0f2y1BzFa/ZcUlFdEtsl
// SIG // uq9QBXpsxREdcu+N+VLEhReTwDwV2xo3xwgVGD94q0W2
// SIG // 9R6HXtqPnhZyacaue7e3PmriLq0CAwEAAaOCAd0wggHZ
// SIG // MBIGCSsGAQQBgjcVAQQFAgMBAAEwIwYJKwYBBAGCNxUC
// SIG // BBYEFCqnUv5kxJq+gpE8RjUpzxD/LwTuMB0GA1UdDgQW
// SIG // BBSfpxVdAF5iXYP05dJlpxtTNRnpcjBcBgNVHSAEVTBT
// SIG // MFEGDCsGAQQBgjdMg30BATBBMD8GCCsGAQUFBwIBFjNo
// SIG // dHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL0Rv
// SIG // Y3MvUmVwb3NpdG9yeS5odG0wEwYDVR0lBAwwCgYIKwYB
// SIG // BQUHAwgwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEw
// SIG // CwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYD
// SIG // VR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186aGMQwVgYD
// SIG // VR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3Nv
// SIG // ZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljUm9vQ2Vy
// SIG // QXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsGAQUFBwEBBE4w
// SIG // TDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3Nv
// SIG // ZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXRfMjAx
// SIG // MC0wNi0yMy5jcnQwDQYJKoZIhvcNAQELBQADggIBAJ1V
// SIG // ffwqreEsH2cBMSRb4Z5yS/ypb+pcFLY+TkdkeLEGk5c9
// SIG // MTO1OdfCcTY/2mRsfNB1OW27DzHkwo/7bNGhlBgi7ulm
// SIG // ZzpTTd2YurYeeNg2LpypglYAA7AFvonoaeC6Ce5732pv
// SIG // vinLbtg/SHUB2RjebYIM9W0jVOR4U3UkV7ndn/OOPcbz
// SIG // aN9l9qRWqveVtihVJ9AkvUCgvxm2EhIRXT0n4ECWOKz3
// SIG // +SmJw7wXsFSFQrP8DJ6LGYnn8AtqgcKBGUIZUnWKNsId
// SIG // w2FzLixre24/LAl4FOmRsqlb30mjdAy87JGA0j3mSj5m
// SIG // O0+7hvoyGtmW9I/2kQH2zsZ0/fZMcm8Qq3UwxTSwethQ
// SIG // /gpY3UA8x1RtnWN0SCyxTkctwRQEcb9k+SS+c23Kjgm9
// SIG // swFXSVRk2XPXfx5bRAGOWhmRaw2fpCjcZxkoJLo4S5pu
// SIG // +yFUa2pFEUep8beuyOiJXk+d0tBMdrVXVAmxaQFEfnyh
// SIG // YWxz/gq77EFmPWn9y8FBSX5+k77L+DvktxW/tM4+pTFR
// SIG // hLy/AsGConsXHRWJjXD+57XQKBqJC4822rpM+Zv/Cuk0
// SIG // +CQ1ZyvgDbjmjJnW4SLq8CdCPSWU5nR0W2rRnj7tfqAx
// SIG // M328y+l7vzhwRNGQ8cirOoo6CGJ/2XBjU02N7oJtpQUQ
// SIG // wXEGahC0HVUzWLOhcGbyoYIDUDCCAjgCAQEwgfmhgdGk
// SIG // gc4wgcsxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
// SIG // aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
// SIG // ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsT
// SIG // HE1pY3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMxJzAl
// SIG // BgNVBAsTHm5TaGllbGQgVFNTIEVTTjozMzAzLTA1RTAt
// SIG // RDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3Rh
// SIG // bXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAC2xIGWZ8
// SIG // mB1ydQxm+Xxo6ZV6bbmggYMwgYCkfjB8MQswCQYDVQQG
// SIG // EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
// SIG // BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
// SIG // cnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGlt
// SIG // ZS1TdGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0BAQsFAAIF
// SIG // AO42G2UwIhgPMjAyNjA4MjQwMTIyNDVaGA8yMDI2MDgy
// SIG // NTAxMjI0NVowdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA
// SIG // 7jYbZQIBADAKAgEAAgIbPgIB/zAHAgEAAgITDjAKAgUA
// SIG // 7jds5QIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEE
// SIG // AYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0G
// SIG // CSqGSIb3DQEBCwUAA4IBAQBkI0TD4Jqkdw2dmsAJJ63l
// SIG // c45UM8FKM77maU48QHczTi6Ayq5q/+lhIG0W9kDAZNDz
// SIG // Jz5wcwRXbo89UOoru5cf8ImvgG4KMuDieaUhzbaKvNBX
// SIG // Z2SABRHLXJEJ+UKjUrchIHVPo0rUzXfNaR2xftzBP80L
// SIG // n6wRGvMhrVuLrR3RsVQDsuuI0V7kXwIpePm2R3QoiaLd
// SIG // QFwRHFOF6E7ksT4aFGaT52VgOlICaJB/kJhOIc/G08IY
// SIG // fxSm93WWak8UXg2qQ9LYj9r4rcEo7j9+nWXGR7KuAb9g
// SIG // HUh96dcybJhz8yKlbyw9iLaoQWJWiKAyfPBoxPOkuQen
// SIG // C46tYUx5Uz79MYIEDTCCBAkCAQEwgZMwfDELMAkGA1UE
// SIG // BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
// SIG // BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
// SIG // b3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRp
// SIG // bWUtU3RhbXAgUENBIDIwMTACEzMAAAIhM8A1+9IPIaQA
// SIG // AQAAAiEwDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3
// SIG // DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQx
// SIG // IgQgnd3ZVR7mGnI6FiyHJUlrKn5DR/eQfBxXmTIq1lof
// SIG // 7UQwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCAA
// SIG // 7yEHnxVVGuAScvCGcsDAL5hkinVFahJsvQPvjwo9RDCB
// SIG // mDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
// SIG // YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
// SIG // VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNV
// SIG // BAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
// SIG // AhMzAAACITPANfvSDyGkAAEAAAIhMCIEIBsu43Mb05km
// SIG // wvueSWwzNk96E/T17HT32Kp43l7tcgBQMA0GCSqGSIb3
// SIG // DQEBCwUABIICALjwC1qjn26lLxiyonY2Md1uHJCs9FRc
// SIG // 8DADSJkF9I9OYu6Z6L+OfKAbSEQypT6hnSaJqjcG0K5U
// SIG // Och6lItAiBld7qiTff8bfiFy7sd7zwntvTRYmskn5XjY
// SIG // nu1aqdRL5P131OC6AK+/mAZ549NiOGvS6+1Jjm7dLryn
// SIG // yKn912PV+aI/sy0dRZtTWnoj2/AJEDgPfP4AirH160SA
// SIG // 5JNfQHh9g3M4WrN/BhZhvohUsFLdVCwun76lOs3PD8dp
// SIG // esPiBavkLwlnTC2uB29sG5psqtuvPIjdql3eOHkq00uc
// SIG // 9oQ4c6Rk4BRn4PJdKqTYzljw09/tDk+Sfx4DMIlkqOjp
// SIG // swfuFna/0uCaa+wiUk36vG64EiCxf8j7R9YjJKBXfGRc
// SIG // o1YGFoTPba6t/Bb5+thwWdk5KGg+TnMqrXMlwa5hWs/i
// SIG // d/T+3g9lERnrUDnHITT1yzQVFYllLI9Vd6ih3DVAKNPB
// SIG // /kR8wkDXt7H2aW+crGQJwolUg3fwlJFedU20hGSiHXxc
// SIG // O4WZFBsQ8pRcdTvTi9saKB8bXffMMyhRflcSOiMTwozG
// SIG // CREADbOinSKwLZsrgv6B3vgf8hza4G739MJwiW5djrW7
// SIG // afxbuV3Ey0Fn/pmt0xfJeTUpmTVhMD7YJt9YALRrza2G
// SIG // dVCULlxMDm7Hl9hTfxBfYvsSI6PhQxvHqGZ2
// SIG // End signature block
