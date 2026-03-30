<#
.SYNOPSIS
    Validates .intunewin packages in a target output folder.

.DESCRIPTION
    Performs structural and metadata integrity checks on all .intunewin files
    found in the specified folder. Checks include: file presence, ZIP structure,
    required entry paths, Detection.xml parsing, SHA256 digest extraction, and
    unencrypted size consistency.

    Outputs a per-package result table and a summary pass/fail count.

.PARAMETER OutputFolder
    Path to the folder containing .intunewin files to check.
    Defaults to the current directory.

.PARAMETER ExportCsv
    Optional. If specified, exports results to a CSV file at this path.

.EXAMPLE
    .\Invoke-IntuneWinCheck.ps1

.EXAMPLE
    .\Invoke-IntuneWinCheck.ps1 -OutputFolder "C:\IntunePackaging\output\Packages"

.EXAMPLE
    .\Invoke-IntuneWinCheck.ps1 -OutputFolder ".\output\Packages" -ExportCsv ".\PackageCheckResults.csv"

.NOTES
    Author: Andrew Jones
    Version: 1.0
    Date: 2026-03-30
    References:
      Microsoft Win32 Content Prep Tool: https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool
      Intune Win32 app management: https://learn.microsoft.com/en-us/mem/intune/apps/apps-win32-app-management
#>

#Requires -Version 5.1

[CmdletBinding()]
param (
    [Parameter()]
    [string]$OutputFolder = ".",

    [Parameter()]
    [string]$ExportCsv = ""
)

Add-Type -AssemblyName System.IO.Compression.FileSystem

# ============================================================================
# CONFIGURATION
# ============================================================================

$RequiredEntries = @(
    "IntuneWinPackage/Contents/IntunePackage.intunewin",
    "IntuneWinPackage/Metadata/Detection.xml"
)

# ============================================================================
# FUNCTIONS
# ============================================================================

function Write-Header {
    param ([string]$Text)
    $line = "=" * 70
    Write-Host "`n$line" -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host "$line" -ForegroundColor Cyan
}

function Write-Check {
    param (
        [string]$Label,
        [bool]$Passed,
        [string]$Detail = ""
    )
    $status = if ($Passed) { "[PASS]" } else { "[FAIL]" }
    $color  = if ($Passed) { "Green" } else { "Red" }
    $msg    = if ($Detail) { "  $status  $Label - $Detail" } else { "  $status  $Label" }
    Write-Host $msg -ForegroundColor $color
}

