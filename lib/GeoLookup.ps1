# GeoLookup.ps1 -- IP-to-country resolution via IP2Location CSV binary search
# Exports: Initialize-GeoDatabase, Find-Country, ConvertTo-IPNumber, Test-PrivateIP

$script:GeoDbV4 = $null
$script:GeoDbV6 = $null

function Initialize-GeoDatabase {
    <#
    .SYNOPSIS
        Loads IP2Location LITE DB1 CSV files into memory for binary search lookup.
    .PARAMETER IPv4CsvPath
        Path to the IPv4 IP2Location CSV file.
    .PARAMETER IPv6CsvPath
        Path to the IPv6 IP2Location CSV file.
    .OUTPUTS
        Hashtable with IPv4Rows and IPv6Rows counts.
    #>
    param(
        [Parameter(Mandatory)][string]$IPv4CsvPath,
        [Parameter(Mandatory)][string]$IPv6CsvPath
    )

    # Load IPv4 database
    $script:GeoDbV4 = [System.Collections.Generic.List[PSCustomObject]]::new()
    $reader = [System.IO.StreamReader]::new($IPv4CsvPath)
    try {
        while (($line = $reader.ReadLine()) -ne $null) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line -replace '"', '' -split ','
            if ($parts.Count -lt 4) { continue }
            $script:GeoDbV4.Add([PSCustomObject]@{
                IpFrom      = [decimal]$parts[0]
                IpTo        = [decimal]$parts[1]
                CountryCode = $parts[2]
                CountryName = $parts[3]
            })
        }
    }
    finally {
        $reader.Close()
        $reader.Dispose()
    }

    # Load IPv6 database
    $script:GeoDbV6 = [System.Collections.Generic.List[PSCustomObject]]::new()
    $reader = [System.IO.StreamReader]::new($IPv6CsvPath)
    try {
        while (($line = $reader.ReadLine()) -ne $null) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line -replace '"', '' -split ','
            if ($parts.Count -lt 4) { continue }
            $script:GeoDbV6.Add([PSCustomObject]@{
                IpFrom      = [bigint]::Parse($parts[0])
                IpTo        = [bigint]::Parse($parts[1])
                CountryCode = $parts[2]
                CountryName = $parts[3]
            })
        }
    }
    finally {
        $reader.Close()
        $reader.Dispose()
    }

    return @{
        IPv4Rows = $script:GeoDbV4.Count
        IPv6Rows = $script:GeoDbV6.Count
    }
}

function ConvertTo-IPNumber {
    <#
    .SYNOPSIS
        Converts an IP address string to its decimal numeric representation.
    .PARAMETER IpAddress
        The IP address string to convert.
    .OUTPUTS
        [decimal] numeric value, or $null if invalid.
    #>
    param(
        [Parameter(Mandatory)][string]$IpAddress
    )

    $ip = [System.Net.IPAddress]::None
    if (-not [System.Net.IPAddress]::TryParse($IpAddress, [ref]$ip)) {
        return $null
    }

    $bytes = $ip.GetAddressBytes()

    if ($ip.AddressFamily -eq 'InterNetwork') {
        # IPv4: 4 bytes to 32-bit number
        return [decimal](
            [uint32]$bytes[0] * 16777216 +
            [uint32]$bytes[1] * 65536 +
            [uint32]$bytes[2] * 256 +
            [uint32]$bytes[3]
        )
    }
    elseif ($ip.AddressFamily -eq 'InterNetworkV6') {
        # IPv6: 16 bytes to 128-bit number (bigint needed -- decimal overflows at 128-bit)
        [bigint]$num = [bigint]::Zero
        foreach ($b in $bytes) {
            $num = $num * 256 + $b
        }
        return $num
    }

    return $null
}

function Test-PrivateIP {
    <#
    .SYNOPSIS
        Checks if an IP address is private, loopback, link-local, or unparseable.
    .PARAMETER IpString
        The IP address string to check.
    .OUTPUTS
        $true if private/reserved/unparseable, $false if public.
    #>
    param(
        [Parameter(Mandatory)][string]$IpString
    )

    $ip = [System.Net.IPAddress]::None
    if (-not [System.Net.IPAddress]::TryParse($IpString, [ref]$ip)) {
        return $true  # Unparseable = treat as private/skip
    }

    $bytes = $ip.GetAddressBytes()

    if ($ip.AddressFamily -eq 'InterNetwork') {
        # 10.0.0.0/8
        if ($bytes[0] -eq 10) { return $true }
        # 172.16.0.0/12
        if ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) { return $true }
        # 192.168.0.0/16
        if ($bytes[0] -eq 192 -and $bytes[1] -eq 168) { return $true }
        # 127.0.0.0/8 (loopback)
        if ($bytes[0] -eq 127) { return $true }
        # 169.254.0.0/16 (link-local)
        if ($bytes[0] -eq 169 -and $bytes[1] -eq 254) { return $true }
        return $false
    }
    elseif ($ip.AddressFamily -eq 'InterNetworkV6') {
        # ::1 (loopback)
        if ($ip.Equals([System.Net.IPAddress]::IPv6Loopback)) { return $true }
        # fc00::/7 (ULA)
        if (($bytes[0] -band 0xFE) -eq 0xFC) { return $true }
        # fe80::/10 (link-local)
        if ($bytes[0] -eq 0xFE -and ($bytes[1] -band 0xC0) -eq 0x80) { return $true }
        return $false
    }

    return $true  # Unknown address family = skip
}

function Find-Country {
    <#
    .SYNOPSIS
        Resolves an IP address to its country code using IP2Location binary search.
    .PARAMETER IpAddress
        The IP address string to look up.
    .OUTPUTS
        Country code string (e.g., "US"), or $null if private/not found/invalid.
    #>
    param(
        [Parameter(Mandatory)][string]$IpAddress
    )

    # Skip private/reserved IPs
    if (Test-PrivateIP -IpString $IpAddress) {
        return $null
    }

    # Convert to numeric
    $ipNum = ConvertTo-IPNumber -IpAddress $IpAddress
    if ($null -eq $ipNum) {
        return $null
    }

    # Determine which database to search
    $ip = [System.Net.IPAddress]::None
    [void][System.Net.IPAddress]::TryParse($IpAddress, [ref]$ip)

    if ($ip.AddressFamily -eq 'InterNetwork') {
        $db = $script:GeoDbV4
    }
    elseif ($ip.AddressFamily -eq 'InterNetworkV6') {
        $db = $script:GeoDbV6
    }
    else {
        return $null
    }

    if ($null -eq $db -or $db.Count -eq 0) {
        return $null
    }

    # Binary search
    $low = 0
    $high = $db.Count - 1
    while ($low -le $high) {
        $mid = [math]::Floor(($low + $high) / 2)
        if ($ipNum -lt $db[$mid].IpFrom) {
            $high = $mid - 1
        }
        elseif ($ipNum -gt $db[$mid].IpTo) {
            $low = $mid + 1
        }
        else {
            return $db[$mid].CountryCode
        }
    }

    return $null
}
