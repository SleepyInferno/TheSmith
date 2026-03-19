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

    // Re-bind upload button
    document.getElementById('upload-btn').addEventListener('click', uploadFile);
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
                '</tr>';
        }).join('');

        html += '<tr class="expansion-row" data-user-index="' + index + '">' +
            '<td colspan="5">' +
            '<table class="sub-table">' +
            '<thead><tr>' +
            '<th>Timestamp</th><th>IP</th><th>Country</th><th>App</th><th>Status</th><th>Protocol</th>' +
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
    /* TODO: Plan 03 */
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
    document.getElementById('upload-btn').addEventListener('click', uploadFile);
});
