#Requires -Version 5.1

<#
.SYNOPSIS
    Converts any PowerShell script to a compiled EXE, a PowerShell module, or both.

.DESCRIPTION
    Universal build tool for PowerShell scripts. Parses the source script using the
    PowerShell AST to extract the param block and build valid module output.

    Supports:
      - EXE compilation via PS2EXE (installs automatically if missing)
      - Module generation: .psm1 wrapping the script logic + .psd1 manifest
      - Optional auto-install of the generated module to the current user's PSModulePath
      - Interactive menu when no parameters are supplied

    Works with any .ps1 script. Scripts using Read-Host for interactive input will
    function correctly in EXE mode only when console mode is enabled (default).

.PARAMETER ScriptPath
    Full or relative path to the source .ps1 file.

.PARAMETER OutputType
    Conversion target. Accepts: EXE, Module, Both.
    If omitted, an interactive menu is shown.

.PARAMETER OutputDir
    Directory where output files are written.
    Defaults to a Build\ subfolder in the same directory as the source script.

.EXAMPLE
    .\Convert-PSScript.ps1 -ScriptPath ".\Rename-ADUserSmart_v4.ps1" -OutputType EXE

.EXAMPLE
    .\Convert-PSScript.ps1 -ScriptPath ".\Rename-ADUserSmart_v4.ps1" -OutputType Module

.EXAMPLE
    .\Convert-PSScript.ps1 -ScriptPath ".\Rename-ADUserSmart_v4.ps1" -OutputType Both

.EXAMPLE
    .\Convert-PSScript.ps1
    Runs fully interactively — prompts for script path, conversion type, and all options.

.NOTES
    Author:      Andrew Jones
    Version:     1.0
    Requires:    PowerShell 5.1 or later
    EXE output:  Requires PS2EXE module (installed automatically if not present)
    References:
      PS2EXE:                https://www.powershellgallery.com/packages/PS2EXE
      about_Modules:         https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_modules
      Approved Verbs:        https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands
      New-ModuleManifest:    https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/new-modulemanifest
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]$ScriptPath,

    [Parameter(Mandatory=$false)]
    [ValidateSet("EXE", "Module", "Both")]
    [string]$OutputType,

    [Parameter(Mandatory=$false)]
    [string]$OutputDir
)

# ============================================================
# HELPERS
# ============================================================

function Write-Header {
    param([string]$Text)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  $Text"                                   -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
}

function Write-Step  { param([string]$T); Write-Host "  >> $T" -ForegroundColor Yellow }
function Write-OK    { param([string]$T); Write-Host "  [OK]   $T" -ForegroundColor Green  }
function Write-Fail  { param([string]$T); Write-Host "  [FAIL] $T" -ForegroundColor Red    }
function Write-Note  { param([string]$T); Write-Host "  [NOTE] $T" -ForegroundColor Gray   }

function Read-Default {
    # Displays a prompt with a default value in brackets.
    # Returns the user's input, or the default if Enter is pressed.
    param([string]$Prompt, [string]$Default = "")
    $display = if ($Default) { "$Prompt [$Default]" } else { $Prompt }
    $input   = (Read-Host "  $display").Trim()
    if ([string]::IsNullOrWhiteSpace($input)) { return $Default }
    return $input
}

# ============================================================
# SCRIPT SELECTION AND VALIDATION
# ============================================================

Write-Header "POWERSHELL SCRIPT CONVERTER"

if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
    $ScriptPath = (Read-Host "  Path to .ps1 script").Trim().Trim('"')
}

if (-not (Test-Path $ScriptPath)) {
    Write-Fail "File not found: $ScriptPath"
    exit 1
}

if ([System.IO.Path]::GetExtension($ScriptPath) -ne ".ps1") {
    Write-Fail "File must be a .ps1 script. Received: $ScriptPath"
    exit 1
}

$ScriptPath    = (Resolve-Path $ScriptPath).Path
$ScriptDir     = Split-Path $ScriptPath -Parent
$ScriptBase    = [System.IO.Path]::GetFileNameWithoutExtension($ScriptPath)
$ScriptContent = Get-Content $ScriptPath -Raw -Encoding UTF8

Write-OK "Script loaded: $ScriptPath"
Write-Note "Lines: $((Get-Content $ScriptPath).Count)"

