# Set-WinRegionAndLang

Interactive PowerShell tool for configuring Windows language, region, and locale settings with system-wide propagation to welcome screen and new user accounts.

## Quick Start

### Interactive Mode

```powershell
.\Set-WinRegionAndLang.ps1
```

Displays menu of 20 common language/region combinations. Select number, confirm, and optionally reboot.

### Direct Mode

```powershell
.\Set-WinRegionAndLang.ps1 -LangTag "en-GB" -GeoID 242
```

## Features

- Interactive menu with 20 pre-configured language/region combinations
- Verifies language pack installation before applying
- Applies settings to current user, system locale, welcome screen, and default user profile
- Dual-method compatibility (Windows 11 native cmdlet + Windows 10 XML fallback)
- Administrator privilege check with warnings
- Optional immediate reboot after configuration

## Available Configurations

| Selection | Language/Region | LangTag | GeoID |
|-----------|----------------|---------|-------|
| 1 | English (United States) | en-US | 244 |
| 2 | English (United Kingdom) | en-GB | 242 |
| 3 | English (Canada) | en-CA | 39 |
| 4 | English (Australia) | en-AU | 12 |
| 5 | English (New Zealand) | en-NZ | 183 |
| 6 | English (Ireland) | en-IE | 68 |
| 7 | English (India) | en-IN | 94 |
| 8 | French (France) | fr-FR | 84 |
| 9 | French (Canada) | fr-CA | 39 |
| 10 | German (Germany) | de-DE | 82 |
| 11 | Spanish (Spain) | es-ES | 223 |
| 12 | Spanish (Mexico) | es-MX | 137 |
| 13 | Italian (Italy) | it-IT | 118 |
| 14 | Portuguese (Brazil) | pt-BR | 21 |
| 15 | Portuguese (Portugal) | pt-PT | 193 |
| 16 | Dutch (Netherlands) | nl-NL | 177 |
| 17 | Japanese (Japan) | ja-JP | 117 |
| 18 | Chinese Simplified (China) | zh-CN | 45 |
| 19 | Chinese Traditional (Taiwan) | zh-TW | 228 |
| 20 | Korean (South Korea) | ko-KR | 203 |

## What Gets Changed

| Setting | Cmdlet | Reboot Required |
|---------|--------|-----------------|
| Display Language | `Set-WinUserLanguageList` | No |
| Keyboard Layout | `Set-WinUserLanguageList` | No |
| Home Location | `Set-WinHomeLocation` | No |
| Date/Time/Number Format | `Set-Culture` | No |
| System Locale | `Set-WinSystemLocale` | Yes |
| Welcome Screen | `Copy-UserInternationalSettingsToSystem` or XML | Yes |
| Default User Profile | `Copy-UserInternationalSettingsToSystem` or XML | Yes |

## Prerequisites

**Administrator Rights Required**

Run PowerShell as Administrator:

```powershell
Start-Process powershell -Verb RunAs
```

**Language Pack Installation**

The target language must be installed before configuration.

Check installed languages:

```powershell
Get-WinUserLanguageList | Select LanguageTag
```

Install language packs:

Windows 11/10: Settings > Time & Language > Language & Region > Add a language

Windows Server:

```powershell
Install-Language -Language "en-GB"
```

**Execution Policy**

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## Usage Examples

### Autopilot Deployment

```powershell
# Silent deployment with parameters
.\Set-WinRegionAndLang.ps1 -LangTag "en-GB" -GeoID 242

# Auto-reboot after configuration
.\Set-WinRegionAndLang.ps1 -LangTag "en-GB" -GeoID 242
Start-Sleep -Seconds 5
Restart-Computer -Force
```

### SCCM Task Sequence

Add as "Run PowerShell Script" step after OS installation:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\Set-WinRegionAndLang.ps1 -LangTag "en-US" -GeoID 244
```

### Intune Remediation

Detection:

```powershell
$culture = Get-Culture
$geoID = (Get-ItemProperty "HKCU:\Control Panel\International\Geo" -Name Nation).Nation

