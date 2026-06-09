$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot "windows-silly-tavern-deploy.bat"
$text = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8

function Assert-Contains {
    param(
        [string] $Needle,
        [string] $Message
    )

    if (-not $text.Contains($Needle)) {
        throw $Message
    }
}

function New-UnicodeText {
    param([int[]] $CodePoints)

    return -join ($CodePoints | ForEach-Object { [char] $_ })
}

Assert-Contains 'merge --ff-only FETCH_HEAD' 'The update path must keep the conservative ff-only merge.'
Assert-Contains ('SillyTavern ' + (New-UnicodeText 26410,26356,26032,65292,20173,22312,26087,29256,26412)) 'The ff-only failure warning must say the project was not updated.'
Assert-Contains ((New-UnicodeText 24403,21069) + ' commit:') 'The warning must print the current commit.'
Assert-Contains ((New-UnicodeText 30446,26631) + ' FETCH_HEAD:') 'The warning must print the target FETCH_HEAD.'
Assert-Contains ('Git ' + (New-UnicodeText 29366,24577,25688,35201) + ':') 'The warning must print a git status summary.'
Assert-Contains ((New-UnicodeText 22788,29702,24314,35758) + ':') 'The warning must print user-actionable recovery guidance.'
Assert-Contains 'ReportGitUpdateSkipped' 'The ff-only failure path must call a dedicated warning reporter.'

$reportLabel = [regex]::Match(
    $text,
    '(?ms)^:ReportGitUpdateSkipped\r?\n(?<body>.*?)(?=^:[A-Za-z0-9_]+\s*$)'
)
if (-not $reportLabel.Success) {
    throw 'Missing ReportGitUpdateSkipped label body.'
}

$reportBody = $reportLabel.Groups['body'].Value
if (-not $reportBody.Contains('if not defined STATUS_FILE')) {
    throw 'ReportGitUpdateSkipped must define a fallback STATUS_FILE.'
}
if (-not $reportBody.Contains('sillytavern_git_status_%RANDOM%.tmp')) {
    throw 'ReportGitUpdateSkipped fallback STATUS_FILE must use a temp status path.'
}
if (-not $reportBody.Contains('UPDATE_SKIP_STATUS_FILE_CREATED')) {
    throw 'ReportGitUpdateSkipped must track whether it created the fallback status file.'
}
if (-not $reportBody.Contains('del /f /q "%STATUS_FILE%"')) {
    throw 'ReportGitUpdateSkipped must clean up fallback STATUS_FILE.'
}

$executableReset = [regex]::Matches(
    $text,
    '(?m)^\s*git\s+-C\s+"%PROJECT_DIR%"\s+checkout\s+-B\s+release\s+FETCH_HEAD\b'
)
if ($executableReset.Count -ne 0) {
    throw 'The script must not execute checkout -B release FETCH_HEAD without explicit user confirmation.'
}

$labelSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$labelMatches = [regex]::Matches($text, '(?m)^:([A-Za-z0-9_]+)\s*$')
foreach ($match in $labelMatches) {
    [void] $labelSet.Add($match.Groups[1].Value)
}

$references = New-Object System.Collections.ArrayList
$callMatches = [regex]::Matches($text, '(?i)\bcall\s+:([A-Za-z0-9_]+)')
foreach ($match in $callMatches) {
    [void] $references.Add($match.Groups[1].Value)
}

$gotoMatches = [regex]::Matches($text, '(?i)\bgoto\s+:?([A-Za-z0-9_]+)')
foreach ($match in $gotoMatches) {
    [void] $references.Add($match.Groups[1].Value)
}

$missing = @()
foreach ($reference in $references) {
    if (-not $labelSet.Contains($reference)) {
        $missing += $reference
    }
}
$missing = $missing | Sort-Object -Unique
if ($missing) {
    throw "Missing batch labels: $($missing -join ', ')"
}

$lineNumber = 0
foreach ($line in ($text -split "`r?`n")) {
    $lineNumber++
    $quoteCount = ([regex]::Matches($line, '"')).Count
    if (($quoteCount % 2) -ne 0) {
        throw "Odd quote count on line ${lineNumber}: $line"
    }
}

Write-Host "windows_update_semantics.ps1 passed"