# ============================================================
# OUTPUT DIRECTORY
# ============================================================

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $ScriptDir "Build"
}
if (!(Test-Path $OutputDir)) {
    New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
}
Write-Note "Output directory: $OutputDir"

# ============================================================
# CONVERSION TYPE SELECTION
# ============================================================

if ([string]::IsNullOrWhiteSpace($OutputType)) {
    Write-Host ""
    Write-Host "  Select conversion target:" -ForegroundColor Magenta
    Write-Host "    [1] EXE     - Compiled executable (PS2EXE). Good for restricted machines,"
    Write-Host "                  bypasses execution policy, single distributable file."
    Write-Host "    [2] Module  - PowerShell module (.psm1 + .psd1). Good for IT team reuse,"
    Write-Host "                  adds tab completion, Get-Help, and version management."
    Write-Host "    [3] Both    - Produce EXE and Module."
    Write-Host ""
    $choice = (Read-Host "  Choice (1/2/3)").Trim()
    $OutputType = switch ($choice) {
        "1"     { "EXE"    }
        "2"     { "Module" }
        "3"     { "Both"   }
        default { Write-Fail "Invalid choice. Enter 1, 2, or 3."; exit 1 }
    }
}

Write-Note "Conversion target: $OutputType"

# ============================================================
# AST PARSE — shared by both paths
# ============================================================

Write-Step "Parsing script AST..."

$ParseErrors = $null
$ParseTokens = $null
$Ast = [System.Management.Automation.Language.Parser]::ParseFile(
           $ScriptPath, [ref]$ParseTokens, [ref]$ParseErrors)

if ($ParseErrors.Count -gt 0) {
    Write-Host "`n  [WARNING] Script has parse errors. Output may not function correctly:" -ForegroundColor Yellow
    foreach ($e in $ParseErrors) {
        Write-Host "    Line $($e.Extent.StartLineNumber): $($e.Message)" -ForegroundColor Yellow
    }
}

# Extract #Requires statements from token stream
$RequiresLines = $ParseTokens |
    Where-Object { $_.Kind -eq 'Comment' -and $_.Text -match '^#Requires' } |
    ForEach-Object { $_.Text }

# Extract param block text (preserves original formatting).
# Strip any existing [CmdletBinding(...)] — the module wrapper adds its own.
# Leaving both causes: ParserError: Unexpected attribute 'CmdletBinding' on import.
$ParamBlockText = if ($Ast.ParamBlock) {
    $Ast.ParamBlock.Extent.Text -replace '(?is)\[CmdletBinding[^]]*\]\s*', ''
} else { "" }

# Determine the line number after which the script body begins
# (after #Requires, [CmdletBinding()], and param block)
$BodyStartLine = 1
if ($Ast.ParamBlock) {
    $BodyStartLine = $Ast.ParamBlock.Extent.EndLineNumber + 1
}

$AllLines   = Get-Content $ScriptPath
$BodyLines  = if ($BodyStartLine -le $AllLines.Count) {
    $AllLines[($BodyStartLine - 1)..($AllLines.Count - 1)]
} else { @() }
# Strip #Requires and script-level [CmdletBinding()] from body.
# #Requires is invalid inside a function — already emitted at module level.
# [CmdletBinding()] at script level duplicates the wrapper's own declaration,
# causing: ParserError: Unexpected attribute 'CmdletBinding'.
$BodyText = ($BodyLines | Where-Object { $_ -notmatch '^\s*#Requires' }) -join "`n"
$BodyText = $BodyText -replace '(?is)\[CmdletBinding[^]]*\]\s*', ''

Write-OK "AST parse complete."

# ============================================================
# FUNCTION: Build-Exe
# ============================================================

