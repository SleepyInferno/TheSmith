# DetectionEngine.ps1 -- Foreign sign-in detection, deduplication, and legacy protocol flagging
# Exports: Invoke-DetectionEngine, Test-LegacyProtocol

$script:LegacyProtocols = @(
    'Exchange ActiveSync'
    'IMAP'
    'IMAP4'
    'POP'
    'POP3'
    'SMTP'
    'Authenticated SMTP'
    'MAPI'
    'Autodiscover'
    'Exchange Web Services'
    'Exchange Online PowerShell'
    'Other clients'
)

function Test-LegacyProtocol {
    <#
    .SYNOPSIS
        Checks if a client application string represents a legacy authentication protocol.
    .PARAMETER ClientApp
        The clientAppUsed value from an Entra sign-in record.
    .OUTPUTS
        $true if the client app is a known legacy protocol, $false otherwise.
    #>
    param(
        [string]$ClientApp
    )

    return ($ClientApp -in $script:LegacyProtocols)
}

function Invoke-DetectionEngine {
    <#
    .SYNOPSIS
        Processes parsed Entra sign-in records to identify foreign (non-US) sign-in events.
        Filters out US IPs, private IPs, null IPs. Deduplicates by correlationId.
        Flags legacy protocol usage.
    .PARAMETER Records
        Array of parsed sign-in record objects (from Import-EntraSignInLog output).
    .OUTPUTS
        PSCustomObject with .results (array of foreign events) and .metadata (processing counts).
    #>
    param(
        [PSCustomObject[]]$Records
    )

    $skippedNullIPs    = 0
    $skippedPrivateIPs = 0
    $duplicatesRemoved = 0
    $seenCorrelationIds = @{}
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($record in $Records) {
        # 1. Check for null or empty IP address
        if ($null -eq $record.ipAddress -or [string]::IsNullOrWhiteSpace($record.ipAddress)) {
            $skippedNullIPs++
            continue
        }

        # 2. Check for private/reserved IP
        if (Test-PrivateIP -IpString $record.ipAddress) {
            $skippedPrivateIPs++
            continue
        }

        # 3. Resolve country via GeoLookup
        $countryCode = Find-Country -IpAddress $record.ipAddress
        if ($null -eq $countryCode -or $countryCode -eq 'US') {
            continue
        }

        # 4. Deduplication by correlationId
        if ($seenCorrelationIds.ContainsKey($record.correlationId)) {
            $duplicatesRemoved++
            continue
        }
        $seenCorrelationIds[$record.correlationId] = $true

        # 5. Build result record with all required fields
        $resultRecord = [PSCustomObject]@{
            userPrincipalName = $record.userPrincipalName
            userDisplayName   = $record.userDisplayName
            ipAddress         = $record.ipAddress
            country           = $countryCode
            countryName       = $countryCode   # Set to code for now; can be enriched later
            city              = $record.locationCity
            timestamp         = $record.createdDateTime
            appDisplayName    = $record.appDisplayName
            clientAppUsed     = $record.clientAppUsed
            isLegacyAuth      = (Test-LegacyProtocol -ClientApp $record.clientAppUsed)
            signInStatus      = $record.signInStatus
            errorCode         = $record.errorCode
            riskLevel         = $record.riskLevel
            correlationId     = $record.correlationId
        }

        $results.Add($resultRecord)
    }

    return [PSCustomObject]@{
        results  = $results.ToArray()
        metadata = @{
            foreignEvents     = $results.Count
            skippedPrivateIPs = $skippedPrivateIPs
            skippedNullIPs    = $skippedNullIPs
            duplicatesRemoved = $duplicatesRemoved
        }
    }
}
