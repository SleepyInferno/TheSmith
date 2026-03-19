# FileParser.ps1 - Entra sign-in log parser
# Supports JSON (bare array and Microsoft wrapper) and CSV formats
# Uses JavaScriptSerializer for JSON to avoid PS 5.1 depth limits
# Uses StreamReader for CSV to handle large files efficiently

Add-Type -AssemblyName System.Web.Extensions

function Detect-FileFormat {
    <#
    .SYNOPSIS
        Auto-detects whether a file is JSON or CSV based on extension and content peek.
    .PARAMETER FilePath
        Path to the file (used for extension check).
    .PARAMETER Content
        Optional content string for content-peek fallback when extension is ambiguous.
    #>
    param(
        [string]$FilePath,
        [string]$Content
    )

    # Check extension first
    if ($FilePath -match '\.json$') {
        return 'json'
    }
    if ($FilePath -match '\.csv$') {
        return 'csv'
    }

    # Fallback: peek at content
    if ($Content) {
        $peek = $Content.Substring(0, [Math]::Min(1024, $Content.Length)).TrimStart()
        if ($peek.StartsWith('[') -or $peek.StartsWith('{')) {
            return 'json'
        }
        # Check if first line looks like a CSV header (contains commas)
        $firstLine = ($peek -split "`n")[0]
        if ($firstLine -match ',') {
            return 'csv'
        }
    }
    elseif ($FilePath -and (Test-Path $FilePath)) {
        $reader = [System.IO.StreamReader]::new($FilePath)
        $peek = $reader.ReadLine()
        $reader.Close()
        if ($peek) {
            $trimmed = $peek.TrimStart()
            if ($trimmed.StartsWith('[') -or $trimmed.StartsWith('{')) {
                return 'json'
            }
            if ($trimmed -match ',') {
                return 'csv'
            }
        }
    }

    return $null
}

function Import-EntraSignInLog {
    <#
    .SYNOPSIS
        Parses an Entra sign-in log file (JSON or CSV) into normalized record objects.
    .PARAMETER FilePath
        Path to the log file.
    .PARAMETER Content
        Optional content string (when content is already in memory from upload).
    .OUTPUTS
        PSCustomObject with .records (array) and .metadata (hashtable).
    #>
    param(
        [string]$FilePath,
        [string]$Content
    )

    # Read content if not provided
    if (-not $Content -and $FilePath -and (Test-Path $FilePath)) {
        $Content = [System.IO.File]::ReadAllText($FilePath)
    }

    $format = Detect-FileFormat -FilePath $FilePath -Content $Content

    switch ($format) {
        'json' {
            $records = Parse-EntraJson -JsonContent $Content
        }
        'csv' {
            $records = Parse-EntraCsv -CsvContent $Content
        }
        default {
            throw "Unable to detect file format for: $FilePath"
        }
    }

    $totalRows = $records.Count

    return [PSCustomObject]@{
        records  = $records
        metadata = @{
            totalRows          = $totalRows
            truncationWarning  = ($totalRows -ge 99000)
            sourceFormat       = $format
        }
    }
}

function Parse-EntraJson {
    <#
    .SYNOPSIS
        Parses Entra sign-in log JSON content (bare array or Microsoft wrapper).
    #>
    param(
        [string]$JsonContent
    )

    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $serializer.MaxJsonLength = [int]::MaxValue
    $serializer.RecursionLimit = 100

    $data = $serializer.DeserializeObject($JsonContent)

    # Handle Microsoft wrapper: { "value": [...] }
    if ($data -is [System.Collections.Generic.Dictionary[string,object]]) {
        if ($data.ContainsKey('value')) {
            $data = $data['value']
        }
    }

    $records = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($record in $data) {
        $ip = $record['ipAddress']
        if ($ip -eq '' -or $null -eq $ip) {
            $ip = $null
        }

        $status = $record['status']
        $location = $record['location']

        $errorCode = 0
        $failureReason = $null
        $signInStatus = 'Success'
        if ($status) {
            $errorCode = [int]$status['errorCode']
            $failureReason = $status['failureReason']
            if ($errorCode -ne 0) {
                $signInStatus = 'Failure'
            }
        }

        $city = $null
        $countryOrRegion = $null
        if ($location) {
            $city = $location['city']
            $countryOrRegion = $location['countryOrRegion']
        }

        $normalized = [PSCustomObject]@{
            userPrincipalName       = $record['userPrincipalName']
            userDisplayName         = $record['userDisplayName']
            ipAddress               = $ip
            createdDateTime         = $record['createdDateTime']
            appDisplayName          = $record['appDisplayName']
            clientAppUsed           = $record['clientAppUsed']
            correlationId           = $record['correlationId']
            signInStatus            = $signInStatus
            errorCode               = $errorCode
            failureReason           = $failureReason
            locationCity            = $city
            locationCountryOrRegion = $countryOrRegion
            riskLevel               = $record['riskLevelAggregated']
        }

        $records.Add($normalized)
    }

    return ,$records.ToArray()
}

