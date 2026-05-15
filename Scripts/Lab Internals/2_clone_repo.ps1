# =============================================================================
# Clone Repo
# -----------------------------------------------------------------------------
# Runs FIRST in the Skillable Lab Lifecycle (After VM Build) stage, BEFORE
# deployment_build2026.ps1, replace_tokens.ps1, and post_deploy.ps1.
#
# This script:
#   1. Verifies git is installed (installs via winget as a last resort).
#   2. Clones https://github.com/jjfrost/build-2026-lab into C:\Lab.
#   3. Retries the clone with exponential backoff if it fails.
#   4. Verifies the clone succeeded by checking for the .git folder and at
#      least one expected file (readme.md).
#   5. Logs every step to C:\Lab\Logs\clone_repo_<timestamp>.log so failures
#      are no longer silent.
# =============================================================================

$ErrorActionPreference = "Stop"

# ---------- Logging ----------------------------------------------------------
# Logs live OUTSIDE of C:\Lab so the clone target can be wiped freely without
# losing diagnostic output.
$logDir = 'C:\Logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = Join-Path $logDir ("clone_repo_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))

function Write-Log {
    param([string]$Message)
    $line = "{0} {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $Message
    $line | Out-File -FilePath $logFile -Append -Encoding UTF8
    Write-Host $line
}

Write-Log "==== Clone Repo start ===="

# ---------- Wipe target for a clean clone -----------------------------------
$targetDir = "C:\Lab"
if (Test-Path $targetDir) {
    Write-Log "Existing $targetDir found. Removing for a clean clone..."
    try {
        Remove-Item -LiteralPath $targetDir -Recurse -Force -ErrorAction Stop
        Write-Log "Removed $targetDir."
    } catch {
        Write-Log "First-pass remove failed: $($_.Exception.Message). Clearing attributes and retrying..."
        Get-ChildItem -LiteralPath $targetDir -Recurse -Force -ErrorAction SilentlyContinue |
            ForEach-Object { try { $_.Attributes = 'Normal' } catch { } }
        Remove-Item -LiteralPath $targetDir -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $targetDir) {
            throw "Could not remove $targetDir prior to clone."
        }
        Write-Log "Removed $targetDir on second pass."
    }
} else {
    Write-Log "$targetDir does not exist. Nothing to wipe."
}

# ================== Configuration ============================================
$repoUrl      = "https://github.com/jjfrost/build-2026-lab"
$tempRoot     = "C:\LabTemp"
$maxAttempts  = 5
$initialDelay = 5     # seconds; doubles each retry
$cloneTimeout = 600   # seconds; per-attempt safety net

# A file we expect to exist in the repo root after a successful clone.
# Adjust if the repo's canonical filename casing differs.
$verifyFile = "LICENSE"

Write-Log "Repo URL:    $repoUrl"
Write-Log "Target dir:  $targetDir"
Write-Log "Max attempts: $maxAttempts"