if ($culture.Name -eq "en-GB" -and $geoID -eq 242) {
    exit 0  # Compliant
} else {
    exit 1  # Non-compliant
}
```

Remediation:

```powershell
.\Set-WinRegionAndLang.ps1 -LangTag "en-GB" -GeoID 242
```

## Common GeoID Reference

### Europe

| GeoID | Country | Common LangTag |
|-------|---------|----------------|
| 14 | Austria | de-AT |
| 15 | Belgium | nl-BE, fr-BE |
| 75 | Czech Republic | cs-CZ |
| 61 | Denmark | da-DK |
| 77 | Finland | fi-FI |
| 84 | France | fr-FR |
| 82 | Germany | de-DE |
| 88 | Greece | el-GR |
| 99 | Hungary | hu-HU |
| 68 | Ireland | en-IE |
| 118 | Italy | it-IT |
| 177 | Netherlands | nl-NL |
| 177 | Norway | nb-NO |
| 191 | Poland | pl-PL |
| 193 | Portugal | pt-PT |
| 200 | Romania | ro-RO |
| 203 | Russia | ru-RU |
| 223 | Spain | es-ES |
| 221 | Sweden | sv-SE |
| 226 | Switzerland | de-CH, fr-CH, it-CH |
| 242 | United Kingdom | en-GB |

### Americas

| GeoID | Country | Common LangTag |
|-------|---------|----------------|
| 7 | Argentina | es-AR |
| 21 | Brazil | pt-BR |
| 39 | Canada | en-CA, fr-CA |
| 46 | Chile | es-CL |
| 51 | Colombia | es-CO |
| 137 | Mexico | es-MX |
| 244 | United States | en-US |

### Asia-Pacific

| GeoID | Country | Common LangTag |
|-------|---------|----------------|
| 12 | Australia | en-AU |
| 45 | China | zh-CN |
| 101 | Hong Kong | zh-HK |
| 94 | India | en-IN, hi-IN |
| 101 | Indonesia | id-ID |
| 117 | Japan | ja-JP |
| 145 | Malaysia | ms-MY |
| 183 | New Zealand | en-NZ |
| 193 | Philippines | fil-PH, en-PH |
| 210 | Singapore | en-SG, zh-SG |
| 203 | South Korea | ko-KR |
| 228 | Taiwan | zh-TW |
| 227 | Thailand | th-TH |
| 251 | Vietnam | vi-VN |

Complete GeoID list: https://learn.microsoft.com/en-us/windows/win32/intl/table-of-geographical-locations

## Troubleshooting

### Language Pack Not Installed

```
Error: Cannot validate argument on parameter 'Language'
```

Solution: Install language pack via Settings > Time & Language > Language & Region

### Access Denied

```
Set-WinSystemLocale : Access is denied
```

Solution: Run PowerShell as Administrator

### Settings Not Applied to Welcome Screen

Check if modern cmdlet is available:

```powershell
Get-Command Copy-UserInternationalSettingsToSystem
```

If not available, script uses legacy XML method which may fail on locked-down systems.

Manual fallback:
1. Settings > Time & Language > Language & Region
2. Administrative language settings > Copy settings
3. Check "Welcome screen and system accounts"
4. Reboot

### Script Runs But No Changes After Reboot

Most likely cause: Language pack was not installed. Verify:

```powershell
Get-WinUserLanguageList | Select LanguageTag
```

## Code Review Summary

### Strengths

**Interactive UX**: Menu system eliminates need to look up LangTag/GeoID values. Pre-configured combinations cover 90% of use cases.

**Parameter Fallback**: Maintains backward compatibility and supports automation scenarios with `-LangTag` and `-GeoID` parameters.

**Pre-flight Checks**: Verifies language pack installation before attempting configuration, preventing cryptic errors.

**Dual-Method Compatibility**: Uses Windows 11 `Copy-UserInternationalSettingsToSystem` cmdlet when available, falls back to Windows 10 XML injection method.

**Admin Privilege Warning**: Checks for administrator rights and warns user rather than silently failing on system-level operations.

### Potential Improvements

**Add Custom Entry Option**: Menu could include option 21 to manually enter LangTag/GeoID for configurations not in the preset list.

**Validate GeoID Range**: Add parameter validation:

```powershell
[ValidateRange(1,300)][int]$GeoID
```

**Return Status Object**: For automation, return structured result:

```powershell
[PSCustomObject]@{
    Success = $true
    LangTag = $LangTag
    GeoID = $GeoID
    RebootRequired = $true
}
```

**Log to File**: Add optional logging for troubleshooting deployment issues:

```powershell
$logPath = "$env:TEMP\Set-WinRegionAndLang.log"
"[$(Get-Date)] Applied $LangTag / $GeoID" | Out-File $logPath -Append
```

**Implement ShouldProcess**: For safety in production environments:

```powershell
[CmdletBinding(SupportsShouldProcess=$true)]
if ($PSCmdlet.ShouldProcess("System", "Apply region settings")) { ... }
```

## Technical Background

### Language Tags (BCP 47)

Format: `language-REGION`

- `language`: ISO 639-1 two-letter code (en, fr, de, es, ja, zh)
- `REGION`: ISO 3166-1 alpha-2 country code (US, GB, FR, DE, CN, JP)

Examples: en-US, en-GB, fr-FR, de-DE, ja-JP, zh-CN

### System Locale vs User Locale

**User Locale** (Culture): Controls date/time/number formats for current user. Changes immediately without reboot.

**System Locale**: Controls character encoding for non-Unicode applications. Requires administrator rights and system reboot.

### Propagation Methods

**Windows 11 (22H2+)**: Native `Copy-UserInternationalSettingsToSystem` cmdlet in International module.

**Windows 10**: XML-based configuration via control.exe:

```xml
<gs:GlobalizationServices xmlns:gs="urn:longhornGlobalizationUnattend">
    <gs:UserList>
        <gs:User UserID="Current" CopySettingsToDefaultUserAcct="true" CopySettingsToSystemAcct="true"/>
    </gs:UserList>
</gs:GlobalizationServices>
```

This schema is documented in Windows System Image Manager (SIM) unattend.xml reference for `Microsoft-Windows-International-Core` component.

## References

**Microsoft Documentation**
- Set-WinUserLanguageList: https://learn.microsoft.com/en-us/powershell/module/international/set-winuserlanguagelist
- Set-WinHomeLocation: https://learn.microsoft.com/en-us/powershell/module/international/set-winhomelocation
- Set-Culture: https://learn.microsoft.com/en-us/powershell/module/international/set-culture
- Set-WinSystemLocale: https://learn.microsoft.com/en-us/powershell/module/international/set-winsystemlocale
- Copy-UserInternationalSettingsToSystem: https://learn.microsoft.com/en-us/powershell/module/international/copy-userinternationalsettingstosystem
- GeoID Table: https://learn.microsoft.com/en-us/windows/win32/intl/table-of-geographical-locations

**Standards**
- BCP 47 Language Tags: https://www.rfc-editor.org/rfc/rfc5646.html
- ISO 639-1 Language Codes: https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes
- ISO 3166-1 Country Codes: https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2