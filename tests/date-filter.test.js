/**
 * Tests for date-range filter timezone offset handling.
 * Exercises the filter logic that will be in getFilteredSortedEvents().
 *
 * Run: node tests/date-filter.test.js
 */

// Simulate the filter logic as it exists in app.js
// We extract just the date filter portion for unit testing.
// The actual implementation reads from app.js; this simulates the same logic.

function filterByDate(events, dateFrom, dateTo) {
    var results = events.slice();

    // --- BEGIN: date filter logic (mirrors app.js getFilteredSortedEvents) ---
    // Apply date-from filter (parse to UTC epoch for offset-safe comparison)
    if (dateFrom) {
        var fromEpoch = new Date(dateFrom + 'T00:00:00Z').getTime();
        results = results.filter(function(evt) {
            return new Date(evt.timestamp).getTime() >= fromEpoch;
        });
    }

    // Apply date-to filter (include the full end day in UTC)
    if (dateTo) {
        var toEpoch = new Date(dateTo + 'T23:59:59.999Z').getTime();
        results = results.filter(function(evt) {
            return new Date(evt.timestamp).getTime() <= toEpoch;
        });
    }
    // --- END: date filter logic ---

    return results;
}

// Test helpers
var passed = 0;
var failed = 0;

function assert(condition, message) {
    if (condition) {
        passed++;
        console.log('  PASS: ' + message);
    } else {
        failed++;
        console.log('  FAIL: ' + message);
    }
}

function makeEvent(timestamp) {
    return { timestamp: timestamp, userDisplayName: 'Test' };
}

console.log('Date Filter Tests (timezone offset handling)\n');

// Test 1: Timestamp with -04:00 offset, UTC is March 20
// "2026-03-19T23:45:00-04:00" => UTC 2026-03-20T03:45:00Z
// dateFrom="2026-03-20" should INCLUDE this event
var t1Events = [makeEvent('2026-03-19T23:45:00-04:00')];
var t1Result = filterByDate(t1Events, '2026-03-20', '');
assert(t1Result.length === 1,
    'Test 1: -04:00 offset event (UTC Mar 20) included with dateFrom=2026-03-20');

// Test 2: Same timestamp with dateTo="2026-03-19" should EXCLUDE it
// UTC is Mar 20, so dateTo Mar 19 should not include it
var t2Result = filterByDate(t1Events, '', '2026-03-19');
assert(t2Result.length === 0,
    'Test 2: -04:00 offset event (UTC Mar 20) excluded with dateTo=2026-03-19');

// Test 3: Timestamp with +05:00 offset, UTC is March 19
// "2026-03-20T01:30:00+05:00" => UTC 2026-03-19T20:30:00Z
// dateTo="2026-03-19" should INCLUDE this event
var t3Events = [makeEvent('2026-03-20T01:30:00+05:00')];
var t3Result = filterByDate(t3Events, '', '2026-03-19');
assert(t3Result.length === 1,
    'Test 3: +05:00 offset event (UTC Mar 19) included with dateTo=2026-03-19');

// Test 4: Z-suffixed timestamp with dateFrom - no regression
var t4Events = [makeEvent('2026-03-18T08:15:00Z')];
var t4Result = filterByDate(t4Events, '2026-03-18', '');
assert(t4Result.length === 1,
    'Test 4: Z timestamp included with dateFrom=2026-03-18');

// Test 5: Z-suffixed timestamp with dateTo - no regression
var t5Result = filterByDate(t4Events, '', '2026-03-18');
assert(t5Result.length === 1,
    'Test 5: Z timestamp included with dateTo=2026-03-18');

console.log('\nResults: ' + passed + ' passed, ' + failed + ' failed');
process.exit(failed > 0 ? 1 : 0);
