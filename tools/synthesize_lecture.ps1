<#
.SYNOPSIS
  Synthesize the speaker notes from Lecture_10min_AlgorithmsOfCities.md into a WAV
  using the Windows 11 Natural Voice "Microsoft Andrew (Natural)".

.NOTES
  Requires:
    - Windows PowerShell 5.1 (uses WinRT interop)
    - Microsoft Andrew (Natural) installed via Settings > Time & Language > Speech.

.USAGE
  powershell -ExecutionPolicy Bypass -File .\tools\synthesize_lecture.ps1
#>

param(
    [string]$LecturePath = (Join-Path $PSScriptRoot '..\Lecture_10min_AlgorithmsOfCities.md'),
    [string]$OutputPath  = (Join-Path $PSScriptRoot '..\Lecture_speech.wav'),
    [string]$VoiceMatch  = 'Andrew',
    [int]$RatePercent    = -8,        # slightly slower for academic delivery
    [int]$BreakMs        = 1200       # pause between slides
)

$ErrorActionPreference = 'Stop'

# --- Load WinRT plumbing -----------------------------------------------------
Add-Type -AssemblyName System.Runtime.WindowsRuntime

[void][Windows.Media.SpeechSynthesis.SpeechSynthesizer, Windows.Media.SpeechSynthesis, ContentType=WindowsRuntime]
[void][Windows.Storage.Streams.DataReader,           Windows.Storage.Streams,         ContentType=WindowsRuntime]
[void][Windows.Storage.Streams.IRandomAccessStream,  Windows.Storage.Streams,         ContentType=WindowsRuntime]

function Await {
    param($WinRtTask, [type]$ResultType)
    $asTaskGeneric = [System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object {
            $_.Name -eq 'AsTask' -and
            $_.IsGenericMethod -and
            $_.GetGenericArguments().Count -eq 1 -and
            $_.GetParameters().Count -eq 1
        } | Select-Object -First 1
    $netTask = $asTaskGeneric.MakeGenericMethod($ResultType).Invoke($null, @($WinRtTask))
    $netTask.Wait(-1) | Out-Null
    $netTask.Result
}

# --- Read & extract speaker notes -------------------------------------------
if (-not (Test-Path $LecturePath)) { throw "Lecture file not found: $LecturePath" }
$md = Get-Content -Path $LecturePath -Raw

# Match a blockquote starting with "> **Speaker note ...**:" and continuing through subsequent ">" lines
$pattern = '(?ms)^>\s*\*\*Speaker note[^*]*\*\*\s*:?\s*(.+?)(?=\r?\n(?!>)|\Z)'
$matches = [regex]::Matches($md, $pattern)
if ($matches.Count -eq 0) { throw "No speaker notes found in $LecturePath" }

function Clean-NoteText([string]$t) {
    # strip continuation blockquote markers
    $t = $t -replace '(?m)^>\s?', ''
    # strip bold/italic markdown
    $t = $t -replace '\*\*', ''
    $t = $t -replace '(?<!\*)\*(?!\*)', ''
    # backticks
    $t = $t -replace '`', ''
    # inline math: $X$ -> X (simply drop the $ delimiters)
    $t = $t -replace '\$', ''
    # any LaTeX command like \sigma -> sigma
    $t = $t -replace '\\([A-Za-z]+)', '$1'
    # collapse whitespace (em/en dashes pass through as natural pauses)
    $t = $t -replace '\s+', ' '
    return $t.Trim()
}

$notes = $matches | ForEach-Object { Clean-NoteText $_.Groups[1].Value }
Write-Host "Extracted $($notes.Count) speaker notes."

# --- Pick voice --------------------------------------------------------------
$voice = [Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices |
    Where-Object { $_.DisplayName -match $VoiceMatch } |
    Select-Object -First 1

if (-not $voice) {
    Write-Host "Voice '$VoiceMatch' not found. Installed voices:"
    [Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices | ForEach-Object {
        Write-Host "  - $($_.DisplayName)"
    }
    throw "Install Microsoft Andrew (Natural) via Settings > Time & Language > Speech > Manage voices."
}
Write-Host "Voice: $($voice.DisplayName)"

# --- Build SSML --------------------------------------------------------------
$rateAttr = if ($RatePercent -ge 0) { "+$RatePercent%" } else { "$RatePercent%" }
$sb = [System.Text.StringBuilder]::new()
[void]$sb.Append("<speak version='1.0' xml:lang='en-US' xmlns='http://www.w3.org/2001/10/synthesis'>")
[void]$sb.Append("<voice name='$($voice.DisplayName)'>")
[void]$sb.Append("<prosody rate='$rateAttr'>")
$first = $true
foreach ($n in $notes) {
    if (-not $first) { [void]$sb.Append("<break time='${BreakMs}ms'/>") }
    [void]$sb.Append([System.Security.SecurityElement]::Escape($n))
    $first = $false
}
[void]$sb.Append('</prosody></voice></speak>')
$ssml = $sb.ToString()

# --- Synthesize --------------------------------------------------------------
$synth = [Windows.Media.SpeechSynthesis.SpeechSynthesizer]::new()
$synth.Voice = $voice

Write-Host "Synthesizing $([math]::Round($ssml.Length / 1024, 1)) KB of SSML..."
$stream  = Await $synth.SynthesizeSsmlToStreamAsync($ssml) ([Windows.Media.SpeechSynthesis.SpeechSynthesisStream])
$size    = [int]$stream.Size
$reader  = [Windows.Storage.Streams.DataReader]::new($stream.GetInputStreamAt(0))
$loaded  = Await $reader.LoadAsync([uint32]$size) ([uint32])

$bytes = New-Object 'byte[]' $loaded
$reader.ReadBytes($bytes)

[System.IO.File]::WriteAllBytes($OutputPath, $bytes)
$mb = [math]::Round((Get-Item $OutputPath).Length / 1MB, 2)
Write-Host "Wrote $OutputPath ($mb MB)"