function Test-IntuneWinPackage {
    param ([System.IO.FileInfo]$File)

    $result = [PSCustomObject]@{
        FileName             = $File.Name
        FileSizeMB           = [math]::Round($File.Length / 1MB, 2)
        LastModified         = $File.LastWriteTime
        ZipReadable          = $false
        RequiredEntriesFound = $false
        DetectionXmlReadable = $false
        SetupFile            = ""
        ToolVersion          = ""
        UnencryptedSizeBytes = ""
        PayloadSizeBytes     = ""
        SizesConsistent      = $false
        FileDigestAlgorithm  = ""
        FileDigest           = ""
        EncryptionKeyPresent = $false
        MacKeyPresent        = $false
        IVPresent            = $false
        OverallStatus        = "FAIL"
        Notes                = ""
    }

    Write-Header "Checking: $($File.Name)"
    Write-Host "  Path:          $($File.FullName)" -ForegroundColor Gray
    Write-Host "  Size:          $($result.FileSizeMB) MB" -ForegroundColor Gray
    Write-Host "  Last Modified: $($result.LastModified)" -ForegroundColor Gray
    Write-Host ""

    # --- Check 1: ZIP readable ---
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($File.FullName)
        $result.ZipReadable = $true
        Write-Check "ZIP structure readable" $true
    }
    catch {
        Write-Check "ZIP structure readable" $false "File may be corrupt or incomplete"
        $result.Notes = "Could not open as ZIP archive"
        $zip = $null
        return $result
    }

    # --- Check 2: Required entries ---
    $entries = $zip.Entries | Select-Object -ExpandProperty FullName
    $allPresent = $true
    foreach ($required in $RequiredEntries) {
        if ($entries -contains $required) {
            Write-Check "Entry found: $required" $true
        }
        else {
            Write-Check "Entry found: $required" $false "Missing from archive"
            $allPresent = $false
        }
    }
    $result.RequiredEntriesFound = $allPresent

    # --- Check 3: Payload size ---
    $payloadEntry = $zip.Entries | Where-Object { $_.FullName -eq "IntuneWinPackage/Contents/IntunePackage.intunewin" }
    if ($payloadEntry) {
        $result.PayloadSizeBytes = $payloadEntry.Length
        $compressed = $payloadEntry.CompressedLength
        $notCompressed = ($payloadEntry.Length -eq $payloadEntry.CompressedLength)
        Write-Check "Payload not additionally compressed (expected for encrypted data)" $notCompressed `
            "Length=$($payloadEntry.Length) CompressedLength=$compressed"
    }

    # --- Check 4: Detection.xml readable and parsed ---
    $xmlEntry = $zip.Entries | Where-Object { $_.FullName -eq "IntuneWinPackage/Metadata/Detection.xml" }
    if ($xmlEntry) {
        try {
            $reader  = New-Object System.IO.StreamReader($xmlEntry.Open())
            $xmlRaw  = $reader.ReadToEnd()
            $reader.Close()

            [xml]$xml = $xmlRaw
            $appInfo  = $xml.ApplicationInfo

            $result.DetectionXmlReadable = $true
            $result.SetupFile            = $appInfo.SetupFile
            $result.ToolVersion          = $appInfo.ToolVersion
            $result.UnencryptedSizeBytes = $appInfo.UnencryptedContentSize
            $result.FileDigest           = $appInfo.EncryptionInfo.FileDigest
            $result.FileDigestAlgorithm  = $appInfo.EncryptionInfo.FileDigestAlgorithm
            $result.EncryptionKeyPresent = (-not [string]::IsNullOrEmpty($appInfo.EncryptionInfo.EncryptionKey))
            $result.MacKeyPresent        = (-not [string]::IsNullOrEmpty($appInfo.EncryptionInfo.MacKey))
            $result.IVPresent            = (-not [string]::IsNullOrEmpty($appInfo.EncryptionInfo.InitializationVector))

            Write-Check "Detection.xml readable" $true
            Write-Check "SetupFile populated"    (-not [string]::IsNullOrEmpty($result.SetupFile))    $result.SetupFile
            Write-Check "ToolVersion populated"  (-not [string]::IsNullOrEmpty($result.ToolVersion))  $result.ToolVersion
            Write-Check "FileDigest present ($($result.FileDigestAlgorithm))" `
                        (-not [string]::IsNullOrEmpty($result.FileDigest)) $result.FileDigest
            Write-Check "EncryptionKey present"  $result.EncryptionKeyPresent
            Write-Check "MacKey present"         $result.MacKeyPresent
            Write-Check "IV present"             $result.IVPresent

            # --- Check 5: Size consistency ---
            # UnencryptedContentSize in XML should be within a few bytes of payload entry Length
            # (AES-256-CBC pads to 16-byte boundary, so payload can be up to 15 bytes larger)
            if ($result.PayloadSizeBytes -and $result.UnencryptedSizeBytes) {
                $declared = [long]$result.UnencryptedSizeBytes
                $payload  = [long]$result.PayloadSizeBytes
                $delta    = $payload - $declared
                $consistent = ($delta -ge 0 -and $delta -le 16)
                $result.SizesConsistent = $consistent
                Write-Check "Size consistency (UnencryptedContentSize vs payload)" $consistent `
                    "Declared=$declared Payload=$payload Delta=$delta bytes"
            }
        }
        catch {
            Write-Check "Detection.xml readable" $false "XML parse error: $_"
            $result.Notes += " Detection.xml parse failed."
        }
    }

    $zip.Dispose()

    # --- Overall status ---
    $passed = $result.ZipReadable -and
              $result.RequiredEntriesFound -and
              $result.DetectionXmlReadable -and
              $result.EncryptionKeyPresent -and
              $result.MacKeyPresent -and
              $result.IVPresent -and
              (-not [string]::IsNullOrEmpty($result.FileDigest)) -and
              $result.SizesConsistent

    $result.OverallStatus = if ($passed) { "PASS" } else { "FAIL" }

    $statusColor = if ($passed) { "Green" } else { "Red" }
    Write-Host ""
    Write-Host "  Overall: $($result.OverallStatus)" -ForegroundColor $statusColor

    return $result
}

# ============================================================================
# MAIN
# ============================================================================

Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host "  IntuneWin Package Integrity Check" -ForegroundColor Cyan
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  Target folder: $OutputFolder" -ForegroundColor Gray

$resolvedFolder = Resolve-Path $OutputFolder -ErrorAction SilentlyContinue
if (-not $resolvedFolder) {
    Write-Host "`n[ERROR] Folder not found: $OutputFolder" -ForegroundColor Red
    exit 1
}

$packages = Get-ChildItem -Path $resolvedFolder -Filter "*.intunewin" -ErrorAction SilentlyContinue
if ($packages.Count -eq 0) {
    Write-Host "`n[WARNING] No .intunewin files found in: $resolvedFolder" -ForegroundColor Yellow
    exit 0
}

Write-Host "  Packages found: $($packages.Count)" -ForegroundColor Gray

$allResults = @()
foreach ($pkg in $packages) {
    $allResults += Test-IntuneWinPackage -File $pkg
}

# ============================================================================
# SUMMARY TABLE
# ============================================================================

Write-Header "Summary"

$allResults | Format-Table -AutoSize -Property `
    FileName,
    FileSizeMB,
    SetupFile,
    ToolVersion,
    FileDigestAlgorithm,
    SizesConsistent,
    OverallStatus

$passCount = ($allResults | Where-Object { $_.OverallStatus -eq "PASS" }).Count
$failCount = ($allResults | Where-Object { $_.OverallStatus -eq "FAIL" }).Count

Write-Host "  Passed: $passCount" -ForegroundColor Green
Write-Host "  Failed: $failCount" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })
Write-Host ""

# ============================================================================
# CSV EXPORT
# ============================================================================

if ($ExportCsv) {
    try {
        $allResults | Export-Csv -Path $ExportCsv -NoTypeInformation -Encoding UTF8
        Write-Host "  Results exported to: $ExportCsv" -ForegroundColor Cyan
    }
    catch {
        Write-Host "  [WARNING] Could not export CSV: $_" -ForegroundColor Yellow
    }
}

# Exit with non-zero code if any package failed, useful for CI/CD pipelines
if ($failCount -gt 0) { exit 1 } else { exit 0 }
