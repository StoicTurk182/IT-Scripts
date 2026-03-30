# IntuneWin Package Integrity Check SOP

Standard operating procedure for validating `.intunewin` packages prior to upload to Microsoft Intune. Covers manual checks, automated script usage, and expected outputs.

## Purpose

Before uploading a Win32 app package to Intune, the `.intunewin` file should be validated to confirm:

- The archive structure is intact and readable
- The encrypted payload and metadata are both present
- The Detection.xml manifest is well-formed and fully populated
- The declared unencrypted size is consistent with the payload
- Encryption keys, MAC, and IV are present (required for Intune decryption on the endpoint)

A corrupt or incomplete package will fail silently at upload or produce a confusing deployment failure on endpoints. This check catches packaging errors before they reach production.

## Background

A `.intunewin` file is a ZIP archive produced by the Microsoft Win32 Content Prep Tool. The archive has a fixed internal structure:

```
IntuneWinPackage/
├── Contents/
│   └── IntunePackage.intunewin    (AES-256-CBC encrypted installer payload)
└── Metadata/
    └── Detection.xml              (package manifest: setup file name, size, SHA256 digest, encryption metadata)
```

The encrypted payload uses AES-256-CBC. Because encrypted data is not compressible, the ZIP compression ratio on the payload entry will always be 1:1 (CompressedLength equals Length). Any deviation indicates a packaging error.

The Detection.xml contains the SHA256 digest of the original source installer (`FileDigest`, base64 encoded). This is used by the Intune service to verify the payload after decryption on the endpoint.

References:
- Win32 Content Prep Tool: https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool
- Intune Win32 app management: https://learn.microsoft.com/en-us/mem/intune/apps/apps-win32-app-management
- Win32 app detection rules: https://learn.microsoft.com/en-us/mem/intune/apps/apps-win32-prepare#step-4-configure-app-detection-rules

## Manual Check Procedure

### Step 1: Verify File Exists and Has Expected Size

```powershell
$pkg = ".\output\Packages\AppName Version.intunewin"
Get-Item $pkg | Select-Object Name, Length, LastWriteTime
```

There is no universal expected size. Compare against the source installer — the `.intunewin` should be within a few percent of the original installer size (encryption does not significantly change size).

### Step 2: Verify ZIP Structure

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($pkg)
$zip.Entries | Select-Object FullName, Length, CompressedLength
$zip.Dispose()
```

Expected output:

| FullName | Length | CompressedLength |
|---|---|---|
| IntuneWinPackage/Contents/IntunePackage.intunewin | (file size) | (same as Length) |
| IntuneWinPackage/Metadata/Detection.xml | ~800-1000 | ~800-1000 |

If `IntunePackage.intunewin` CompressedLength does not equal Length, the payload may have been re-compressed or corrupted after packaging. Repackage from the original source installer.

### Step 3: Read and Validate Detection.xml

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($pkg)
$entry = $zip.Entries | Where-Object { $_.FullName -eq "IntuneWinPackage/Metadata/Detection.xml" }
$reader = New-Object System.IO.StreamReader($entry.Open())
$reader.ReadToEnd()
$reader.Close()
$zip.Dispose()
```

### Step 4: Interpret Detection.xml Output

A valid Detection.xml looks like:

```xml
<ApplicationInfo xmlns:xsd="..." xmlns:xsi="..." ToolVersion="1.8.7.0">
  <Name>AppName Setup.exe</Name>
  <UnencryptedContentSize>76209759</UnencryptedContentSize>
  <FileName>IntunePackage.intunewin</FileName>
  <SetupFile>AppName Setup.exe</SetupFile>
  <EncryptionInfo>
    <EncryptionKey>...</EncryptionKey>
    <MacKey>...</MacKey>
    <InitializationVector>...</InitializationVector>
    <Mac>...</Mac>
    <ProfileIdentifier>ProfileVersion1</ProfileIdentifier>
    <FileDigest>...</FileDigest>
    <FileDigestAlgorithm>SHA256</FileDigestAlgorithm>
  </EncryptionInfo>
</ApplicationInfo>
```

