---
phase: 02-web-ui-and-dashboard
plan: 02
subsystem: ui
tags: [vanilla-js, accordion, per-user-rollup, legacy-auth, event-delegation]
dependency_graph:
  requires: [02-01]
  provides: [per-user-rollup-table, accordion-expand, legacy-auth-badges]
  affects: [web/app.js]
tech_stack:
  added: []
  patterns: [event-delegation, innerHTML-batch-insert, accordion-toggle]
key_files:
  created: []
  modified: [web/app.js]
decisions:
  - Used event delegation on tbody for accordion click handling (performance over per-row listeners)
  - Sorted sub-table events by timestamp descending for chronological relevance
metrics:
  duration: 1min
  completed: "2026-03-19T19:59:30Z"
---

# Phase 2 Plan 2: Per-User Rollup Table Summary

Per-user rollup table with accordion sub-tables and legacy auth amber badges via event delegation on innerHTML-rendered rows.

## What Was Built

Replaced the `renderUserRollup` stub in `web/app.js` with a full implementation that:

1. **User summary rows** -- Each user gets a clickable row showing display name, event count, comma-separated country names (via `getCountryName`), and formatted date range.

2. **Accordion sub-tables** -- Each user row has a hidden expansion row containing a nested `<table class="sub-table">` with columns: Timestamp, IP, Country, App, Status, Protocol. Events are sorted by timestamp descending.

3. **Legacy auth visual treatment** -- Events where `isLegacyAuth` is true get `class="legacy-row"` (amber left border + warning background via CSS) and a `<span class="legacy-badge">` showing the warning sign + "Legacy Auth" text.

4. **Click handling** -- Event delegation on `#user-rollup-body` toggles `visible` class on expansion rows and `expanded` class on user rows (which rotates the chevron via existing CSS transitions). Multiple rows can be expanded simultaneously.

5. **Security** -- All user-provided strings (displayName, ipAddress, appDisplayName, clientAppUsed, signInStatus) pass through `escapeHtml()` before innerHTML insertion.

## Task Completion

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Implement renderUserRollup with accordion sub-tables and legacy auth badges | 745ef82 | web/app.js |

## Deviations from Plan

None -- plan executed exactly as written.

## Self-Check: PASSED
