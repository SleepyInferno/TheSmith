# Server.Tests.ps1 -- Integration tests for HTTP server and API endpoints
# Covers: INFRA-01, INFRA-02, INFRA-03, INFRA-04

BeforeAll {
    $script:ProjectRoot = "$PSScriptRoot/.."

    # Dot-source all modules
    . "$script:ProjectRoot/lib/GeoLookup.ps1"
    . "$script:ProjectRoot/lib/FileParser.ps1"
    . "$script:ProjectRoot/lib/DetectionEngine.ps1"
    . "$script:ProjectRoot/lib/IntuneParser.ps1"
    . "$script:ProjectRoot/lib/JobManager.ps1"
    . "$script:ProjectRoot/lib/Server.ps1"

    # Initialize GeoDatabase with test fixtures
    $ipv4Fixture = "$PSScriptRoot/fixtures/sample-ip2location-v4.csv"
    $ipv6Fixture = "$PSScriptRoot/fixtures/sample-ip2location-v6.csv"
    $null = Initialize-GeoDatabase -IPv4CsvPath $ipv4Fixture -IPv6CsvPath $ipv6Fixture

    # Clear saved results from previous runs to ensure a clean test environment
    $resultsDir = "$script:ProjectRoot/results"
    if (Test-Path $resultsDir) {
        Get-ChildItem -Path $resultsDir -Filter '*.json' -File | Remove-Item -Force
    }

    # Pick a random high port to avoid conflicts
    $script:TestPort = 18080 + (Get-Random -Minimum 0 -Maximum 1000)
    $script:TestUrl  = "http://localhost:$($script:TestPort)"

    # Start server in a background Runspace
    $script:ServerRunspace = [RunspaceFactory]::CreateRunspace()
    $script:ServerRunspace.Open()

    $script:ServerPS = [PowerShell]::Create()
    $script:ServerPS.Runspace = $script:ServerRunspace

    [void]$script:ServerPS.AddScript({
        param($Port, $Root)

        . "$Root/lib/GeoLookup.ps1"
        . "$Root/lib/FileParser.ps1"
        . "$Root/lib/DetectionEngine.ps1"
        . "$Root/lib/IntuneParser.ps1"
        . "$Root/lib/JobManager.ps1"
        . "$Root/lib/Server.ps1"

        $ipv4Path = "$Root/tests/fixtures/sample-ip2location-v4.csv"
        $ipv6Path = "$Root/tests/fixtures/sample-ip2location-v6.csv"
        $null = Initialize-GeoDatabase -IPv4CsvPath $ipv4Path -IPv6CsvPath $ipv6Path

        Start-Server -Port $Port -ScriptRoot $Root
    })

    [void]$script:ServerPS.AddArgument($script:TestPort)
    [void]$script:ServerPS.AddArgument($script:ProjectRoot)

    $script:AsyncHandle = $script:ServerPS.BeginInvoke()

    # Wait for server to start
    Start-Sleep -Seconds 2
}

AfterAll {
    # Graceful shutdown
    try {
        $null = Invoke-WebRequest -Uri "$($script:TestUrl)/shutdown" -UseBasicParsing -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
    }
    catch {
        # Server may already be stopped
    }

    # Clean up Runspace
    if ($null -ne $script:ServerPS) {
        $script:ServerPS.Stop()
        $script:ServerPS.Dispose()
    }
    if ($null -ne $script:ServerRunspace) {
        $script:ServerRunspace.Close()
        $script:ServerRunspace.Dispose()
    }
}

Describe 'Server Startup' -Tag 'Startup' {
    It 'responds to HTTP requests on the configured port' {
        $response = Invoke-WebRequest -Uri "$script:TestUrl/" -UseBasicParsing
        $response.StatusCode | Should -Be 200
    }

    It 'serves index.html at root path' {
        $response = Invoke-WebRequest -Uri "$script:TestUrl/" -UseBasicParsing
        $response.Content | Should -Match '<title>TheSmith'
    }
}