Check each field against this table:

| Field | Expected | Fail Condition |
|---|---|---|
| `SetupFile` | Matches source installer filename exactly | Empty or wrong filename |
| `ToolVersion` | Any non-empty version string | Empty |
| `UnencryptedContentSize` | Numeric, close to source installer size | Empty or zero |
| `EncryptionKey` | Non-empty base64 string | Empty |
| `MacKey` | Non-empty base64 string | Empty |
| `InitializationVector` | Non-empty base64 string | Empty |
| `Mac` | Non-empty base64 string | Empty |
| `FileDigest` | Non-empty base64 string | Empty |
| `FileDigestAlgorithm` | `SHA256` | Any other value or empty |

### Step 5: Size Consistency Check

Compare `UnencryptedContentSize` from Detection.xml against the payload entry `Length` from Step 2.

AES-256-CBC pads to a 16-byte boundary. The payload `Length` should equal `UnencryptedContentSize` rounded up to the nearest 16 bytes. A delta of 0 to 15 bytes is acceptable. A larger delta or a negative delta indicates a mismatch between the manifest and the payload.

```powershell
$declared = 76209759  # UnencryptedContentSize from Detection.xml
$payload  = 76209808  # Length from ZIP entry
$delta    = $payload - $declared
Write-Host "Delta: $delta bytes (acceptable range: 0-15)"
```

## Automated Check: Invoke-IntuneWinCheck.ps1

The script `Invoke-IntuneWinCheck.ps1` performs all manual checks above against every `.intunewin` file in a target folder and outputs a structured pass/fail result.

### Location

Place the script in your IntunePackaging working directory or a shared scripts location. Recommended:

```
IntunePackaging-Simple/
├── source/
├── output/
│   └── Packages/
└── Invoke-IntuneWinCheck.ps1
```

### Usage

Check all packages in the default output folder:

```powershell
.\Invoke-IntuneWinCheck.ps1 -OutputFolder ".\output\Packages"
```

Check a specific folder and export results to CSV:

```powershell
.\Invoke-IntuneWinCheck.ps1 -OutputFolder ".\output\Packages" -ExportCsv ".\PackageCheckResults.csv"
```

Run from anywhere against a full path:

```powershell
.\Invoke-IntuneWinCheck.ps1 -OutputFolder "C:\Users\Administrator\Andrew J IT Labs\INTUNE PROJECT\IntunePackaging-Simple\output\Packages"
```

### Checks Performed Per Package

| Check | Description |
|---|---|
| ZIP structure readable | Confirms the file opens as a valid ZIP archive |
| Required entries found | Confirms both IntunePackage.intunewin and Detection.xml exist at expected paths |
| Payload not additionally compressed | Confirms CompressedLength equals Length (encrypted data should not compress) |
| Detection.xml readable | Confirms XML is well-formed and parseable |
| SetupFile populated | Confirms source installer filename is recorded |
| ToolVersion populated | Confirms the packaging tool version is recorded |
| FileDigest present | Confirms SHA256 of original installer is recorded |
| EncryptionKey present | Confirms AES key is present |
| MacKey present | Confirms HMAC key is present |
| IV present | Confirms initialisation vector is present |
| Size consistency | Confirms UnencryptedContentSize vs payload Length delta is 0-15 bytes |

### Output Example

```
================================================================
  IntuneWin Package Integrity Check
  2026-03-30 11:45:00
================================================================
  Target folder: .\output\Packages
  Packages found: 2

======================================================================
  Checking: Evonex Connect Setup 1.8.2.intunewin
======================================================================
  Path:          .\output\Packages\Evonex Connect Setup 1.8.2.intunewin
  Size:          72.73 MB
  Last Modified: 30/03/2026 11:24:30

  [PASS]  ZIP structure readable
  [PASS]  Entry found: IntuneWinPackage/Contents/IntunePackage.intunewin
  [PASS]  Entry found: IntuneWinPackage/Metadata/Detection.xml
  [PASS]  Payload not additionally compressed - Length=76209808 CompressedLength=76209808
  [PASS]  Detection.xml readable
  [PASS]  SetupFile populated - Evonex Connect Setup 1.8.2.exe
  [PASS]  ToolVersion populated - 1.8.7.0
  [PASS]  FileDigest present (SHA256) - z/C+ZQyKHWMv5YlA64jVShLeWcdGJFQ3DC/byLJbjVI=
  [PASS]  EncryptionKey present
  [PASS]  MacKey present
  [PASS]  IV present
  [PASS]  Size consistency - Declared=76209759 Payload=76209808 Delta=49 bytes

  Overall: PASS
```

