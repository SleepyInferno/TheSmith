/* TheSmith - Foreign Connection Audit - Client Application */

/* ==================== Utility Functions ==================== */

function escapeHtml(str) {
    if (str == null) return '';
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

function debounce(fn, ms) {
    var timer;
    return function() {
        var args = arguments;
        var context = this;
        clearTimeout(timer);
        timer = setTimeout(function() { fn.apply(context, args); }, ms);
    };
}

function formatTimestamp(isoStr) {
    return new Date(isoStr).toLocaleString();
}

/* ==================== Country Code Lookup ==================== */

var COUNTRY_NAMES = {
    US: 'United States', CN: 'China', RU: 'Russia', DE: 'Germany',
    GB: 'United Kingdom', FR: 'France', JP: 'Japan', BR: 'Brazil',
    IN: 'India', AU: 'Australia', CA: 'Canada', KR: 'South Korea',
    NG: 'Nigeria', ZA: 'South Africa', MX: 'Mexico', IT: 'Italy',
    ES: 'Spain', NL: 'Netherlands', SE: 'Sweden', NO: 'Norway',
    PL: 'Poland', TR: 'Turkey', UA: 'Ukraine', ID: 'Indonesia',
    TH: 'Thailand', VN: 'Vietnam', PH: 'Philippines', EG: 'Egypt',
    IR: 'Iran', SA: 'Saudi Arabia', AE: 'United Arab Emirates',
    AR: 'Argentina', CL: 'Chile', CO: 'Colombia', PK: 'Pakistan',
    BD: 'Bangladesh', MY: 'Malaysia', SG: 'Singapore', HK: 'Hong Kong',
    TW: 'Taiwan'
};

function getCountryName(code) {
    return COUNTRY_NAMES[code] || code;
}

/* ==================== State Variables ==================== */

var allResults = [];
var metadata = null;
var intuneLoaded = false;
var filterState = { search: '', country: '', status: '', dateFrom: '', dateTo: '' };
var sortState = { column: 'timestamp', direction: 'desc' };

/* ==================== Theme Toggle ==================== */

function initThemeToggle() {
    var btn = document.getElementById('theme-toggle');
    var currentTheme = localStorage.getItem('thesmith-theme') || 'light';

    function updateButton() {
        if (document.documentElement.getAttribute('data-theme') === 'dark') {
            btn.textContent = '\u2600';
            btn.setAttribute('aria-label', 'Switch to light mode');
        } else {
            btn.textContent = '\uD83C\uDF19';
            btn.setAttribute('aria-label', 'Switch to dark mode');
        }
    }

    updateButton();

    btn.addEventListener('click', function() {
        var isDark = document.documentElement.getAttribute('data-theme') === 'dark';
        if (isDark) {
            document.documentElement.removeAttribute('data-theme');
            localStorage.setItem('thesmith-theme', 'light');
        } else {
            document.documentElement.setAttribute('data-theme', 'dark');
            localStorage.setItem('thesmith-theme', 'dark');
        }
        updateButton();
    });
}

/* ==================== Upload Flow ==================== */

var uploadAreaOriginalHTML = '';

function uploadFile() {
    var fileInput = document.getElementById('file-input');
    var uploadBtn = document.getElementById('upload-btn');
    var statusBanner = document.getElementById('status-banner');
    var loadingSkeleton = document.getElementById('loading-skeleton');
    var resultsContainer = document.getElementById('results-container');
    var emptyState = document.getElementById('empty-state');

    if (!fileInput || !fileInput.files.length) {
        alert('Please select a file first.');
        return;
    }

    uploadBtn.disabled = true;
    statusBanner.className = 'status-banner processing';
    statusBanner.textContent = 'Uploading and processing...';
    loadingSkeleton.style.display = 'block';
    resultsContainer.classList.remove('visible');
    emptyState.style.display = 'none';

    var formData = new FormData();
    formData.append('file', fileInput.files[0]);

    fetch('/upload', { method: 'POST', body: formData })
        .then(function(res) {
            return res.json().then(function(data) {
                if (!res.ok) throw new Error(data.error || 'Upload failed');
                return data;
            });
        })
        .then(function(uploadData) {
            return pollStatus(statusBanner);
        })
        .then(function() {
            return fetch('/results');
        })
        .then(function(res) {
            return res.json();
        })
        .then(function(data) {
            var loadingSkeleton = document.getElementById('loading-skeleton');
            loadingSkeleton.style.display = 'none';

            allResults = data.results || [];
            metadata = data.metadata || {};

            if (allResults.length === 0) {
                document.getElementById('empty-state').style.display = 'block';
                document.getElementById('results-container').classList.remove('visible');
                statusBanner.className = 'status-banner complete';
                statusBanner.textContent = 'Analysis complete \u2014 0 foreign sign-in events detected.';
                return;
            }

            renderDashboard();
            document.getElementById('results-container').classList.add('visible');
            collapseUploadArea();
            document.getElementById('intune-upload-area').classList.add('visible');
            document.getElementById('export-csv-btn').style.display = '';
            document.getElementById('jump-bar').classList.add('visible');
            initJumpBar();

            var bannerText = 'Analysis complete \u2014 ' + metadata.foreignEvents + ' foreign sign-in events detected.';
            if (metadata.truncationWarning) {
                bannerText = 'Warning: This file contains approximately 100,000 rows and may be truncated. Some sign-in events may be missing from the export. ' + bannerText;
            }
            statusBanner.className = 'status-banner complete';
            statusBanner.textContent = bannerText;
        })
        .catch(function(err) {
            var loadingSkeleton = document.getElementById('loading-skeleton');
            loadingSkeleton.style.display = 'none';
            statusBanner.className = 'status-banner error';
            statusBanner.textContent = 'Analysis failed \u2014 ' + err.message + '. Try uploading the file again. If the problem persists, check the PowerShell console for details.';
        })
        .then(function() {
            var uploadBtn = document.getElementById('upload-btn');
            if (uploadBtn) uploadBtn.disabled = false;
        });
}

function pollStatus(statusBanner) {
    return new Promise(function(resolve, reject) {
        var interval = setInterval(function() {
            fetch('/status')
                .then(function(res) { return res.json(); })
                .then(function(statusData) {
                    if (statusData.status === 'complete') {
                        clearInterval(interval);
                        resolve();
                    } else if (statusData.status === 'error') {
                        clearInterval(interval);
                        reject(new Error(statusData.error || 'Processing failed'));
                    } else {
                        var pct = statusData.totalRows > 0
                            ? Math.round((statusData.progress / statusData.totalRows) * 100)
                            : 0;
                        statusBanner.textContent = 'Processing... ' + statusData.progress + ' / ' + statusData.totalRows + ' rows (' + pct + '%)';
                    }
                })
                .catch(function(err) {
                    clearInterval(interval);
                    reject(err);
                });
        }, 1000);
    });
}

function collapseUploadArea() {
    var uploadArea = document.getElementById('upload-area');
    uploadAreaOriginalHTML = uploadArea.innerHTML;
    uploadArea.classList.add('collapsed');
    uploadArea.innerHTML = '<a href="#" id="reanalyze-link" style="color:var(--color-accent);text-decoration:none;font-weight:600">Analyze another file</a>';

    document.getElementById('reanalyze-link').addEventListener('click', function(e) {
        e.preventDefault();
        restoreUploadArea();
    });
}

function restoreUploadArea() {
    var uploadArea = document.getElementById('upload-area');
    uploadArea.classList.remove('collapsed');
    uploadArea.innerHTML = uploadAreaOriginalHTML;

    document.getElementById('results-container').classList.remove('visible');
    document.getElementById('jump-bar').classList.remove('visible');

    var statusBanner = document.getElementById('status-banner');
    statusBanner.className = 'status-banner';
    statusBanner.textContent = '';

    // Reset Intune upload area
    var intuneArea = document.getElementById('intune-upload-area');
    if (intuneArea) {
        intuneArea.classList.remove('visible', 'collapsed');
        intuneArea.innerHTML = '<h3>Upload Intune Device Export</h3>' +
            '<p>Optional. Upload an Intune device compliance CSV to correlate devices with foreign sign-in events.</p>' +
            '<input type="file" id="intune-file-input" accept=".csv">' +
            '<br>' +
            '<button class="btn-primary" id="intune-upload-btn">Correlate Devices</button>';
    }
    intuneLoaded = false;
    document.getElementById('export-csv-btn').style.display = 'none';

    // Re-bind upload button
    document.getElementById('upload-btn').addEventListener('click', uploadFile);
    document.getElementById('intune-upload-btn').addEventListener('click', uploadIntuneFile);
}

/* ==================== Intune Upload Flow ==================== */

function uploadIntuneFile() {
    var fileInput = document.getElementById('intune-file-input');
    var uploadBtn = document.getElementById('intune-upload-btn');
    var statusBanner = document.getElementById('status-banner');

    if (!fileInput || !fileInput.files.length) {
        alert('Please select an Intune CSV file first.');
        return;
    }

    uploadBtn.disabled = true;
    statusBanner.className = 'status-banner processing';
    statusBanner.textContent = 'Processing Intune device data...';

    var formData = new FormData();
    formData.append('file', fileInput.files[0]);

    fetch('/upload-intune', { method: 'POST', body: formData })
        .then(function(res) {
            return res.json().then(function(data) {
                if (!res.ok) throw new Error(data.error || 'Intune upload failed');
                return data;
            });
        })
        .then(function(data) {
            allResults = data.results || [];
            intuneLoaded = true;

            // Collapse Intune upload area
            var intuneArea = document.getElementById('intune-upload-area');
            var deviceCount = data.intuneData ? data.intuneData.deviceCount : 0;
            intuneArea.classList.add('collapsed');
            intuneArea.innerHTML = '<span>' + deviceCount + ' devices loaded from Intune export</span>';

            // Re-render tables with device data
            var userData = aggregateByUser(allResults);
            renderUserRollup(userData);
            renderEventsTable();

            statusBanner.className = 'status-banner complete';
            var correlatedUsers = data.intuneData ? data.intuneData.correlatedUsers : 0;
            statusBanner.textContent = 'Intune data loaded. ' + deviceCount + ' devices correlated across ' + correlatedUsers + ' users.';
        })
        .catch(function(err) {
            statusBanner.className = 'status-banner error';
            statusBanner.textContent = err.message.indexOf('Unrecognized') !== -1
                ? 'Unrecognized CSV format. Expected an Intune device compliance export with columns like Device name, UPN, and Compliance.'
                : 'Failed to process Intune file. Check that the file is a valid CSV and try again.';
        })
        .then(function() {
            var uploadBtn = document.getElementById('intune-upload-btn');
            if (uploadBtn) uploadBtn.disabled = false;
        });
}

/* ==================== Compliance Badge ==================== */

function renderComplianceBadge(state) {
    if (!state) return '--';
    var cssClass = 'unknown';
    if (state === 'Compliant') cssClass = 'compliant';
    else if (state === 'Non-compliant') cssClass = 'noncompliant';
    return '<span class="compliance-badge ' + cssClass + '">' + escapeHtml(state) + '</span>';
}

/* ==================== CSV Export ==================== */

function exportCsv() {
    var events = getFilteredSortedEvents();
    var columns = [
        'userPrincipalName', 'userDisplayName', 'ipAddress', 'country',
        'city', 'timestamp', 'appDisplayName', 'clientAppUsed',
        'isLegacyAuth', 'signInStatus', 'errorCode', 'riskLevel',
        'deviceName', 'deviceOS', 'complianceState'
    ];
    var header = columns.join(',');
    var rows = events.map(function(evt) {
        return columns.map(function(col) {
            var val = evt[col];
            if (val == null) val = '';
            val = String(val);
            if (val.indexOf(',') !== -1 || val.indexOf('"') !== -1 || val.indexOf('\n') !== -1) {
                val = '"' + val.replace(/"/g, '""') + '"';
            }
            return val;
        }).join(',');
    });
    var csv = header + '\n' + rows.join('\n');
    var blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    var url = URL.createObjectURL(blob);
    var a = document.createElement('a');
    a.href = url;
    a.download = 'thesmith-foreign-events.csv';
    a.click();
    URL.revokeObjectURL(url);
}

/* ==================== Data Aggregation ==================== */

function aggregateByCountry(results) {
    var counts = {};
    results.forEach(function(evt) {
        if (!counts[evt.country]) {
            counts[evt.country] = { code: evt.country, name: getCountryName(evt.country), count: 0 };
        }
        counts[evt.country].count++;
    });
    return Object.keys(counts)
        .map(function(k) { return counts[k]; })
        .sort(function(a, b) { return b.count - a.count; });
}

function aggregateByUser(results) {
    var users = {};
    results.forEach(function(evt) {
        if (!users[evt.userDisplayName]) {
            users[evt.userDisplayName] = {
                name: evt.userDisplayName,
                upn: evt.userPrincipalName,
                events: [],
                countries: {},
                minDate: evt.timestamp,
                maxDate: evt.timestamp,
                count: 0
            };
        }
        var u = users[evt.userDisplayName];
        u.events.push(evt);
        u.countries[evt.country] = true;
        u.count++;
        if (evt.timestamp < u.minDate) u.minDate = evt.timestamp;
        if (evt.timestamp > u.maxDate) u.maxDate = evt.timestamp;
    });
    return Object.keys(users)
        .map(function(k) {
            var u = users[k];
            u.countries = Object.keys(u.countries);
            return u;
        })
        .sort(function(a, b) { return b.count - a.count; });
}

/* ==================== Summary Rendering ==================== */

function renderDashboard() {
    var countryData = aggregateByCountry(allResults);
    var userData = aggregateByUser(allResults);
    renderHeroStats();
    renderCountryBars(countryData);
    renderUserBars(userData);
    renderUserRollup(userData);
    renderEventsTable();
}

function renderHeroStats() {
    document.getElementById('stat-events').textContent = metadata.foreignEvents;

    var countries = {};
    allResults.forEach(function(r) { countries[r.country] = true; });
    document.getElementById('stat-countries').textContent = Object.keys(countries).length;

    var users = {};
    allResults.forEach(function(r) { users[r.userDisplayName] = true; });
    document.getElementById('stat-users').textContent = Object.keys(users).length;
}

function renderCountryBars(data) {
    var container = document.getElementById('country-bars');
    var toggle = document.getElementById('country-toggle');
    var maxCount = data.length > 0 ? data[0].count : 1;
    var showAll = false;

    function render(limit) {
        var items = limit ? data.slice(0, limit) : data;
        container.innerHTML = items.map(function(d) {
            var pct = Math.round((d.count / maxCount) * 100);
            return '<li class="bar-item">' +
                '<div class="bar-fill" style="width:' + pct + '%"></div>' +
                '<span class="bar-label">' + escapeHtml(d.name) + '</span>' +
                '<span class="bar-count">' + d.count + '</span>' +
                '</li>';
        }).join('');
    }

    render(10);

    if (data.length > 10) {
        toggle.style.display = 'block';
        toggle.textContent = 'Show all ' + data.length + ' countries';
        toggle.onclick = function() {
            showAll = !showAll;
            if (showAll) {
                render(null);
                toggle.textContent = 'Show fewer';
            } else {
                render(10);
                toggle.textContent = 'Show all ' + data.length + ' countries';
            }
        };
    } else {
        toggle.style.display = 'none';
    }
}

function renderUserBars(data) {
    var container = document.getElementById('user-bars');
    var toggle = document.getElementById('user-toggle');
    var maxCount = data.length > 0 ? data[0].count : 1;
    var showAll = false;

    function render(limit) {
        var items = limit ? data.slice(0, limit) : data;
        container.innerHTML = items.map(function(d) {
            var pct = Math.round((d.count / maxCount) * 100);
            return '<li class="bar-item">' +
                '<div class="bar-fill" style="width:' + pct + '%"></div>' +
                '<span class="bar-label">' + escapeHtml(d.name) + '</span>' +
                '<span class="bar-count">' + d.count + '</span>' +
                '</li>';
        }).join('');
    }

    render(10);

    if (data.length > 10) {
        toggle.style.display = 'block';
        toggle.textContent = 'Show all ' + data.length + ' users';
        toggle.onclick = function() {
            showAll = !showAll;
            if (showAll) {
                render(null);
                toggle.textContent = 'Show fewer';
            } else {
                render(10);
                toggle.textContent = 'Show all ' + data.length + ' users';
            }
        };
    } else {
        toggle.style.display = 'none';
    }
}

/* ==================== Stub Functions (Plans 02 and 03) ==================== */

function renderUserRollup(userData) {
    var tbody = document.getElementById('user-rollup-body');
    var html = '';

    userData.forEach(function(user, index) {
        // Row 1: user summary row
        var countriesList = user.countries.map(function(c) { return getCountryName(c); }).join(', ');
        var dateRange = formatTimestamp(user.minDate);
        if (user.minDate !== user.maxDate) {
            dateRange += ' - ' + formatTimestamp(user.maxDate);
        }

        html += '<tr class="user-row" data-user-index="' + index + '">' +
            '<td><span class="chevron">\u25B6</span></td>' +
            '<td>' + escapeHtml(user.name) + '</td>' +
            '<td>' + user.count + '</td>' +
            '<td>' + escapeHtml(countriesList) + '</td>' +
            '<td>' + escapeHtml(dateRange) + '</td>' +
            '</tr>';

        // Row 2: expansion row with sub-table
        var sortedEvents = user.events.slice().sort(function(a, b) {
            return a.timestamp > b.timestamp ? -1 : a.timestamp < b.timestamp ? 1 : 0;
        });

        var subRows = sortedEvents.map(function(evt) {
            var protocolCell;
            if (evt.isLegacyAuth) {
                protocolCell = '<span class="legacy-badge">\u26A0 Legacy Auth</span>';
            } else {
                protocolCell = escapeHtml(evt.clientAppUsed);
            }
            var rowClass = evt.isLegacyAuth ? ' class="legacy-row"' : '';
            return '<tr' + rowClass + '>' +
                '<td>' + formatTimestamp(evt.timestamp) + '</td>' +
                '<td>' + escapeHtml(evt.ipAddress) + '</td>' +
                '<td>' + getCountryName(evt.country) + '</td>' +
                '<td>' + escapeHtml(evt.appDisplayName) + '</td>' +
                '<td>' + escapeHtml(evt.signInStatus) + '</td>' +
                '<td>' + protocolCell + '</td>' +
                '<td>' + escapeHtml(evt.deviceName || '--') + '</td>' +
                '<td>' + escapeHtml(evt.deviceOS || '--') + '</td>' +
                '<td>' + renderComplianceBadge(evt.complianceState) + '</td>' +
                '</tr>';
        }).join('');

        html += '<tr class="expansion-row" data-user-index="' + index + '">' +
            '<td colspan="5">' +
            '<table class="sub-table">' +
            '<thead><tr>' +
            '<th>Timestamp</th><th>IP</th><th>Country</th><th>App</th><th>Status</th><th>Protocol</th><th>Device</th><th>OS</th><th>Compliance</th>' +
            '</tr></thead>' +
            '<tbody>' + subRows + '</tbody>' +
            '</table>' +
            '</td>' +
            '</tr>';
    });

    tbody.innerHTML = html;

    // Accordion click handler via event delegation
    tbody.addEventListener('click', function(e) {
        var row = e.target.closest('tr.user-row');
        if (!row) return;
        var idx = row.getAttribute('data-user-index');
        var expansionRow = tbody.querySelector('tr.expansion-row[data-user-index="' + idx + '"]');
        if (expansionRow) {
            expansionRow.classList.toggle('visible');
            row.classList.toggle('expanded');
        }
    });
}

function renderEventsTable() {
    // Populate country dropdown from allResults
    var countrySelect = document.getElementById('filter-country');
    var existingValue = countrySelect.value;

    // Remove all options except the first "All Countries"
    while (countrySelect.options.length > 1) {
        countrySelect.remove(1);
    }

    // Collect unique country codes
    var countryCodes = {};
    allResults.forEach(function(evt) {
        if (evt.country) countryCodes[evt.country] = true;
    });

    // Sort by country name alphabetically and add options
    Object.keys(countryCodes)
        .sort(function(a, b) {
            return getCountryName(a).localeCompare(getCountryName(b));
        })
        .forEach(function(code) {
            var opt = document.createElement('option');
            opt.value = code;
            opt.textContent = getCountryName(code);
            countrySelect.appendChild(opt);
        });

    // Restore previous selection if still valid
    countrySelect.value = existingValue;

    // Render table body and sort arrows
    applyFiltersAndSort();
}

function getFilteredSortedEvents() {
    var results = allResults.slice();

    // Apply text search filter
    if (filterState.search) {
        var term = filterState.search.toLowerCase();
        results = results.filter(function(evt) {
            return (evt.userDisplayName && evt.userDisplayName.toLowerCase().indexOf(term) !== -1) ||
                   (evt.ipAddress && evt.ipAddress.toLowerCase().indexOf(term) !== -1) ||
                   (evt.userPrincipalName && evt.userPrincipalName.toLowerCase().indexOf(term) !== -1);
        });
    }

    // Apply country filter
    if (filterState.country) {
        results = results.filter(function(evt) {
            return evt.country === filterState.country;
        });
    }

    // Apply status filter
    if (filterState.status) {
        results = results.filter(function(evt) {
            return evt.signInStatus === filterState.status;
        });
    }

    // Apply date-from filter (parse to UTC epoch for offset-safe comparison)
    if (filterState.dateFrom) {
        var fromEpoch = new Date(filterState.dateFrom + 'T00:00:00Z').getTime();
        results = results.filter(function(evt) {
            return new Date(evt.timestamp).getTime() >= fromEpoch;
        });
    }

    // Apply date-to filter (include the full end day in UTC)
    if (filterState.dateTo) {
        var toEpoch = new Date(filterState.dateTo + 'T23:59:59.999Z').getTime();
        results = results.filter(function(evt) {
            return new Date(evt.timestamp).getTime() <= toEpoch;
        });
    }

    // Apply sort
    var comparator = createSortComparator(sortState.column, sortState.direction);
    results.sort(comparator);

    return results;
}

function applyFiltersAndSort() {
    var filtered = getFilteredSortedEvents();
    var tbody = document.getElementById('events-body');

    if (filtered.length === 0 && allResults.length > 0) {
        tbody.innerHTML = '<tr><td colspan="12" style="text-align:center;padding:24px">No events match the current filters.</td></tr>';
    } else {
        tbody.innerHTML = filtered.map(function(evt) {
            var rowClass = evt.isLegacyAuth ? ' class="legacy-row"' : '';
            var protocolCell;
            if (evt.isLegacyAuth) {
                protocolCell = '<span class="legacy-badge">\u26A0 Legacy Auth</span>';
            } else {
                protocolCell = escapeHtml(evt.clientAppUsed);
            }
            return '<tr' + rowClass + '>' +
                '<td>' + formatTimestamp(evt.timestamp) + '</td>' +
                '<td>' + escapeHtml(evt.userDisplayName) + '</td>' +
                '<td>' + escapeHtml(evt.ipAddress) + '</td>' +
                '<td>' + escapeHtml(getCountryName(evt.country)) + '</td>' +
                '<td>' + escapeHtml(evt.city || '') + '</td>' +
                '<td>' + escapeHtml(evt.appDisplayName) + '</td>' +
                '<td>' + protocolCell + '</td>' +
                '<td>' + escapeHtml(evt.signInStatus) + '</td>' +
                '<td>' + escapeHtml(evt.riskLevel || '') + '</td>' +
                '<td>' + escapeHtml(evt.deviceName || '--') + '</td>' +
                '<td>' + escapeHtml(evt.deviceOS || '--') + '</td>' +
                '<td>' + renderComplianceBadge(evt.complianceState) + '</td>' +
                '</tr>';
        }).join('');
    }

    // Update sort arrows on column headers
    var ths = document.querySelectorAll('#events-table thead th');
    ths.forEach(function(th) {
        var existing = th.querySelector('.sort-arrow');
        if (existing) existing.remove();

        var col = th.getAttribute('data-column');
        if (col && col === sortState.column) {
            var arrow = document.createElement('span');
            arrow.className = 'sort-arrow';
            arrow.textContent = sortState.direction === 'asc' ? '\u2191' : '\u2193';
            th.appendChild(arrow);
        }
    });
}

function initFilters() {
    var searchInput = document.getElementById('filter-search');
    var countrySelect = document.getElementById('filter-country');
    var statusSelect = document.getElementById('filter-status');
    var dateFromInput = document.getElementById('filter-date-from');
    var dateToInput = document.getElementById('filter-date-to');

    searchInput.addEventListener('input', debounce(function() {
        filterState.search = searchInput.value;
        applyFiltersAndSort();
    }, 200));

    countrySelect.addEventListener('change', function() {
        filterState.country = countrySelect.value;
        applyFiltersAndSort();
    });

    statusSelect.addEventListener('change', function() {
        filterState.status = statusSelect.value;
        applyFiltersAndSort();
    });

    dateFromInput.addEventListener('change', function() {
        filterState.dateFrom = dateFromInput.value;
        applyFiltersAndSort();
    });

    dateToInput.addEventListener('change', function() {
        filterState.dateTo = dateToInput.value;
        applyFiltersAndSort();
    });
}

function initSort() {
    var headers = document.querySelectorAll('#events-table thead th.sortable');
    headers.forEach(function(th) {
        th.addEventListener('click', function() {
            var col = th.getAttribute('data-column');
            if (sortState.column === col && sortState.direction === 'asc') {
                sortState.direction = 'desc';
            } else if (sortState.column === col && sortState.direction === 'desc') {
                sortState.column = 'timestamp';
                sortState.direction = 'desc';
            } else {
                sortState.column = col;
                sortState.direction = 'asc';
            }
            applyFiltersAndSort();
        });
    });
}

/* ==================== Jump Bar ==================== */

function initJumpBar() {
    var sections = ['section-summary', 'section-users', 'section-events'];
    var links = document.querySelectorAll('.jump-bar a');

    var observer = new IntersectionObserver(function(entries) {
        entries.forEach(function(entry) {
            if (entry.isIntersecting) {
                var id = entry.target.id;
                links.forEach(function(link) {
                    if (link.getAttribute('href') === '#' + id) {
                        link.classList.add('active');
                    } else {
                        link.classList.remove('active');
                    }
                });
            }
        });
    }, { threshold: 0.1 });

    sections.forEach(function(id) {
        var el = document.getElementById(id);
        if (el) observer.observe(el);
    });

    links.forEach(function(link) {
        link.addEventListener('click', function(e) {
            e.preventDefault();
            var targetId = this.getAttribute('href').substring(1);
            var target = document.getElementById(targetId);
            if (target) {
                target.scrollIntoView({ behavior: 'smooth' });
            }
        });
    });
}

/* ==================== Sort Comparator ==================== */

function createSortComparator(column, direction) {
    var dir = direction === 'asc' ? 1 : -1;
    return function(a, b) {
        var valA = a[column];
        var valB = b[column];
        if (valA == null) valA = '';
        if (valB == null) valB = '';
        if (typeof valA === 'string') {
            var cmp = valA.localeCompare(valB);
            return cmp === 0 ? 0 : cmp * dir;
        }
        return valA < valB ? -1 * dir : valA > valB ? 1 * dir : 0;
    };
}

/* ==================== Initialization ==================== */

document.addEventListener('DOMContentLoaded', function() {
    initThemeToggle();
    initFilters();
    initSort();
    document.getElementById('upload-btn').addEventListener('click', uploadFile);
    document.getElementById('intune-upload-btn').addEventListener('click', uploadIntuneFile);
    document.getElementById('export-csv-btn').addEventListener('click', exportCsv);
});