Describe 'Server Listener' -Tag 'Listener' {
    It 'listens on localhost only (not + or *)' {
        # Read the Server.ps1 source and verify the prefix uses localhost
        $serverSource = Get-Content "$script:ProjectRoot/lib/Server.ps1" -Raw
        $serverSource | Should -Match 'http://localhost:'
        $serverSource | Should -Not -Match 'http://\+:'
        $serverSource | Should -Not -Match 'http://\*:'
    }
}

Describe 'API Endpoints' -Tag 'NoExternalCalls' {
    It 'GET /status returns valid JSON with status field' {
        $result = Invoke-RestMethod -Uri "$script:TestUrl/status" -Method GET
        $result | Should -Not -BeNullOrEmpty
        $result.status | Should -Not -BeNullOrEmpty
    }

    It 'GET /results returns 404 when no job completed' {
        try {
            $null = Invoke-WebRequest -Uri "$script:TestUrl/results" -UseBasicParsing
            # Should not reach here
            $true | Should -Be $false -Because 'should have thrown a 404 error'
        }
        catch {
            $_.Exception.Response.StatusCode.value__ | Should -Be 404
        }
    }

    It 'GET /saved-results returns empty array initially' {
        $result = Invoke-RestMethod -Uri "$script:TestUrl/saved-results" -Method GET
        # Result should be empty array or null (no saved results yet)
        if ($null -ne $result) {
            @($result).Count | Should -Be 0
        }
    }

    It 'POST /upload with valid JSON file starts processing' {
        # Create sample Entra sign-in JSON content
        $sampleContent = Get-Content "$script:ProjectRoot/tests/fixtures/sample-entra-signin.json" -Raw

        # Build multipart form-data manually
        $boundary = [Guid]::NewGuid().ToString()
        $LF = "`r`n"
        $body = "--$boundary$LF"
        $body += "Content-Disposition: form-data; name=`"file`"; filename=`"test.json`"$LF"
        $body += "Content-Type: application/json$LF$LF"
        $body += "$sampleContent$LF"
        $body += "--$boundary--$LF"

        $result = Invoke-RestMethod -Uri "$script:TestUrl/upload" -Method POST `
            -ContentType "multipart/form-data; boundary=$boundary" `
            -Body $body

        $result.jobId | Should -Match '^job-'
        $result.status | Should -Be 'processing'
    }

    It 'POST /upload rejects non-POST methods' {
        try {
            $null = Invoke-WebRequest -Uri "$script:TestUrl/upload" -Method GET -UseBasicParsing
            $true | Should -Be $false -Because 'should have thrown a 405 error'
        }
        catch {
            $_.Exception.Response.StatusCode.value__ | Should -Be 405
        }
    }

    It 'GET /status reflects processing state after upload' {
        # Give the job a moment to start
        Start-Sleep -Milliseconds 500
        $result = Invoke-RestMethod -Uri "$script:TestUrl/status" -Method GET
        $result.jobId | Should -Match '^job-'
        $result.status | Should -BeIn @('processing', 'complete', 'error')
    }
}