function Build-Exe {
    Write-Header "EXE COMPILATION"

    # --- PS2EXE check ---
    Write-Step "Checking PS2EXE module..."
    if (-not (Get-Module -ListAvailable PS2EXE -ErrorAction SilentlyContinue)) {
        Write-Host "  PS2EXE not found. Installing from PSGallery..." -ForegroundColor Yellow
        Write-Note "Reference: https://www.powershellgallery.com/packages/PS2EXE"
        try {
            Install-Module -Name PS2EXE -Scope CurrentUser -Force -ErrorAction Stop
            Write-OK "PS2EXE installed."
        } catch {
            Write-Fail "PS2EXE installation failed: $($_.Exception.Message)"
            Write-Note "Install manually: Install-Module -Name PS2EXE -Scope CurrentUser -Force"
            return
        }
    } else {
        Write-OK "PS2EXE available."
    }
    Import-Module PS2EXE -Force -ErrorAction SilentlyContinue

    # --- Metadata ---
    Write-Host "`n  [METADATA]" -ForegroundColor Magenta
    Write-Note "Press Enter to accept the value shown in brackets."
    $Title       = Read-Default -Prompt "Title"       -Default $ScriptBase
    $Description = Read-Default -Prompt "Description" -Default "Compiled PowerShell script"
    $Company     = Read-Default -Prompt "Company"     -Default "Andrew J IT Labs"
    $Version     = Read-Default -Prompt "Version"     -Default "1.0.0.0"

    if ($Version -notmatch '^\d+\.\d+\.\d+\.\d+$') {
        Write-Host "  [WARNING] Version must be in X.X.X.X format. Defaulting to 1.0.0.0" -ForegroundColor Yellow
        $Version = "1.0.0.0"
    }

    # --- Options ---
    Write-Host "`n  [OPTIONS]" -ForegroundColor Magenta

    $AdminChoice  = Read-Default -Prompt "Require administrator (UAC prompt on launch)? Y/N" -Default "Y"
    $x64Choice    = Read-Default -Prompt "Force 64-bit PowerShell host? Y/N" -Default "Y"
    $ConsoleChoice = Read-Default -Prompt "Suppress console window (GUI-only mode)? Y/N" -Default "N"

    $RequireAdmin = $AdminChoice.ToUpper()  -ne "N"
    $x64Option    = $x64Choice.ToUpper()    -ne "N"
    $NoConsole    = $ConsoleChoice.ToUpper() -eq "Y"

    if ($NoConsole) {
        Write-Host ""
        Write-Host "  [WARNING] NoConsole suppresses the terminal window." -ForegroundColor Yellow
        Write-Host "            Scripts using Read-Host will silently fail in this mode." -ForegroundColor Yellow
        Write-Host "            Only use NoConsole for scripts with GUI (WinForms/WPF) output." -ForegroundColor Yellow
    }

    if ($x64Option) {
        Write-Note "64-bit host selected. ActiveDirectory and other 64-bit-only modules will load correctly."
    }

    # --- Output path ---
    $OutputExe = Join-Path $OutputDir "$ScriptBase.exe"

    # --- Compile ---
    Write-Host ""
    Write-Step "Compiling $ScriptBase.exe..."

    $Ps2ExeArgs = @{
        InputFile   = $ScriptPath
        OutputFile  = $OutputExe
        Title       = $Title
        Description = $Description
        Company     = $Company
        FileVersion = $Version
        NoConsole   = $NoConsole
    }
    if ($RequireAdmin) { $Ps2ExeArgs['RequireAdmin'] = $true }
    if ($x64Option)    { $Ps2ExeArgs['x64']          = $true }

    try {
        Invoke-PS2EXE @Ps2ExeArgs -ErrorAction Stop
        Write-OK "EXE created: $OutputExe"
        Write-Note "Test: & '$OutputExe'"
    } catch {
        Write-Fail "Compilation failed: $($_.Exception.Message)"
        Write-Note "If the error mentions MTA/STA threading, add -MTA or -STA to the Invoke-PS2EXE call."
    }
}

# ============================================================
# FUNCTION: Build-Module
# ============================================================

