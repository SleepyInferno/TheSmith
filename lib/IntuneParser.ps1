# IntuneParser.ps1 -- Intune device compliance CSV parsing, correlation, and CSV export
# Exports: Import-IntuneDevices, Merge-IntuneWithResults, Build-CsvExportRow, Get-CsvExportHeader

# Use case-sensitive dictionary to support variants like 'Device name' vs 'Device Name'
$intuneColumnMap = New-Object 'System.Collections.Generic.Dictionary[string,string]'
$intuneColumnMap.Add('DeviceName',          'deviceName')
$intuneColumnMap.Add('UPN',                 'userPrincipalName')
$intuneColumnMap.Add('ComplianceState',     'complianceState')
$intuneColumnMap.Add('OS',                  'os')
$intuneColumnMap.Add('OSVersion',           'osVersion')
$intuneColumnMap.Add('CompliantState',      'complianceState')
$intuneColumnMap.Add('Device name',         'deviceName')
$intuneColumnMap.Add('User principal name', 'userPrincipalName')
$intuneColumnMap.Add('Compliance',          'complianceState')
$intuneColumnMap.Add('Device Name',         'deviceName')
$intuneColumnMap.Add('UserPrincipalName',   'userPrincipalName')
$intuneColumnMap.Add('Operating system',    'os')
$intuneColumnMap.Add('OS version',          'osVersion')

function Normalize-ComplianceState {
    <#
    .SYNOPSIS
        Normalizes raw compliance state strings to one of: Compliant, Non-compliant, Unknown.
    #>
    param(
        [string]$RawState
    )

    if ([string]::IsNullOrWhiteSpace($RawState)) {
        return 'Unknown'
    }

    switch ($RawState.ToLower().Trim()) {
        'compliant'      { return 'Compliant' }
        'noncompliant'   { return 'Non-compliant' }
        'non-compliant'  { return 'Non-compliant' }
        'ingraceperiod'  { return 'Non-compliant' }
        'configmanager'  { return 'Unknown' }
        'unknown'        { return 'Unknown' }
        default          { return 'Unknown' }
    }
}

function Import-IntuneDevices {
    <#
    .SYNOPSIS
        Parses Intune device compliance CSV content (Graph API or Admin Center format)
        into normalized device objects.
    .PARAMETER Content
        Raw CSV content string.
    .OUTPUTS
        Array of PSCustomObject with userPrincipalName, deviceName, os, osVersion, complianceState.
    #>
    param(
        [Parameter(Mandatory)][string]$Content
    )

    $reader = [System.IO.StringReader]::new($Content)
    $headerLine = $reader.ReadLine()

    # Parse header
    $headers = $headerLine -split ','

    # Build column index -> normalized name mapping
    $indexMap = @{}
    for ($i = 0; $i -lt $headers.Count; $i++) {
        $header = $headers[$i].Trim()
        if ($intuneColumnMap.ContainsKey($header)) {
            $indexMap[$i] = $intuneColumnMap[$header]
        }
    }

    # Validate required columns
    $mappedFields = $indexMap.Values
    if ('userPrincipalName' -notin $mappedFields -or 'deviceName' -notin $mappedFields) {
        $reader.Close()
        throw "Unrecognized Intune CSV format. Expected columns like DeviceName, UPN, ComplianceState or Device name, User principal name, Compliance."
    }

    $devices = [System.Collections.Generic.List[PSCustomObject]]::new()

    while ($null -ne ($line = $reader.ReadLine())) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        $fields = $line -split ','

        # Build raw hashtable from mapped columns
        $raw = @{}
        foreach ($kvp in $indexMap.GetEnumerator()) {
            $idx = $kvp.Key
            $name = $kvp.Value
            $val = if ($idx -lt $fields.Count) { $fields[$idx].Trim() } else { '' }
            $raw[$name] = $val
        }

        $device = [PSCustomObject]@{
            userPrincipalName = $raw['userPrincipalName']
            deviceName        = $raw['deviceName']
            os                = if ($raw.ContainsKey('os')) { $raw['os'] } else { '' }
            osVersion         = if ($raw.ContainsKey('osVersion')) { $raw['osVersion'] } else { '' }
            complianceState   = Normalize-ComplianceState -RawState $raw['complianceState']
        }

        $devices.Add($device)
    }

    $reader.Close()

    return ,$devices.ToArray()
}

