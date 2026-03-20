# TheSmith — Foreign Connection Audit

TheSmith is a self-contained PowerShell tool for IT administrators to audit Microsoft Entra (Azure AD) sign-in logs for suspicious foreign access. Upload a sign-in log, get a structured interactive report — no cloud services, no external dependencies, no modules to install.

---

## What It Does

1. **Parses** Entra sign-in logs (JSON or CSV export formats)
2. **Geolocates** every sign-in IP address using a bundled IP2Location database
3. **Filters** out US-origin, private, and null-IP records
4. **Deduplicates** events by `correlationId`
5. **Flags** legacy authentication protocols (IMAP, POP3, SMTP, Exchange ActiveSync, MAPI, etc.)
6. **Optionally enriches** results with Intune device compliance data
7. **Presents** findings in an interactive web UI with per-user rollups, filtering, sorting, and CSV export

All processing happens locally. No data leaves the machine.

---

## Requirements

- **Windows** with **PowerShell 5.1+** (built into Windows 10/11 — no install needed)
- A modern browser (opened automatically on launch)

---

## Quick Start

```powershell
.\Start-TheSmith.ps1
```

This will:
- Load the bundled IP2Location geolocation database
- Start a local HTTP server on port `8080`
- Open the UI in your default browser

To use a different port:

```powershell
.\Start-TheSmith.ps1 -Port 9090
```

Press `Ctrl+C` in the terminal to shut down.

---

## Getting Your Sign-In Log

Export from the **Microsoft Entra admin center**:

1. Go to [entra.microsoft.com](https://entra.microsoft.com) → **Identity** → **Monitoring & health** → **Sign-in logs**
2. Apply any filters (date range, user, etc.)
3. Click **Download** → choose **JSON** or **CSV**

Both the raw JSON array format and the Microsoft wrapper format (`{"value": [...]}`) are supported.

> **Note:** Entra exports are capped at 100,000 rows. If your tenant has high sign-in volume, narrow the date range or filter by user/app before exporting.

---

## Using the UI

### Upload a Sign-In Log

Drag and drop your exported file onto the upload area, or click to browse. Processing runs in the background — a progress indicator shows status.

### Summary Dashboard

Once processing completes, the dashboard shows:

| Section | Description |
|---------|-------------|
| **Foreign Events** | Total non-US sign-in events detected |
| **Affected Users** | Distinct user accounts with foreign activity |
| **Legacy Auth** | Events using legacy protocols (IMAP, POP3, SMTP, etc.) |
| **Countries** | Breakdown of source countries |

### Per-User Rollup

Each user with foreign activity gets a collapsible row showing:
- Total foreign events
- Countries seen
- Whether legacy auth was used (amber badge)
- Expandable sub-table with individual sign-in events

### Events Table

Full list of all foreign events with columns for:
- User, IP address, country, city
- Timestamp, application, client app used
- Sign-in status, risk level
- Legacy auth indicator

Supports column sorting and freetext filtering.

### Intune Device Enrichment (Optional)

If your organisation uses Microsoft Intune, you can enrich results with device compliance data:

1. Export device data from Intune (Graph API or Admin Center CSV format)
2. After uploading your Entra log, click **Upload Intune Data**
3. Results update to include device name, OS, and compliance state per user

### CSV Export

Click **Export CSV** to download a complete report of all foreign events including Intune fields (if loaded). Suitable for ticket creation, manager review, or archiving.

### Saved Results

Previously processed results are saved automatically to the `results/` directory. Use the **Load Saved** option in the UI to reload a prior run without re-uploading.

---

## Project Structure

```
TheSmith/
├── Start-TheSmith.ps1          # Entry point — launches server and opens browser
├── lib/
│   ├── GeoLookup.ps1           # IP geolocation using IP2Location binary search
│   ├── FileParser.ps1          # Entra log parser (JSON + CSV, auto-detects format)
│   ├── DetectionEngine.ps1     # Foreign event filtering, deduplication, legacy auth flagging
│   ├── IntuneParser.ps1        # Intune CSV parser, device correlation, CSV export builder
│   ├── JobManager.ps1          # Async background job management via PowerShell Runspaces
│   └── Server.ps1              # HttpListener-based HTTP server and route dispatcher
├── web/
│   ├── index.html              # Single-page application shell
│   ├── app.js                  # All UI logic — rendering, filtering, sorting, upload flow
│   └── styles.css              # Design system with light/dark theme support
├── data/
│   ├── IP2LOCATION-LITE-DB1.CSV        # IPv4 geolocation database
│   └── IP2LOCATION-LITE-DB1.IPV6.CSV  # IPv6 geolocation database
├── results/                    # Auto-created — stores processed job JSON files
└── tests/                      # Pester test suite (109 tests)
```

---

## Module Overview

### `GeoLookup.ps1`
Loads the IP2Location Lite CSV database into sorted in-memory arrays and performs binary search to resolve an IP address to a country code. Supports both IPv4 and IPv6. Private and reserved IP ranges are detected and excluded before lookup.

### `FileParser.ps1`
Parses Entra sign-in log exports. Auto-detects format from file extension or content peek. Handles:
- JSON bare arrays (`[{...}]`)
- Microsoft wrapper JSON (`{"value": [{...}]}`)
- CSV exports with display-friendly column headers

Uses `JavaScriptSerializer` for JSON to avoid the PowerShell 5.1 depth limit on `ConvertFrom-Json`. Streams CSV via `StreamReader` for memory efficiency on large files.

### `DetectionEngine.ps1`
Processes parsed records through a pipeline:
1. Skip null/empty IP addresses
2. Skip private/reserved IPs (RFC 1918, loopback, link-local, IPv6 ULA)
3. Geolocate — skip US and unknown results
4. Deduplicate by `correlationId` (keeps first occurrence)
5. Build enriched result record with `isLegacyAuth` flag

**Legacy protocols flagged:** Exchange ActiveSync, IMAP, IMAP4, POP, POP3, SMTP, Authenticated SMTP, MAPI, Autodiscover, Exchange Web Services, Exchange Online PowerShell, Other clients.

### `IntuneParser.ps1`
Parses Intune device export CSVs. Handles both Graph API format and Admin Center format column names via a normalisation map. Correlates devices to Entra results by UPN. When a user has multiple devices, the worst compliance state is used. Builds CSV export rows with proper comma escaping.

### `JobManager.ps1`
Manages a single background processing job using PowerShell Runspaces. Provides a thread-safe shared state hashtable for status polling (`idle | processing | complete | error`). Saves completed results as JSON files in the `results/` directory.

### `Server.ps1`
A minimal HTTP server built on `System.Net.HttpListener`. Routes:

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/` | Serves `web/index.html` |
| `GET` | `/status` | Returns current job status and progress |
| `POST` | `/upload` | Accepts Entra log file, starts processing job |
| `GET` | `/results` | Returns completed job results as JSON |
| `GET` | `/saved-results` | Lists previously saved result files |
| `GET` | `/load-result` | Returns content of a saved result file by `?name=` |
| `POST` | `/upload-intune` | Accepts Intune CSV, correlates with current results |
| `GET` | `/shutdown` | Gracefully stops the server |

---

## Running Tests

Requires [Pester](https://pester.dev/) v5. Windows ships with Pester 3.x by default — install v5 first:

```powershell
Install-Module Pester -Force -SkipPublisherCheck
```

```powershell
Invoke-Pester -Path ./tests/ -Output Detailed
```

**111 tests** covering all modules:

| File | Coverage |
|------|----------|
| `GeoLookup.Tests.ps1` | IPv4/IPv6 loading, binary search, private IP detection |
| `FileParser.Tests.ps1` | JSON/CSV parsing, format detection, null IP handling, truncation |
| `DetectionEngine.Tests.ps1` | Filtering, deduplication, legacy protocol detection, field mapping |
| `IntuneParser.Tests.ps1` | Both CSV formats, compliance normalisation, device correlation, CSV export |
| `Server.Tests.ps1` | HTTP endpoints, upload flow, Intune enrichment, dependency checks |

---

## Geolocation Data

TheSmith uses the [IP2Location LITE](https://lite.ip2location.com/) database (CC BY-SA 4.0), bundled in the `data/` directory. This database maps IP ranges to country codes.

The database is accurate at the country level. City data shown in the UI comes from the location fields embedded in the Entra sign-in log itself, not the IP2Location database.

To update the database, download a new `DB1` CSV from [lite.ip2location.com](https://lite.ip2location.com/) and replace the files in `data/`.

---

## Limitations

- **Single-user tool** — designed for one analyst running one job at a time. Concurrent uploads are not supported.
- **US-only filtering** — currently flags all non-US sign-ins. Future versions may support configurable country allowlists.
- **No authentication** — the server binds to `localhost` only and is not intended to be exposed on a network.
- **100k row Entra export cap** — Microsoft's export limit. Split by date range for larger datasets.

---

## License

Geolocation data: IP2Location LITE, licensed under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).

Application code: see repository for license details.