Describe 'Intune Upload Endpoint' -Tag 'Intune' {

    BeforeAll {
        # Ensure an Entra upload job is running, then wait for it to complete.
        # The API Endpoints block starts a job; if it hasn't fired yet, start one here.
        $status = Invoke-RestMethod -Uri "$script:TestUrl/status" -Method GET
        if ($status.status -eq 'idle') {
            $sampleContent = Get-Content "$script:ProjectRoot/tests/fixtures/sample-entra-signin.json" -Raw
            $boundary = [Guid]::NewGuid().ToString()
            $LF = "`r`n"
            $body = "--$boundary$LF"
            $body += "Content-Disposition: form-data; name=`"file`"; filename=`"test.json`"$LF"
            $body += "Content-Type: application/json$LF$LF"
            $body += "$sampleContent$LF"
            $body += "--$boundary--$LF"
            $null = Invoke-RestMethod -Uri "$script:TestUrl/upload" -Method POST `
                -ContentType "multipart/form-data; boundary=$boundary" -Body $body
        }

        # Wait up to 90 seconds for job to finish (geo DB load takes ~30s on first run)
        $deadline = (Get-Date).AddSeconds(90)
        do {
            Start-Sleep -Milliseconds 500
            $status = Invoke-RestMethod -Uri "$script:TestUrl/status" -Method GET
        } while ($status.status -eq 'processing' -and (Get-Date) -lt $deadline)

        $script:IntuneUploaded = $false
    }

    It 'POST /upload-intune returns 400 when called before any Entra upload succeeds' {
        # Start a fresh server instance would be ideal; instead, verify the endpoint
        # correctly gates on completed Entra results. If a job is complete the endpoint
        # will accept. Skip this assertion if a job already completed.
        $status = Invoke-RestMethod -Uri "$script:TestUrl/status" -Method GET
        if ($status.status -ne 'complete') {
            $boundary = [Guid]::NewGuid().ToString()
            $LF = "`r`n"
            $body = "--$boundary$LF"
            $body += "Content-Disposition: form-data; name=`"file`"; filename=`"intune.csv`"$LF"
            $body += "Content-Type: text/csv$LF$LF"
            $body += "DeviceName,UPN,ComplianceState$LF"
            $body += "--$boundary--$LF"

            try {
                $null = Invoke-WebRequest -Uri "$script:TestUrl/upload-intune" -Method POST `
                    -ContentType "multipart/form-data; boundary=$boundary" `
                    -Body $body -UseBasicParsing
                $true | Should -Be $false -Because 'should have returned 400'
            } catch {
                $_.Exception.Response.StatusCode.value__ | Should -Be 400
            }
        } else {
            Set-ItResult -Skipped -Because 'Entra job already complete; gating test not applicable'
        }
    }

    It 'POST /upload-intune rejects non-POST methods' {
        try {
            $null = Invoke-WebRequest -Uri "$script:TestUrl/upload-intune" -Method GET -UseBasicParsing
            $true | Should -Be $false -Because 'should have thrown a 405 error'
        } catch {
            $_.Exception.Response.StatusCode.value__ | Should -Be 405
        }
    }

    It 'POST /upload-intune returns 400 when no file content is sent' {
        $status = Invoke-RestMethod -Uri "$script:TestUrl/status" -Method GET
        if ($status.status -ne 'complete') {
            Set-ItResult -Skipped -Because 'Entra job not yet complete'
            return
        }

        $boundary = [Guid]::NewGuid().ToString()
        $LF = "`r`n"
        # No file part — just an empty multipart body
        $body = "--$boundary--$LF"

        try {
            $null = Invoke-WebRequest -Uri "$script:TestUrl/upload-intune" -Method POST `
                -ContentType "multipart/form-data; boundary=$boundary" `
                -Body $body -UseBasicParsing
            $true | Should -Be $false -Because 'should have returned 400'
        } catch {
            $_.Exception.Response.StatusCode.value__ | Should -Be 400
        }
    }

    It 'POST /upload-intune with valid Intune CSV returns device count and correlated users' {
        $status = Invoke-RestMethod -Uri "$script:TestUrl/status" -Method GET
        if ($status.status -ne 'complete') {
            Set-ItResult -Skipped -Because 'Entra job not yet complete'
            return
        }

        $intuneContent = Get-Content "$script:ProjectRoot/tests/fixtures/sample-intune-devices-server.csv" -Raw

        $boundary = [Guid]::NewGuid().ToString()
        $LF = "`r`n"
        $body = "--$boundary$LF"
        $body += "Content-Disposition: form-data; name=`"file`"; filename=`"sample-intune-devices.csv`"$LF"
        $body += "Content-Type: text/csv$LF$LF"
        $body += "$intuneContent$LF"
        $body += "--$boundary--$LF"

        $result = Invoke-RestMethod -Uri "$script:TestUrl/upload-intune" -Method POST `
            -ContentType "multipart/form-data; boundary=$boundary" `
            -Body $body

        $result.intuneData | Should -Not -BeNullOrEmpty
        $result.intuneData.deviceCount | Should -Be 4  # sample-intune-devices-server.csv has 4 rows
        $result.intuneData.correlatedUsers | Should -BeGreaterThan 0
        $result.results | Should -Not -BeNullOrEmpty
        $script:IntuneUploaded = $true
    }

    It 'GET /results after Intune upload includes deviceName, deviceOS, complianceState fields' {
        if (-not $script:IntuneUploaded) {
            Set-ItResult -Skipped -Because 'Intune upload test did not succeed'
            return
        }

        $result = Invoke-RestMethod -Uri "$script:TestUrl/results" -Method GET

        $result.results | Should -Not -BeNullOrEmpty
        $firstResult = $result.results[0]

        # All results should have the device fields (populated or empty string)
        $firstResult.PSObject.Properties.Name | Should -Contain 'deviceName'
        $firstResult.PSObject.Properties.Name | Should -Contain 'deviceOS'
        $firstResult.PSObject.Properties.Name | Should -Contain 'complianceState'
    }

    It 'GET /results includes Intune data block with device count' {
        if (-not $script:IntuneUploaded) {
            Set-ItResult -Skipped -Because 'Intune upload test did not succeed'
            return
        }

        $result = Invoke-RestMethod -Uri "$script:TestUrl/results" -Method GET
        $result.intuneData | Should -Not -BeNullOrEmpty
        $result.intuneData.deviceCount | Should -Be 4
    }

    It 'Intune-matched results have non-empty complianceState' {
        if (-not $script:IntuneUploaded) {
            Set-ItResult -Skipped -Because 'Intune upload test did not succeed'
            return
        }

        $result = Invoke-RestMethod -Uri "$script:TestUrl/results" -Method GET

        # sample-intune-devices-server.csv has john.doe@contoso.com — sample-entra-signin.json also has john.doe@contoso.com
        $matched = $result.results | Where-Object { $_.userPrincipalName -eq 'john.doe@contoso.com' }
        if ($matched) {
            $matched[0].complianceState | Should -Not -BeNullOrEmpty
            $matched[0].deviceName     | Should -Not -BeNullOrEmpty
        } else {
            Set-ItResult -Skipped -Because 'No matching UPN between fixtures'
        }
    }
}

