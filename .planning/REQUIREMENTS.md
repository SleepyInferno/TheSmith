# Requirements: TheSmith — Foreign Connection Audit Report

**Defined:** 2026-03-19
**Core Value:** An IT admin can load Entra and Intune exports, immediately see all non-US activity in a clear web UI, and export a CSV — without cloud access or manual log grepping.

## v1 Requirements

### File Ingestion

- [x] **INGEST-01**: User can load an Entra sign-in log JSON file via the web UI file picker
- [x] **INGEST-02**: User can load an Entra sign-in log CSV file via the web UI file picker
- [ ] **INGEST-03**: User can load an Intune device compliance CSV file via the web UI file picker
- [x] **INGEST-04**: Tool detects and warns the user when an Entra export is truncated at 100,000 rows
- [x] **INGEST-05**: Tool handles files with missing or null IP address fields without crashing

### Geolocation

- [x] **GEO-01**: Tool resolves IP addresses to countries using IP2Location LITE DB1 (bundled, offline, no API key)
- [x] **GEO-02**: Tool does NOT rely on Entra's built-in `location.countryOrRegion` as the sole geolocation source (known unreliable)
- [x] **GEO-03**: Tool correctly identifies US vs non-US for both IPv4 and IPv6 addresses

### Foreign Sign-in Detection

- [x] **DETECT-01**: Tool identifies all sign-in events from non-US IP addresses
- [x] **DETECT-02**: Tool deduplicates sign-in events by `correlationId` to avoid counting MFA/CA retry events multiple times
- [x] **DETECT-03**: Tool flags sign-ins using legacy protocols (IMAP, POP3, SMTP, ActiveSync, Exchange ActiveSync) from foreign IPs as high-risk
- [x] **DETECT-04**: Tool extracts and displays: user principal name, display name, IP address, resolved country, city, sign-in timestamp, app accessed, client app used, sign-in status (success/failure), risk level

### Intune Device Correlation

- [ ] **INTUNE-01**: Tool correlates Intune device records to Entra sign-in events via `userPrincipalName`
- [ ] **INTUNE-02**: Tool displays device compliance state (Compliant / Non-compliant / Unknown) alongside foreign sign-in events where a device match exists
- [ ] **INTUNE-03**: Tool shows device name and OS alongside correlated sign-in events

### Web UI — Summary Dashboard

- [x] **UI-01**: Web UI displays total count of foreign sign-in events detected
- [x] **UI-02**: Web UI displays breakdown of events by country (sorted by count descending)
- [x] **UI-03**: Web UI displays top users by foreign sign-in count

### Web UI — Per-User Rollup

- [x] **UI-04**: Web UI groups foreign events by user, showing: user name, total foreign sign-in count, countries seen, date range of activity
- [x] **UI-05**: User can expand a per-user row to see that user's individual sign-in events
- [x] **UI-06**: Legacy protocol sign-ins are visually distinguished (e.g., badge or highlight) in per-user and event views

### Web UI — Per-Event Detail

- [ ] **UI-07**: Web UI displays a filterable table of all foreign sign-in events with all extracted fields
- [ ] **UI-08**: User can filter the event table by country, user, date range, or sign-in status
- [ ] **UI-09**: User can sort the event table by any column

### Export

- [ ] **EXPORT-01**: User can export all flagged foreign events as a CSV file
- [ ] **EXPORT-02**: CSV export includes all extracted fields: user, IP, country, city, timestamp, app, client app, protocol, status, risk level, device compliance state

### Infrastructure

- [x] **INFRA-01**: Tool is launched by running a single PowerShell script (`Start-TheSmith.ps1`)
- [x] **INFRA-02**: PowerShell script starts a local HTTP server and opens the web UI in the default browser automatically
- [x] **INFRA-03**: Tool runs on PowerShell 5.1+ on Windows with no additional installs required
- [x] **INFRA-04**: Tool processes log files locally — no data is sent to any external service

## v2 Requirements

### False Positive Suppression

- **FPS-01**: User can define an IP/CIDR allowlist of known-safe addresses (VPNs, proxies) to exclude from flagging
- **FPS-02**: Allowlist is persisted to a local config file

### Enhanced Exports

- **EXPORT-03**: Excel (.xlsx) export with formatted columns and conditional formatting on risk fields
- **EXPORT-04**: Printable HTML report for formal distribution

### Extended Coverage

- **EXT-01**: Support for Azure Monitor / Log Analytics exported JSON format
- **EXT-02**: Risk tiering by country (configurable high/medium/low)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Live Microsoft Graph API connection | Tool works on pre-exported files only — no credentials stored |
| Scheduled / automated runs | On-demand use only for v1 |
| Mobile or cross-platform support | Windows/PowerShell first |
| Real-time monitoring | File-based batch processing only |
| IP allowlist (v1) | Flag everything for now; admin reviews manually |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| INGEST-01 | Phase 1 | Complete |
| INGEST-02 | Phase 1 | Complete |
| INGEST-03 | Phase 3 | Pending |
| INGEST-04 | Phase 1 | Complete |
| INGEST-05 | Phase 1 | Complete |
| GEO-01 | Phase 1 | Complete |
| GEO-02 | Phase 1 | Complete |
| GEO-03 | Phase 1 | Complete |
| DETECT-01 | Phase 1 | Complete |
| DETECT-02 | Phase 1 | Complete |
| DETECT-03 | Phase 1 | Complete |
| DETECT-04 | Phase 1 | Complete |
| INTUNE-01 | Phase 3 | Pending |
| INTUNE-02 | Phase 3 | Pending |
| INTUNE-03 | Phase 3 | Pending |
| UI-01 | Phase 2 | Complete |
| UI-02 | Phase 2 | Complete |
| UI-03 | Phase 2 | Complete |
| UI-04 | Phase 2 | Complete |
| UI-05 | Phase 2 | Complete |
| UI-06 | Phase 2 | Complete |
| UI-07 | Phase 2 | Pending |
| UI-08 | Phase 2 | Pending |
| UI-09 | Phase 2 | Pending |
| EXPORT-01 | Phase 3 | Pending |
| EXPORT-02 | Phase 3 | Pending |
| INFRA-01 | Phase 1 | Complete |
| INFRA-02 | Phase 1 | Complete |
| INFRA-03 | Phase 1 | Complete |
| INFRA-04 | Phase 1 | Complete |

**Coverage:**
- v1 requirements: 30 total
- Phase 1: 15 requirements (INFRA, INGEST-01/02/04/05, GEO, DETECT)
- Phase 2: 9 requirements (UI)
- Phase 3: 6 requirements (INGEST-03, INTUNE, EXPORT)
- Mapped to phases: 30
- Unmapped: 0

---
*Requirements defined: 2026-03-19*
*Last updated: 2026-03-19 after roadmap creation*