### Exit Codes

The script exits with code `0` if all packages pass, and `1` if any package fails. This makes it usable in CI/CD pipelines or automated packaging workflows.

### CSV Export Fields

When `-ExportCsv` is used, the output CSV contains:

| Column | Description |
|---|---|
| FileName | Package filename |
| FileSizeMB | File size in megabytes |
| LastModified | File last write timestamp |
| ZipReadable | True/False |
| RequiredEntriesFound | True/False |
| DetectionXmlReadable | True/False |
| SetupFile | Installer filename from manifest |
| ToolVersion | Packaging tool version |
| UnencryptedSizeBytes | Declared unencrypted size |
| PayloadSizeBytes | Actual encrypted payload size |
| SizesConsistent | True/False |
| FileDigestAlgorithm | Hash algorithm (SHA256) |
| FileDigest | Base64 encoded hash of source installer |
| EncryptionKeyPresent | True/False |
| MacKeyPresent | True/False |
| IVPresent | True/False |
| OverallStatus | PASS or FAIL |
| Notes | Any error messages |

## Fail Conditions and Remediation

| Failure | Likely Cause | Remediation |
|---|---|---|
| ZIP not readable | File truncated during copy or packaging | Re-run the Win32 Content Prep Tool from original source |
| Missing entries | Packaging tool error or partial run | Re-run the Win32 Content Prep Tool |
| Detection.xml parse error | Corrupted XML | Re-run the Win32 Content Prep Tool |
| Empty EncryptionKey / MacKey / IV | Packaging tool failed mid-run | Re-run the Win32 Content Prep Tool |
| Size delta outside 0-15 bytes | Manifest and payload mismatch, possible file corruption | Re-run the Win32 Content Prep Tool; verify source installer is not corrupt |
| CompressedLength not equal to Length | File re-compressed after packaging (e.g. copied into a ZIP) | Copy the .intunewin directly, do not place inside another archive |

## Notes on Encryption Keys

The `EncryptionKey`, `MacKey`, `InitializationVector`, and `Mac` values in Detection.xml are the decryption credentials for the payload. The Intune service uses these to decrypt the package on the management endpoint after download from Azure CDN.

These values are sensitive. A `.intunewin` file combined with its Detection.xml gives anyone the ability to decrypt the installer payload. Treat `.intunewin` files with the same care as any installation media:

- Do not commit `.intunewin` files to public repositories
- Store packages in access-controlled locations
- The script masks key values in terminal output (shows only presence, not value)

## Integration with Packaging Workflow

This check should be performed as the final step before uploading to Intune, after the `.intunewin` has been produced and the install/uninstall commands and detection rules have been confirmed.

Recommended packaging workflow order:

1. Obtain source installer
2. Test silent install and uninstall on a clean machine
3. Confirm registry or file detection point post-install
4. Run Win32 Content Prep Tool to produce `.intunewin`
5. Run `Invoke-IntuneWinCheck.ps1` against the output folder
6. Upload to Intune only if all checks pass

## References

- Microsoft Win32 Content Prep Tool: https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool
- Intune Win32 app management overview: https://learn.microsoft.com/en-us/mem/intune/apps/apps-win32-app-management
- Win32 app preparation and upload: https://learn.microsoft.com/en-us/mem/intune/apps/apps-win32-prepare
- AES-256-CBC padding: https://learn.microsoft.com/en-us/dotnet/api/system.security.cryptography.aes
- PowerShell ZipFile class: https://learn.microsoft.com/en-us/dotnet/api/system.io.compression.zipfile
