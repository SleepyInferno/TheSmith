# Roadmap: TheSmith — Foreign Connection Audit Report

## Overview

TheSmith delivers a PowerShell-driven security audit tool in three phases. Phase 1 builds the entire backend pipeline: HTTP server, Entra log ingestion, geolocation, and foreign sign-in detection. Phase 2 builds the complete web UI with summary dashboard, per-user rollups, and filterable event tables. Phase 3 adds Intune device correlation and CSV export, completing the tool for production use.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Server, Parsing, and Detection Engine** - PowerShell HTTP server that ingests Entra logs, resolves geolocation, and identifies all foreign sign-in events
- [ ] **Phase 2: Web UI and Dashboard** - Complete browser-based interface with summary stats, per-user rollups, filtering, and sorting
- [ ] **Phase 3: Intune Integration and Export** - Intune device file loading, device compliance correlation, and CSV export of all findings

## Phase Details

### Phase 1: Server, Parsing, and Detection Engine
**Goal**: An IT admin can launch a single PowerShell script, upload an Entra sign-in log file, and receive structured JSON data identifying all non-US sign-in events -- with correct geolocation, deduplication, and edge case handling
**Depends on**: Nothing (first phase)
**Requirements**: INFRA-01, INFRA-02, INFRA-03, INFRA-04, INGEST-01, INGEST-02, INGEST-04, INGEST-05, GEO-01, GEO-02, GEO-03, DETECT-01, DETECT-02, DETECT-03, DETECT-04
**Success Criteria** (what must be TRUE):
  1. Admin runs `Start-TheSmith.ps1` and a local HTTP server starts, opening the browser to the web UI -- on stock Windows with PowerShell 5.1, no additional installs
  2. Admin uploads an Entra sign-in JSON or CSV file through the web UI and the backend parses it without error, including files with missing/null IP fields
  3. Backend resolves IP addresses to countries using the bundled IP2Location database (not relying solely on Entra's built-in location field), handling both IPv4 and IPv6
  4. Backend returns a JSON response containing only non-US sign-in events, deduplicated by correlationId, with all extracted fields (UPN, display name, IP, country, city, timestamp, app, client app, status, risk level) and legacy protocol flags
  5. If a file has near-100K rows, a truncation warning is included in the response
**Plans**: 4 plans

Plans:
- [x] 01-01-PLAN.md — GeoLookup module: IP2Location CSV loading and binary-search IP-to-country resolution (IPv4 + IPv6)
- [x] 01-02-PLAN.md — FileParser module: Entra sign-in log JSON/CSV auto-detection and parsing with field normalization
- [x] 01-03-PLAN.md — DetectionEngine module: foreign sign-in filtering, correlationId deduplication, legacy protocol flagging
- [x] 01-04-PLAN.md — HTTP server, async job manager, entry-point script, and placeholder web UI

### Phase 2: Web UI and Dashboard
**Goal**: An IT admin sees all foreign sign-in activity in a clear, interactive web interface with summary statistics, per-user investigation rollups, and full event detail with filtering and sorting
**Depends on**: Phase 1
**Requirements**: UI-01, UI-02, UI-03, UI-04, UI-05, UI-06, UI-07, UI-08, UI-09
**Success Criteria** (what must be TRUE):
  1. After uploading a log file, the web UI displays a summary dashboard showing total foreign sign-in count, breakdown by country (sorted by count), and top users by foreign sign-in count
  2. Admin can view a per-user rollup showing each user's name, total foreign sign-in count, countries seen, and date range -- and can expand any user row to see their individual events
  3. Legacy protocol sign-ins (IMAP, POP3, SMTP, ActiveSync) are visually distinguished in both the per-user and event detail views
  4. Admin can view a full event table with all extracted fields, filter by country/user/date range/sign-in status, and sort by any column
**Plans**: 3 plans

Plans:
- [ ] 02-01-PLAN.md — Foundation: test fixture, CSS design system, page structure (index.html), upload flow, and summary dashboard (hero stats, country bars, top users)
- [ ] 02-02-PLAN.md — Per-user rollup table with accordion-expand sub-tables and legacy auth visual treatment
- [ ] 02-03-PLAN.md — All-events table with filter bar (text search, country, status, date range), column sorting, and visual verification checkpoint

### Phase 3: Intune Integration and Export
**Goal**: An IT admin can load Intune device data, correlate foreign sign-in events with device compliance state, and export a complete CSV report of all findings
**Depends on**: Phase 2
**Requirements**: INGEST-03, INTUNE-01, INTUNE-02, INTUNE-03, EXPORT-01, EXPORT-02
**Success Criteria** (what must be TRUE):
  1. Admin uploads an Intune device compliance CSV via the web UI file picker, and the tool correlates device records to sign-in events via userPrincipalName
  2. Where a device match exists, the UI displays device name, OS, and compliance state (Compliant / Non-compliant / Unknown) alongside the foreign sign-in event
  3. Admin can export all flagged foreign events as a CSV file containing every extracted field including device compliance state
**Plans**: TBD

Plans:
- [ ] 03-01: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Server, Parsing, and Detection Engine | 4/4 | Complete | 2026-03-19 |
| 2. Web UI and Dashboard | 2/3 | In Progress|  |
| 3. Intune Integration and Export | 0/1 | Not started | - |
