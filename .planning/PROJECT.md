# TheSmith — Foreign Connection Audit Report

## What This Is

A PowerShell-driven security reporting tool with a web frontend that scans locally exported Microsoft Entra ID and Intune logs to detect connections, sign-ins, and device check-ins originating from outside the United States. IT administrators run the tool on demand to surface foreign activity across their tenant and export findings as a CSV summary.

## Core Value

An IT admin can load their Entra and Intune log exports, immediately see all non-US activity in a clear web UI, and export a CSV report — without needing cloud access or manual log grepping.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] User can load exported Entra sign-in log files (JSON or CSV) via the web UI
- [ ] User can load exported Intune device log files via the web UI
- [ ] Tool identifies sign-ins from non-US IP addresses using geolocation
- [ ] Tool identifies access to apps/resources hosted in foreign countries
- [ ] Tool identifies Intune-managed devices that checked in from foreign IP addresses
- [ ] Tool shows device compliance state alongside foreign check-in events
- [ ] All non-US countries are flagged (no risk tiers — any foreign = flagged)
- [ ] Web UI displays flagged events in a readable, filterable table
- [ ] User can export findings as CSV/Excel

### Out of Scope

- Risk tiering by country — all foreign treated equally for now
- Direct API connection to Microsoft Graph / Entra (logs are pre-exported locally)
- Scheduled/automated runs — on-demand only
- Mobile app or cross-platform support — Windows/PowerShell first
- Real-time monitoring

## Context

- Logs are exported from the Microsoft Entra admin center and/or Intune portal
- Common export formats from Entra: JSON (sign-in logs), CSV
- Common export formats from Intune: CSV (device compliance reports)
- IP geolocation will be needed to map IP addresses to countries — a local or lightweight lookup approach is preferred over requiring API keys
- The web frontend will be served locally by PowerShell (no external hosting)
- Home country is United States — everything else is foreign

## Constraints

- **Tech stack**: PowerShell backend + HTML/CSS/JS web frontend (no Node, no Python)
- **Runtime**: Must run on Windows without additional installs beyond PowerShell 5.1+
- **Data**: Works on locally exported files only — no live API calls during report generation
- **Distribution**: Single script or small folder — easy for IT admin to copy and run

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------| --------|
| PowerShell + web frontend | Admin-friendly on Windows, no extra installs, web UI for ease of use | — Pending |
| Local file input (not live API) | Admin controls when to pull logs; no credential management in tool | — Pending |
| All-foreign flagging (no tiers) | Simple and consistent — admin decides what to investigate | — Pending |

---
*Last updated: 2026-03-19 after initialization*
