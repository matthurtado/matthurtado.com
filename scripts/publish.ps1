[CmdletBinding()]
param(
    [string]$CommitMessage = "Update portfolio website",
    [string]$RemoteDirectory = "/public_html/",
    [string[]]$SetlistPath,
    [Alias("SkipGit")]
    [switch]$WebsiteOnly,
    [switch]$SkipUpload
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
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

function Build-SetlistIndex {
    $setlistDirectory = Join-Path $ProjectRoot "setlists"
    $indexPath = Join-Path $setlistDirectory "index.json"
    New-Item -ItemType Directory -Path $setlistDirectory -Force | Out-Null

    $episodeArchive = [ordered]@{}
    if (Test-Path -LiteralPath $indexPath) {
        $existingData = Get-Content -Raw -LiteralPath $indexPath | ConvertFrom-Json
        if ($null -ne $existingData.value -and $null -eq $existingData.episode) {
            # Migrate indexes produced by older versions that serialized a
            # PowerShell collection wrapper instead of the underlying array.
            $existingEpisodes = @($existingData.value)
        } else {
            $existingEpisodes = @($existingData)
        }
        foreach ($existingEpisode in $existingEpisodes) {
            if ($null -ne $existingEpisode -and -not [string]::IsNullOrWhiteSpace([string]$existingEpisode.episode)) {
                $episodeArchive[[string]$existingEpisode.episode] = $existingEpisode
            }
        }
    }

    foreach ($csvFile in Get-ChildItem -LiteralPath $setlistDirectory -Filter "*.csv" -File) {
        $rows = @(Import-Csv -LiteralPath $csvFile.FullName -Encoding UTF8)
        if ($rows.Count -eq 0) { continue }

        $first = $rows[0]
        $episode = ([string]$first.Episode -replace '^\s*Episode\s*', '').Trim()
        $theme = [string]$first.Theme
        if ([string]::IsNullOrWhiteSpace($episode)) {
            $episode = [System.IO.Path]::GetFileNameWithoutExtension($csvFile.Name)
        }

        $tracks = foreach ($row in $rows) {
            $title = [string]$row.Title
            if ([string]::IsNullOrWhiteSpace($title)) { continue }

            [ordered]@{
                set = [string]$row.Set
                number = [string]$row.'Playlist Number'
                title = $title
                artist = [string]$row.Artist
                album = [string]$row.Album
            }
        }

        $episodeArchive[$episode] = [ordered]@{
            episode = $episode
            theme = $theme
            tracks = @($tracks)
        }
    }

    $archivedEpisodes = @($episodeArchive.GetEnumerator() | ForEach-Object { $_.Value })
    $sortedEpisodes = @($archivedEpisodes | Sort-Object -Property @{ Expression = { if ([string]$_.episode -match '\d+') { [int]$Matches[0] } else { 0 } }; Descending = $true }, @{ Expression = { [string]$_.episode }; Descending = $true })
    $json = ConvertTo-Json -InputObject ([object[]]$sortedEpisodes) -Depth 6
    [System.IO.File]::WriteAllText($indexPath, $json, [System.Text.UTF8Encoding]::new($false))

    $validationData = Get-Content -Raw -LiteralPath $indexPath | ConvertFrom-Json
    $validatedEpisodes = @($validationData)
    if ($validatedEpisodes.Count -ne $sortedEpisodes.Count) {
        throw "Setlist index validation failed: expected $($sortedEpisodes.Count) episodes, found $($validatedEpisodes.Count)."
    }
    if (@($validatedEpisodes | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.episode) }).Count -gt 0) {
        throw "Setlist index validation failed: an episode has no episode number."
    }

    $indexBytes = [System.IO.File]::ReadAllBytes($indexPath)
    if ($indexBytes.Length -ge 3 -and $indexBytes[0] -eq 0xEF -and $indexBytes[1] -eq 0xBB -and $indexBytes[2] -eq 0xBF) {
        throw "Setlist index validation failed: index.json contains a UTF-8 byte-order mark."
    }
}

if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot "index.html"))) {
    throw "index.html is missing from $ProjectRoot."
}

$setlistDirectory = Join-Path $ProjectRoot "setlists"
New-Item -ItemType Directory -Path $setlistDirectory -Force | Out-Null
foreach ($sourcePath in @($SetlistPath)) {
    if ([string]::IsNullOrWhiteSpace($sourcePath)) { continue }
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Setlist CSV was not found: $sourcePath"
    }
    if ([System.IO.Path]::GetExtension($sourcePath) -ne ".csv") {
        throw "Setlist imports must be CSV files: $sourcePath"
    }
    Copy-Item -LiteralPath $sourcePath -Destination $setlistDirectory -Force
}

Build-SetlistIndex

if (-not $WebsiteOnly) {
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

        $websitePaths = @(
            "index.html",
            "oow_pic.jpg",
            "favicon.svg",
            "README.md",
            ".gitignore",
            "scripts/publish.ps1",
            "setlists/index.json"
        )
        git add -- $websitePaths
        if ($LASTEXITCODE -ne 0) { throw "Git staging failed with exit code $LASTEXITCODE." }

        $setlistCsvFiles = @(Get-ChildItem -LiteralPath $setlistDirectory -Filter "*.csv" -File)
        foreach ($setlistCsvFile in $setlistCsvFiles) {
            git add -- $setlistCsvFile.FullName
            if ($LASTEXITCODE -ne 0) { throw "Git staging failed for $($setlistCsvFile.Name)." }
        }

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
$PublishDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("matthurtado-publish-" + [guid]::NewGuid().ToString("N"))
$PublishFiles = @("index.html", "oow_pic.jpg", "favicon.svg")

New-Item -ItemType Directory -Path $PublishDirectory | Out-Null
foreach ($file in $PublishFiles) {
    $source = Join-Path $ProjectRoot $file
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Publish file is missing: $source"
    }

    Copy-Item -LiteralPath $source -Destination $PublishDirectory
}

$publishedSetlistDirectory = Join-Path $PublishDirectory "setlists"
New-Item -ItemType Directory -Path $publishedSetlistDirectory | Out-Null
Copy-Item -LiteralPath (Join-Path $ProjectRoot "setlists\index.json") -Destination $publishedSetlistDirectory

$openCommand = "open $WinScpSession"
$synchronizeCommand = "synchronize remote $PublishDirectory $RemoteDirectory"

Write-Host "Uploading with the saved WinSCP session '$WinScpSession'..."
try {
    & $WinScpPath /command `
        "option batch abort" `
        "option confirm off" `
        $openCommand `
        $synchronizeCommand `
        "exit"

    if ($LASTEXITCODE -ne 0) {
        throw "WinSCP failed with exit code $LASTEXITCODE."
    }
} finally {
    if (Test-Path -LiteralPath $PublishDirectory) {
        Remove-Item -LiteralPath $PublishDirectory -Recurse -Force
    }
}

Write-Host "Website published successfully."
