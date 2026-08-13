[CmdletBinding()]
param(
    [string]$CommitMessage = "Update portfolio website",
    [string]$RemoteDirectory = "/",
    [switch]$SkipGit,
    [switch]$SkipUpload
)

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot
$WinScpSession = "matthurtado.com"
$GitRemoteUrl = "https://github.com/matthurtado/matthurtado.com.git"

function Find-WinScp {
    $command = Get-Command "WinSCP.com" -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $candidates = @(
        "${env:ProgramFiles(x86)}\WinSCP\WinSCP.com",
        "$env:ProgramFiles\WinSCP\WinSCP.com"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }

    throw "WinSCP.com could not be found. Install WinSCP or add it to PATH."
}

if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot "index.html"))) {
    throw "index.html is missing from $ProjectRoot."
}

if (-not $SkipGit) {
    Push-Location $ProjectRoot
    try {
        if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot ".git"))) {
            Write-Host "Initializing the Git repository..."
            git init -b main
            if ($LASTEXITCODE -ne 0) { throw "Git initialization failed with exit code $LASTEXITCODE." }
        }

        $remotes = @(git remote)
        if ($remotes -notcontains "origin") {
            git remote add origin $GitRemoteUrl
            if ($LASTEXITCODE -ne 0) { throw "Could not add the GitHub remote." }
        } else {
            $originUrl = git remote get-url origin
            if ($originUrl -ne $GitRemoteUrl) {
                throw "The existing 'origin' remote points to '$originUrl' instead of '$GitRemoteUrl'."
            }
        }

        git add --all
        if ($LASTEXITCODE -ne 0) { throw "Git staging failed with exit code $LASTEXITCODE." }

        git diff --cached --quiet
        if ($LASTEXITCODE -eq 0) {
            Write-Host "No Git changes to commit."
        } else {
            git commit -m $CommitMessage
            if ($LASTEXITCODE -ne 0) { throw "Git commit failed with exit code $LASTEXITCODE." }
        }

        $currentBranch = git branch --show-current
        $gitConfig = @(git config --list)
        $hasUpstream = $gitConfig -match "^branch\.$([regex]::Escape($currentBranch))\.remote="
        if ($hasUpstream) {
            git push
        } else {
            git push --set-upstream origin HEAD
        }
        if ($LASTEXITCODE -ne 0) { throw "Git push failed with exit code $LASTEXITCODE." }
    } finally {
        Pop-Location
    }
}

if ($SkipUpload) {
    Write-Host "Upload skipped."
    exit 0
}

$WinScpPath = Find-WinScp
$openCommand = "open $WinScpSession"
$synchronizeCommand = "synchronize remote -filemask=`"| .git/; README.md; publish.ps1`" `"$ProjectRoot`" `"$RemoteDirectory`""

Write-Host "Uploading with the saved WinSCP session '$WinScpSession'..."
& $WinScpPath /command `
    "option batch abort" `
    "option confirm off" `
    $openCommand `
    $synchronizeCommand `
    "exit"

if ($LASTEXITCODE -ne 0) {
    throw "WinSCP failed with exit code $LASTEXITCODE."
}

Write-Host "Website published successfully."
