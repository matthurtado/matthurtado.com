# Matt Hurtado: Portfolio

A dependency-free, single-page portfolio styled as a full-screen retro game menu.

## Preview

Open `index.html` in a browser. No build step is required.

## Publish

```powershell
.\scripts\publish.ps1
```

The script commits and pushes pending changes to [matthurtado/matthurtado.com](https://github.com/matthurtado/matthurtado.com), then stages only the public website files and synchronizes them to `/public_html/` through the saved WinSCP session `matthurtado.com`. On its first run, it initializes this folder as a Git repository and configures the GitHub remote automatically.

Useful options:

```powershell
.\scripts\publish.ps1 -WebsiteOnly
.\scripts\publish.ps1 -SkipUpload
.\scripts\publish.ps1 -CommitMessage "Refresh projects"
.\scripts\publish.ps1 -RemoteDirectory "/public_html"
```

The `-WebsiteOnly` option rebuilds the setlist index and uploads the website without committing or pushing to GitHub. The older `-SkipGit` flag remains available as an alias.

## Virtual Soundscapes setlists

Export a CSV from TrackForge with the Episode, Theme, Set, Playlist Number, Title, Artist, and Album fields enabled. Import and publish it in one step:

```powershell
.\scripts\publish.ps1 -SetlistPath "D:\Radio\path\to\episode.csv"
```

You can also drop one or more CSVs into the `setlists` folder before running `scripts\publish.ps1`. The script adds or updates those episodes in `setlists/index.json`, sorts episodes newest-first, and publishes the index with the site. Previously imported episodes remain in the index even if their original CSV is later deleted. CSV files themselves are not uploaded to the public website.

The first episode is expanded automatically; older episodes start collapsed. No database or manual HTML editing is required.
