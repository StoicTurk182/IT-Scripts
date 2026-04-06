# New-GitCommit.ps1 — Automated Git Commit Assistant

Local git commit message generator for the IT-Scripts toolbox. Analyses staged changes using git output only — no external API calls, no data leaves the machine.

Repository: https://github.com/StoicTurk182/IT-Scripts

---


> # Git Commit Assistant
> # Calls New-GitCommit.ps1 from any repo directory
> # Script lives in IT-Scripts — alias works globally via $PROFILE
> # Reference: https://github.com/StoicTurk182/IT-Scripts

```powershell
function New-Commit { & "C:\Users\Administrator\OneDrive\DEV_OPS\IT-Scripts\New-GitCommit.ps1" }
Set-Alias -Name gco -Value New-Commit
```

```powershell
git add -A
gco
```

## What It Does

1. Validates you are inside a git repository with staged changes
2. Lists every staged file with its status (added, modified, deleted)
3. Infers commit type from file status codes and extensions
4. Infers scope from folder path using the repository structure map
5. Prompts for confirmation or editing of the inferred values
6. Builds a conventional commit message with a subject line and file list body
7. Commits and optionally pushes

---

## Usage

```powershell
# Stage changes first
git add -A
# or selectively
git add .\ActiveDirectory\Rename-UPN\Rename-ADUserSmart_v4.ps1

# Run the assistant
& "C:\Users\Administrator\OneDrive\DEV_OPS\IT-Scripts\New-GitCommit.ps1"
```

Add to `$PROFILE` for quick access from anywhere:

```powershell
function New-Commit { & "C:\Users\Administrator\OneDrive\DEV_OPS\IT-Scripts\New-GitCommit.ps1" }
Set-Alias -Name gcm -Value New-Commit
```

Then simply:

```powershell
git add -A
gcm
```

---

## Type Inference Logic

The script infers commit type from the git status codes and file extensions of staged files:

| Condition | Inferred Type |
|---|---|
| Any deleted file (`D`) | `chore` |
| Any new file (`A`), no modified | `feat` |
| Mix of new and modified | `feat` |
| Modified `.md` files only | `docs` |
| Modified `.psd1` files only | `chore` |
| Modified `.ps1` files | `fix` |
| Everything else | `chore` |

The inferred type is always shown before prompting — press Enter to accept or type a different value.

---

## Scope Inference Logic

Scope is determined by matching the folder name of each staged file against the `$ScopeMap` table in the script. Multiple scopes are combined when files span more than one area.

### Default Scope Map

| Folder | Scope Label |
|---|---|
| `ActiveDirectory` | `ActiveDirectory` |
| `Rename-UPN` | `ActiveDirectory` |
| `migrate_groups` | `ActiveDirectory` |
| `Clear_Prefetch` | `clear_pre` |
| `Setup` | `Setup` |
| `HWH` | `HWH` |
| `Utils` | `Utils` |
| `BACKUPS` | `Backups` |
| `Bookmarks` | `Bookmarks` |
| `Win11-AppManager` | `Win11-AppManager` |
| `modules` / `Build` | `modules` |

Root-level files (e.g. `Menu.ps1`) use the filename without extension as scope.

### Extending the Scope Map

Add new entries directly in `New-GitCommit.ps1`:

```powershell
$ScopeMap = [ordered]@{
    "ActiveDirectory"  = "ActiveDirectory"
    "Rename-UPN"       = "ActiveDirectory"
    "YourNewFolder"    = "YourScopeLabel"   # add here
    ...
}
```

---

## Output Format

Generated commit messages follow the conventional commits specification.

### Subject Line

```
<type>(<scope>): <description>
```

### Full Message with Body

```
feat(ActiveDirectory): add SamAccountName character validation

- add ActiveDirectory/Rename-UPN/Rename-ADUserSmart_v4.ps1
- update ActiveDirectory/Rename-UPN/Rename-ADUserSmart_v4.ps1
```

### Examples of Generated Messages

Single file modified:

```
fix(clear_pre): null guard on Get-FolderSizeMB for empty folders

- update Clear_Prefetch/clear_pre_v2.ps1
```

New script added:

```
feat(Setup): add hardware hash collection script

- add Setup/HWH/hwh.ps1
```

Documentation only:

```
docs(ActiveDirectory): add full comment-based help block to rename script

- update ActiveDirectory/Rename-UPN/Rename-ADUserSmart_v4.ps1
```

Multi-area change:

```
chore(ActiveDirectory, modules): rebuild module after help block update

- update ActiveDirectory/Rename-UPN/Rename-ADUserSmart_v4.ps1
- update modules/ADIdentityTools/ADIdentityTools.psm1
- update modules/ADIdentityTools/ADIdentityTools.psd1
```

---

## Interactive Flow

```
========================================
  GIT COMMIT ASSISTANT
========================================

  [NOTE] Repository: C:\...\IT-Scripts

  Staged files:
    [added   ]  ActiveDirectory/Rename-UPN/Rename-ADUserSmart_v4.ps1
    [modified]  Menu.ps1

  [COMMIT MESSAGE]
  Types: feat | fix | docs | refactor | chore | perf | test
  Inferred type: feat
  Type [Enter to accept 'feat']:

  Inferred scope: ActiveDirectory, Menu
  Scope [Enter to accept]:

  Description (imperative present tense): add v4 with input validation

  ----------------------------------------
  feat(ActiveDirectory, Menu): add v4 with input validation

  - add ActiveDirectory/Rename-UPN/Rename-ADUserSmart_v4.ps1
  - update Menu.ps1
  ----------------------------------------

  [C]ommit  [E]dit description  [A]bort: C

  [OK]   Committed: feat(ActiveDirectory, Menu): add v4 with input validation

  Push to remote now? Y/N: Y
  [OK]   Pushed.
```

---

## Adding to IT-Scripts Menu

Add an entry to `Menu.ps1` to make the commit assistant accessible from the toolbox:

```powershell
"Git Tools" = @(
    @{ Name = "New Commit"; Path = "New-GitCommit.ps1"; Description = "Generate structured commit message from staged changes" }
)
```

---

## Limitations

| Limitation | Notes |
|---|---|
| Type inference is heuristic | Accepts manual override at the prompt — always shown before asking |
| Scope map must be maintained | Add new folders to `$ScopeMap` as the repo grows |
| Renamed files (`R`) | Shown in output but treated as modified for type inference |
| Copied files (`C`) | Same as renamed |
| No multi-line body editing | Description is a single line; body is auto-generated from file list |

---

## References

- Conventional Commits: https://www.conventionalcommits.org/en/v1.0.0/
- git diff documentation: https://git-scm.com/docs/git-diff
- git status documentation: https://git-scm.com/docs/git-status
- git commit documentation: https://git-scm.com/docs/git-commit