function Parse-EntraCsv {
    <#
    .SYNOPSIS
        Parses Entra sign-in log CSV content with display-friendly column names.
    #>
    param(
        [string]$CsvContent
    )

    # Column name mappings: display-friendly -> normalized
    $columnMap = @{
        'Date (UTC)'               = 'createdDateTime'
        'CreatedDateTime'          = 'createdDateTime'
        'User principal name'      = 'userPrincipalName'
        'UserPrincipalName'        = 'userPrincipalName'
        'User display name'        = 'userDisplayName'
        'UserDisplayName'          = 'userDisplayName'
        'IP address'               = 'ipAddress'
        'IpAddress'                = 'ipAddress'
        'Application'              = 'appDisplayName'
        'AppDisplayName'           = 'appDisplayName'
        'Client app'               = 'clientAppUsed'
        'ClientAppUsed'            = 'clientAppUsed'
        'Correlation ID'           = 'correlationId'
        'CorrelationId'            = 'correlationId'
        'Status'                   = 'signInStatus'
        'Sign-in status'           = 'signInStatus'
        'Sign-in error code'       = 'errorCode'
        'ErrorCode'                = 'errorCode'
        'Failure reason'           = 'failureReason'
        'FailureReason'            = 'failureReason'
        'Location'                 = 'location'
        'Risk level (aggregate)'   = 'riskLevel'
        'RiskLevelAggregated'      = 'riskLevel'
    }

    $reader = [System.IO.StringReader]::new($CsvContent)
    $headerLine = $reader.ReadLine()

    # Parse header - split on comma (simple case, no quoted commas in Entra headers)
    $headers = $headerLine -split ','

    # Build column index -> normalized name mapping
    $indexMap = @{}
    for ($i = 0; $i -lt $headers.Count; $i++) {
        $header = $headers[$i].Trim()
        if ($columnMap.ContainsKey($header)) {
            $indexMap[$i] = $columnMap[$header]
        }
    }

    $records = [System.Collections.Generic.List[PSCustomObject]]::new()

    while ($null -ne ($line = $reader.ReadLine())) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        $fields = $line -split ','

        # Build a raw hashtable from mapped columns
        $raw = @{}
        foreach ($kvp in $indexMap.GetEnumerator()) {
            $idx = $kvp.Key
            $name = $kvp.Value
            $val = if ($idx -lt $fields.Count) { $fields[$idx].Trim() } else { '' }
            $raw[$name] = $val
        }

        # Normalize IP address
        $ip = $raw['ipAddress']
        if ([string]::IsNullOrWhiteSpace($ip)) {
            $ip = $null
        }

        # Handle location field (may be combined "City Country")
        $city = $null
        $countryOrRegion = $null
        if ($raw.ContainsKey('location') -and -not [string]::IsNullOrWhiteSpace($raw['location'])) {
            $locParts = $raw['location'] -split ' '
            if ($locParts.Count -ge 2) {
                $countryOrRegion = $locParts[-1]
                $city = ($locParts[0..($locParts.Count - 2)]) -join ' '
            }
            elseif ($locParts.Count -eq 1) {
                $city = $locParts[0]
            }
        }

        # Parse error code
        $errorCode = 0
        if ($raw.ContainsKey('errorCode') -and -not [string]::IsNullOrWhiteSpace($raw['errorCode'])) {
            $errorCode = [int]$raw['errorCode']
        }

        $normalized = [PSCustomObject]@{
            userPrincipalName       = $raw['userPrincipalName']
            userDisplayName         = $raw['userDisplayName']
            ipAddress               = $ip
            createdDateTime         = $raw['createdDateTime']
            appDisplayName          = $raw['appDisplayName']
            clientAppUsed           = $raw['clientAppUsed']
            correlationId           = $raw['correlationId']
            signInStatus            = $raw['signInStatus']
            errorCode               = $errorCode
            failureReason           = $raw['failureReason']
            locationCity            = $city
            locationCountryOrRegion = $countryOrRegion
            riskLevel               = $raw['riskLevel']
        }

        $records.Add($normalized)
    }

    $reader.Close()

    return ,$records.ToArray()
}
