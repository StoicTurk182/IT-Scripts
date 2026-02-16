# DMARC Record Breakdown

Reference for understanding DMARC TXT record tags and their values.

## Record Tags

| Tag | Value | Purpose |
|-----|-------|---------|
| `v` | `DMARC1` | **Version:** Identifies the record as DMARC (required first). |
| `p` | `quarantine` | **Policy:** Tells receiving servers to send suspicious emails to the recipient's Spam/Junk folder. |
| `pct` | `50` | **Percentage:** This is a "rollout" setting. Only 50% of emails failing checks will be quarantined; the other 50% will still go to the Inbox. |
| `rua` | `mailto:...` | **Reporting:** Aggregate XML reports will be sent to this email so you can see who is sending mail as your domain. |
| `aspf` | `r` | **SPF Alignment:** Set to "Relaxed." The domain in the "From" header only needs to match the organizational domain of the SPF record. |
| `adkim` | `r` | **DKIM Alignment:** Set to "Relaxed." Similar to SPF, the DKIM signature domain must share the same root domain as the "From" address. |
| `fo` | `1` | **Failure Options:** Generates a report if any underlying authentication mechanism (SPF or DKIM) fails. |

## Example Record

```
v=DMARC1; p=quarantine; pct=50; rua=mailto:dmarc-reports@example.com; aspf=r; adkim=r; fo=1
```

## References

- DMARC Specification (RFC 7489): https://datatracker.ietf.org/doc/html/rfc7489
- Microsoft DMARC Documentation: https://learn.microsoft.com/en-us/microsoft-365/security/office-365-security/email-authentication-dmarc-configure
- DMARC.org Overview: https://dmarc.org/overview/