# ================== Ensure git is available ==================================
function Resolve-GitCommand {
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCmd) {
        Write-Log "git found at: $($gitCmd.Source)"
        return $gitCmd.Source
    }

    Write-Log "git not found on PATH. Attempting install via winget..."
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "git is not installed and winget is not available. Cannot install git automatically."
    }

    try {
        & winget install --id Git.Git -e --silent --accept-package-agreements --accept-source-agreements `
            *>&1 | ForEach-Object { Write-Log "winget: $_" }
    } catch {
        Write-Log "winget install threw: $($_.Exception.Message)"
    }

    # Refresh PATH for current process
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")

    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCmd) {
        # Fall back to common install locations
        $candidates = @(
            "C:\Program Files\Git\cmd\git.exe",
            "C:\Program Files (x86)\Git\cmd\git.exe"
        )
        foreach ($c in $candidates) {
            if (Test-Path $c) { $gitCmd = @{ Source = $c }; break }
        }
    }

    if (-not $gitCmd) { throw "git is still not available after install attempt." }

    Write-Log "git resolved to: $($gitCmd.Source)"
    return $gitCmd.Source
}

$gitExe = Resolve-GitCommand
Write-Log "git version: $((& $gitExe --version) 2>&1)"

# ================== Helpers ==================================================
function Test-CloneSuccess {
    param([string]$Path)

    if (-not (Test-Path (Join-Path $Path '.git'))) {
        Write-Log "Verification: .git folder NOT found in $Path"
        return $false
    }
    if (-not (Test-Path (Join-Path $Path $verifyFile))) {
        Write-Log "Verification: expected file '$verifyFile' NOT found in $Path"
        return $false
    }

    # Confirm git itself considers the working tree valid.
    Push-Location $Path
    try {
        $rev = & $gitExe rev-parse HEAD 2>&1
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($rev)) {
            Write-Log "Verification: 'git rev-parse HEAD' failed: $rev"
            return $false
        }
        Write-Log "Verification: HEAD = $rev"
    } finally {
        Pop-Location
    }

    return $true
}

function Invoke-GitClone {
    param([string]$Url, [string]$Destination, [int]$TimeoutSec)

    if (Test-Path $Destination) {
        Write-Log "Cleaning existing temp clone path: $Destination"
        Remove-Item -LiteralPath $Destination -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null

    # Prevent any interactive credential prompts from hanging the clone.
    $env:GIT_TERMINAL_PROMPT = '0'
    $env:GCM_INTERACTIVE     = 'never'

    Write-Log "Starting: git clone $Url $Destination"

    # Invoke git directly (not via Start-Process) so $LASTEXITCODE is reliable.
    # Merge stderr into stdout and capture everything as an array of lines.
    #
    # NOTE: We locally disable ErrorActionPreference=Stop and
    # $PSNativeCommandUseErrorActionPreference because git writes its normal
    # progress output ("Cloning into...", "Receiving objects...") to stderr,
    # which PowerShell 7+ otherwise converts into terminating errors.
    $prevEAP  = $ErrorActionPreference
    $prevPNCP = $null
    if (Test-Path Variable:PSNativeCommandUseErrorActionPreference) {
        $prevPNCP = $PSNativeCommandUseErrorActionPreference
        $PSNativeCommandUseErrorActionPreference = $false
    }
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $gitExe clone --progress $Url $Destination 2>&1
        $exit   = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prevEAP
        if ($null -ne $prevPNCP) {
            $PSNativeCommandUseErrorActionPreference = $prevPNCP
        }
    }

    foreach ($line in $output) {
        Write-Log "git: $line"
    }
    Write-Log "git clone exit code: $exit"
    return ($exit -eq 0)
}

function Move-CloneIntoTarget {
    param([string]$Source, [string]$Target)

    # Ensure target exists, preserving the Logs folder we created earlier.
    if (-not (Test-Path $Target)) {
        New-Item -ItemType Directory -Path $Target -Force | Out-Null
    }

    Write-Log "Moving contents of $Source into $Target ..."
    # /E recurse, /MOVE delete source, /NFL/NDL/NJH/NJS quieter, /R:2 /W:2 small retry
    $rcArgs = @($Source, $Target, '/E', '/MOVE', '/R:2', '/W:2', '/NFL', '/NDL', '/NJH', '/NJS')
    $rcOut = & robocopy @rcArgs 2>&1
    $rcExit = $LASTEXITCODE
    foreach ($l in $rcOut) { Write-Log "robocopy: $l" }
    # robocopy exit codes 0-7 are success; 8+ are failures
    if ($rcExit -ge 8) {
        throw "robocopy failed moving clone into target (exit $rcExit)."
    }
    Write-Log "robocopy exit code: $rcExit (success)"
}

# ================== Clone with retries =======================================
if (-not (Test-Path $tempRoot)) { New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null }

$success = $false
$delay   = $initialDelay

for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
    Write-Log "----- Attempt $attempt of $maxAttempts -----"

    $tempClone = Join-Path $tempRoot ("clone_{0}" -f ([guid]::NewGuid().ToString('N').Substring(0,8)))

    $cloneOk = $false
    try {
        $cloneOk = Invoke-GitClone -Url $repoUrl -Destination $tempClone -TimeoutSec $cloneTimeout
    } catch {
        Write-Log "Invoke-GitClone threw: $($_.Exception.Message)"
        $cloneOk = $false
    }

    if ($cloneOk -and (Test-CloneSuccess -Path $tempClone)) {
        try {
            Move-CloneIntoTarget -Source $tempClone -Target $targetDir
        } catch {
            Write-Log "Move failed: $($_.Exception.Message)"
            Remove-Item -LiteralPath $tempClone -Recurse -Force -ErrorAction SilentlyContinue
            continue
        }

        if (Test-CloneSuccess -Path $targetDir) {
            Write-Log "Clone + move succeeded on attempt $attempt."
            $success = $true
            break
        } else {
            Write-Log "Post-move verification failed."
        }
    } else {
        Write-Log "Clone attempt $attempt failed verification."
        Remove-Item -LiteralPath $tempClone -Recurse -Force -ErrorAction SilentlyContinue
    }

    if ($attempt -lt $maxAttempts) {
        Write-Log "Sleeping ${delay}s before retry..."
        Start-Sleep -Seconds $delay
        $delay = [Math]::Min($delay * 2, 60)
    }
}

# ================== Cleanup temp root ========================================
try {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
} catch { }

if (-not $success) {
    Write-Log "==== Clone Repo FAILED after $maxAttempts attempts ===="
    throw "Failed to clone $repoUrl into $targetDir after $maxAttempts attempts. See $logFile."
}

Write-Log "Repo cloned successfully to: $targetDir"
Write-Log "==== Clone Repo complete ===="
