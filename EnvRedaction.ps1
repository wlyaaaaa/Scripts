$script:CodexEnvRedactionMarker = '<REDACTED:restore-from-credential-backup-or-rotate>'

function Test-CodexEnvSecretName {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Name
    )

    return $Name -match '(?i)(KEY|TOKEN|SECRET|PASSWORD|PASS|CREDENTIAL|AUTH)'
}

function Test-CodexEnvSecretValue {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    $patterns = @(
        'gh[pousr]_[A-Za-z0-9_]{20,}',
        'github_pat_[A-Za-z0-9_]{20,}',
        'sk-[A-Za-z0-9_-]{20,}',
        'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',
        'AKIA[0-9A-Z]{16}',
        'ASIA[0-9A-Z]{16}',
        'AIza[0-9A-Za-z_-]{20,}',
        'xox[baprs]-[A-Za-z0-9-]{20,}',
        'hf_[A-Za-z0-9]{20,}',
        'glpat-[A-Za-z0-9_-]{20,}',
        'npm_[A-Za-z0-9]{20,}',
        '(?:sk|pk)_(?:live|test)_[A-Za-z0-9]{16,}',
        'ya29\.[A-Za-z0-9_-]{20,}'
    )

    foreach ($pattern in $patterns) {
        if ($Value -match $pattern) {
            return $true
        }
    }

    return $false
}

function Test-CodexEnvSensitiveEntry {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    return (Test-CodexEnvSecretName -Name $Name) -or (Test-CodexEnvSecretValue -Value $Value)
}

function ConvertTo-CodexRedactedEnvLines {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [string[]]$Lines
    )

    $redacted = New-Object 'System.Collections.Generic.List[string]'
    $currentName = $null
    $suppressFormatListContinuation = $false

    foreach ($line in $Lines) {
        if ($line -match '^(?<prefix>\s*Name\s*:\s*)(?<name>.*)$') {
            $currentName = $Matches['name'].Trim()
            $suppressFormatListContinuation = $false
            $redacted.Add($line)
            continue
        }

        if ($line -match '^(?<prefix>\s*Value\s*:\s*)(?<value>.*)$' -and $null -ne $currentName) {
            $value = $Matches['value']
            if (Test-CodexEnvSensitiveEntry -Name $currentName -Value $value) {
                $redacted.Add($Matches['prefix'] + $script:CodexEnvRedactionMarker)
                $suppressFormatListContinuation = $true
            } else {
                $redacted.Add($line)
                $suppressFormatListContinuation = $false
            }
            continue
        }

        if ($null -ne $currentName -and $suppressFormatListContinuation) {
            if ([string]::IsNullOrWhiteSpace($line)) {
                $currentName = $null
                $suppressFormatListContinuation = $false
                $redacted.Add($line)
            }
            continue
        }

        if ($line -match '^(?<name>[^:=\s][^:=]*?)\s*(?<separator>[:=])\s*(?<value>.*)$' -and
            $Matches['name'].Trim() -notin @('Name', 'Value')) {
            $name = $Matches['name'].Trim()
            $separator = $Matches['separator']
            $value = $Matches['value']
            if (Test-CodexEnvSensitiveEntry -Name $name -Value $value) {
                $redacted.Add($name + $separator + ' ' + $script:CodexEnvRedactionMarker)
            } else {
                $redacted.Add($line)
            }
            continue
        }

        if ([string]::IsNullOrWhiteSpace($line)) {
            $currentName = $null
            $suppressFormatListContinuation = $false
        }
        $redacted.Add($line)
    }

    return $redacted.ToArray()
}

function Get-CodexEnvRedactionSummary {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [string[]]$Lines
    )

    $entryCount = 0
    $sensitiveCount = 0
    $currentName = $null

    foreach ($line in $Lines) {
        if ($line -match '^\s*Name\s*:\s*(?<name>.*)$') {
            $currentName = $Matches['name'].Trim()
            $entryCount++
            continue
        }

        if ($line -match '^\s*Value\s*:\s*(?<value>.*)$' -and $null -ne $currentName) {
            if (Test-CodexEnvSensitiveEntry -Name $currentName -Value $Matches['value']) {
                $sensitiveCount++
            }
            continue
        }

        if ($line -match '^(?<name>[^:=\s][^:=]*?)\s*[:=]\s*(?<value>.*)$' -and
            $Matches['name'].Trim() -notin @('Name', 'Value')) {
            $entryCount++
            if (Test-CodexEnvSensitiveEntry -Name $Matches['name'].Trim() -Value $Matches['value']) {
                $sensitiveCount++
            }
            continue
        }

        if ([string]::IsNullOrWhiteSpace($line)) {
            $currentName = $null
        }
    }

    [pscustomobject]@{
        EntryCount     = $entryCount
        SensitiveCount = $sensitiveCount
    }
}

function Export-CodexRedactedEnvFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    $lines = Get-Content -LiteralPath $InputPath -Encoding utf8
    $redacted = ConvertTo-CodexRedactedEnvLines -Lines $lines
    $redacted | Set-Content -LiteralPath $OutputPath -Encoding utf8
    return Get-CodexEnvRedactionSummary -Lines $lines
}