function Build-Module {
    Write-Header "MODULE CONVERSION"

    Write-Note "The script body will be wrapped in a PowerShell function and exported as a module."
    Write-Note "AST extraction preserves the original param block and #Requires directives."

    # --- Function name ---
    Write-Host "`n  [FUNCTION NAME]" -ForegroundColor Magenta
    Write-Host "  Use an approved PowerShell verb (Get, Set, New, Remove, Invoke, Start, etc.)"
    Write-Note "Reference: https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands"
    $FunctionName = Read-Default -Prompt "Function name (Verb-Noun)" -Default $ScriptBase

    # Approved verb check — PowerShell will import the module but warn on every Import-Module
    # call if the function name uses a non-standard verb.
    # Reference: https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands
    $ApprovedVerbs = (Get-Verb).Verb
    $UsedVerb      = ($FunctionName -split '-')[0]
    if ($UsedVerb -and $ApprovedVerbs -notcontains $UsedVerb) {
        Write-Host ""
        Write-Host "  [WARNING] '$UsedVerb' is not an approved PowerShell verb." -ForegroundColor Yellow
        Write-Host "            Import-Module will warn every time this module is loaded." -ForegroundColor Yellow
        Write-Host "            Common approved alternatives: Invoke, Set, Update, Rename, Convert" -ForegroundColor Yellow
        $Override = (Read-Default -Prompt "Continue with '$FunctionName' anyway? Y/N" -Default "N").ToUpper()
        if ($Override -ne "Y") {
            $FunctionName = Read-Default -Prompt "Function name (Verb-Noun)" -Default "Invoke-$($ScriptBase -replace '^[^-]+-','')"
        }
    }

    # --- Module metadata ---
    Write-Host "`n  [MODULE METADATA]" -ForegroundColor Magenta
    $ModuleName    = Read-Default -Prompt "Module name"    -Default $ScriptBase
    $ModuleVersion = Read-Default -Prompt "Module version" -Default "1.0.0"
    $Author        = Read-Default -Prompt "Author"         -Default "Andrew Jones"
    $Description   = Read-Default -Prompt "Description"    -Default "$ModuleName PowerShell Module"
    $PSVersion     = Read-Default -Prompt "Min PowerShell version (e.g. 5.1 or 7.0)" -Default "5.1"
    # New-ModuleManifest requires at least Major.Minor format. Normalise bare integers.
    if ($PSVersion -match '^\d+$') { $PSVersion = "$PSVersion.0" }

    # --- Detect required modules from #Requires ---
    $RequiredModules = @()
    foreach ($line in $RequiresLines) {
        if ($line -match '-Modules?\s+(.+)') {
            $RequiredModules += ($Matches[1] -split ',') | ForEach-Object { $_.Trim() }
        }
    }
    if ($RequiredModules.Count -gt 0) {
        Write-Note "Detected required modules from #Requires: $($RequiredModules -join ', ')"
    }

    # --- Extract help block from source script (AST) ---
    # If the source has comment-based help (<# ... #>), reuse it directly in the
    # generated function rather than overwriting it with the generic stub.
    # This means enriching help in the source .ps1 is all that is needed —
    # rebuilding the module via Convert-PSScript will carry the changes forward.
    # Reference: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_comment_based_help
    $SourceHelpBlock = ""
    $HelpAst = $Ast.Find({ $args[0] -is [System.Management.Automation.Language.ScriptBlockAst] }, $false)
    if ($Ast.GetHelpContent()) {
        # Source has parseable help — extract the raw comment block text from tokens
        $HelpToken = $ParseTokens | Where-Object {
            $_.Kind -eq 'Comment' -and $_.Text -match '(?s)<#.*\.SYNOPSIS'
        } | Select-Object -First 1
        if ($HelpToken) {
            $SourceHelpBlock = $HelpToken.Text
            Write-Note "Help block detected in source script — reusing in generated function."
            Write-Note "To update help, edit the source .ps1 and rebuild."
        }
    }

    # If no source help found, fall back to generated stub
    $HelpBlock = if ($SourceHelpBlock) {
        $SourceHelpBlock
    } else {
        @"
    <#
    .SYNOPSIS
        $Description
    .NOTES
        Author:    $Author
        Version:   $ModuleVersion
        Generated: $(Get-Date -Format 'yyyy-MM-dd')
        Source:    $(Split-Path $ScriptPath -Leaf)

        To add full help, edit the source .ps1 comment block and rebuild.
        Reference: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_comment_based_help
    #>
"@
    }

    # --- Build .psm1 content ---
    # CmdletBinding: SupportsShouldProcess adds -WhatIf and -Confirm support.
    # [CmdletBinding()] must be immediately followed by param() — if the source
    # has no param block, emit an empty one to satisfy the parser.
    $Psm1Header = @"
# $ModuleName.psm1
# Generated by Convert-PSScript on $(Get-Date -Format 'yyyy-MM-dd HH:mm')
# Source: $(Split-Path $ScriptPath -Leaf)
# Reference: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_modules
#
# To update help metadata: edit the .SYNOPSIS/.DESCRIPTION/.NOTES block in
# the source .ps1, then rebuild with Convert-PSScript.ps1.
# To update after build without rebuilding: edit this .psm1 directly,
# then reinstall: Copy-Item '<BuildDir>' '$env:USERPROFILE\Documents\PowerShell\Modules\' -Recurse -Force

"@

    # Re-emit #Requires at module level (they apply to the module as a whole)
    $RequiresBlock = ($RequiresLines -join "`n")

    # [CmdletBinding()] requires a param() block immediately after it.
    # If the source script has no param block, emit an empty one so the
    # function is valid. Without this, PowerShell throws:
    # ParserError: Unexpected attribute 'CmdletBinding'.
    $FinalParamBlock = if ([string]::IsNullOrWhiteSpace($ParamBlockText)) { "param()" } else { $ParamBlockText }

    $Psm1Function = @"

function $FunctionName {
$HelpBlock
    [CmdletBinding(SupportsShouldProcess)]
    $FinalParamBlock

$BodyText
}

Export-ModuleMember -Function '$FunctionName'
"@

    $Psm1Content = $Psm1Header + $RequiresBlock + $Psm1Function

    # --- Output paths ---
    $ModuleOutputDir = Join-Path $OutputDir $ModuleName
    if (!(Test-Path $ModuleOutputDir)) {
        New-Item -Path $ModuleOutputDir -ItemType Directory -Force | Out-Null
    }
    $Psm1Path = Join-Path $ModuleOutputDir "$ModuleName.psm1"
    $Psd1Path = Join-Path $ModuleOutputDir "$ModuleName.psd1"

    # --- Write .psm1 ---
    Write-Step "Writing $ModuleName.psm1..."
    Set-Content -Path $Psm1Path -Value $Psm1Content -Encoding UTF8
    Write-OK "Created: $Psm1Path"

    # --- Write .psd1 ---
    Write-Step "Writing $ModuleName.psd1..."
    try {
        $ManifestArgs = @{
            Path               = $Psd1Path
            ModuleVersion      = $ModuleVersion
            Author             = $Author
            Description        = $Description
            RootModule         = "$ModuleName.psm1"
            FunctionsToExport  = @($FunctionName)
            PowerShellVersion  = $PSVersion
        }
        if ($RequiredModules.Count -gt 0) {
            $ManifestArgs['RequiredModules'] = $RequiredModules
        }
        New-ModuleManifest @ManifestArgs -ErrorAction Stop
        Write-OK "Created: $Psd1Path"
    } catch {
        Write-Fail "Manifest creation failed: $($_.Exception.Message)"
    }

    # --- Optional install ---
    Write-Host ""
    Write-Host "  [INSTALL]" -ForegroundColor Magenta
    Write-Host "  PSModulePath (current user): $env:USERPROFILE\Documents\PowerShell\Modules"
    $Install = (Read-Default -Prompt "Install module for current user? Y/N" -Default "N").ToUpper()

    if ($Install -eq "Y") {
        $UserModulePath = "$env:USERPROFILE\Documents\PowerShell\Modules\$ModuleName"
        Write-Step "Installing to $UserModulePath..."
        try {
            Copy-Item -Path $ModuleOutputDir -Destination $UserModulePath -Recurse -Force -ErrorAction Stop
            Write-OK "Module installed."
            Write-Host ""
            Write-Host "  Import with:  Import-Module $ModuleName" -ForegroundColor Cyan
            Write-Host "  Run with:     $FunctionName" -ForegroundColor Cyan
            Write-Host "  Help:         Get-Help $FunctionName -Full" -ForegroundColor Cyan
        } catch {
            Write-Fail "Install failed: $($_.Exception.Message)"
            Write-Note "Install manually by copying '$ModuleOutputDir' to your PSModulePath."
        }
    } else {
        Write-Host ""
        Write-Host "  To install manually:" -ForegroundColor Gray
        Write-Host "    Copy-Item '$ModuleOutputDir' '$env:USERPROFILE\Documents\PowerShell\Modules\' -Recurse" -ForegroundColor Gray
        Write-Host "    Import-Module $ModuleName" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Note "Module output: $ModuleOutputDir"
}

# ============================================================
# MAIN
# ============================================================

switch ($OutputType) {
    "EXE"    { Build-Exe }
    "Module" { Build-Module }
    "Both"   {
        Build-Exe
        Build-Module
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  COMPLETE" -ForegroundColor Cyan
Write-Host "  Output: $OutputDir" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
