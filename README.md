# Matt Hurtado — Portfolio

A dependency-free, single-page portfolio styled as a full-screen retro game menu.

## Preview

Open `index.html` in a browser. No build step is required.

## Publish

```powershell
.\publish.ps1
```

The script commits and pushes pending changes to [matthurtado/matthurtado.com](https://github.com/matthurtado/matthurtado.com), then stages only the public website files and synchronizes them to `/public_html/` through the saved WinSCP session `matthurtado.com`. On its first run, it initializes this folder as a Git repository and configures the GitHub remote automatically.

Useful options:

```powershell
.\publish.ps1 -SkipGit
.\publish.ps1 -SkipUpload
.\publish.ps1 -CommitMessage "Refresh projects"
.\publish.ps1 -RemoteDirectory "/public_html"
```

The `-SkipGit` option uploads without committing or pushing to GitHub.