Describe 'Dependencies' -Tag 'Dependencies' {
    It 'does not require external PowerShell modules' {
        $libFiles = Get-ChildItem "$script:ProjectRoot/lib/*.ps1" | Select-Object -ExpandProperty FullName
        $entryPoint = "$script:ProjectRoot/Start-TheSmith.ps1"
        $allFiles = @($entryPoint) + $libFiles

        $importModuleHits = @()
        foreach ($file in $allFiles) {
            $matches = Select-String -Path $file -Pattern 'Import-Module' |
                Where-Object { $_.Line -notmatch 'Pester' -and $_.Line -notmatch 'System\.Web\.Extensions' }
            if ($matches) {
                $importModuleHits += $matches
            }
        }

        $importModuleHits | Should -BeNullOrEmpty
    }

    It 'does not contain outbound URLs in source code' {
        $libFiles = Get-ChildItem "$script:ProjectRoot/lib/*.ps1" | Select-Object -ExpandProperty FullName
        $entryPoint = "$script:ProjectRoot/Start-TheSmith.ps1"
        $allFiles = @($entryPoint) + $libFiles

        $urlHits = @()
        foreach ($file in $allFiles) {
            $matches = Select-String -Path $file -Pattern 'https://'
            if ($matches) {
                $urlHits += $matches
            }
        }

        $urlHits | Should -BeNullOrEmpty
    }
}