function Merge-IntuneWithResults {
    <#
    .SYNOPSIS
        Correlates Intune device data with Entra sign-in results by UPN.
        For users with multiple devices, surfaces the worst compliance state.
    .PARAMETER Devices
        Array of device objects from Import-IntuneDevices.
    .PARAMETER Results
        Array of result objects from the detection engine.
    .OUTPUTS
        Modified results array with deviceName, deviceOS, and complianceState added.
    #>
    param(
        [Parameter(Mandatory)][array]$Devices,
        [Parameter(Mandatory)][array]$Results
    )

    # Build hashtable grouping devices by UPN (lowercase)
    $devicesByUpn = @{}
    foreach ($device in $Devices) {
        $key = $device.userPrincipalName.ToLower()
        if (-not $devicesByUpn.ContainsKey($key)) {
            $devicesByUpn[$key] = @()
        }
        $devicesByUpn[$key] += $device
    }

    # Compliance severity ranking (higher = worse)
    $severityMap = @{
        'Non-compliant' = 3
        'Unknown'       = 2
        'Compliant'     = 1
        ''              = 0
    }

    foreach ($result in $Results) {
        $upnKey = $result.userPrincipalName.ToLower()
        $userDevices = $devicesByUpn[$upnKey]

        if ($userDevices -and $userDevices.Count -gt 0) {
            # Find device with worst compliance state
            $worstDevice = $null
            $worstSeverity = -1

            foreach ($dev in $userDevices) {
                $severity = $severityMap[$dev.complianceState]
                if ($null -eq $severity) { $severity = 0 }
                if ($severity -gt $worstSeverity) {
                    $worstSeverity = $severity
                    $worstDevice = $dev
                }
            }

            $result | Add-Member -NotePropertyName 'deviceName' -NotePropertyValue $worstDevice.deviceName -Force
            $result | Add-Member -NotePropertyName 'deviceOS' -NotePropertyValue $worstDevice.os -Force
            $result | Add-Member -NotePropertyName 'complianceState' -NotePropertyValue $worstDevice.complianceState -Force
        }
        else {
            $result | Add-Member -NotePropertyName 'deviceName' -NotePropertyValue '' -Force
            $result | Add-Member -NotePropertyName 'deviceOS' -NotePropertyValue '' -Force
            $result | Add-Member -NotePropertyName 'complianceState' -NotePropertyValue '' -Force
        }
    }

    return ,$Results
}

function Get-CsvExportHeader {
    <#
    .SYNOPSIS
        Returns the CSV header row for export.
    #>
    return 'userPrincipalName,userDisplayName,ipAddress,country,city,timestamp,appDisplayName,clientAppUsed,isLegacyAuth,signInStatus,errorCode,riskLevel,deviceName,deviceOS,complianceState'
}

function Build-CsvExportRow {
    <#
    .SYNOPSIS
        Builds an RFC 4180 compliant CSV row string from an event object.
    .PARAMETER Event
        PSCustomObject with all required event fields.
    .OUTPUTS
        CSV row string.
    #>
    param(
        [Parameter(Mandatory)][PSCustomObject]$Event
    )

    $columns = @(
        'userPrincipalName', 'userDisplayName', 'ipAddress', 'country', 'city',
        'timestamp', 'appDisplayName', 'clientAppUsed', 'isLegacyAuth',
        'signInStatus', 'errorCode', 'riskLevel',
        'deviceName', 'deviceOS', 'complianceState'
    )

    $values = @()
    foreach ($col in $columns) {
        $val = $Event.$col
        if ($null -eq $val) { $val = '' }
        $val = [string]$val

        # RFC 4180: escape fields containing comma, double-quote, or newline
        if ($val -match '[,"\r\n]') {
            $val = '"' + ($val -replace '"', '""') + '"'
        }

        $values += $val
    }

    return ($values -join ',')
}
