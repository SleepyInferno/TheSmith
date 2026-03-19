# JobManager.ps1 -- Runspace-based async job management with progress tracking
# Exports: Start-ProcessingJob, Get-JobStatus, Get-JobResults, Get-SavedResults

$script:CurrentJob = [hashtable]::Synchronized(@{
    Id          = $null
    Status      = 'idle'       # idle | processing | complete | error
    Progress    = 0
    TotalRows   = 0
    Error       = $null
    Results     = $null
    StartedAt   = $null
    CompletedAt = $null
    SourceFile  = $null
})
$script:Runspace    = $null
$script:PowerShell  = $null
$script:AsyncResult = $null

function Start-ProcessingJob {
    <#
    .SYNOPSIS
        Starts async file processing in a background Runspace.
    .PARAMETER FileContent
        The raw content of the uploaded file.
    .PARAMETER FileName
        The original filename (used for format detection and result naming).
    .OUTPUTS
        Job ID string (e.g., "job-20260319-143022").
    #>
    param(
        [Parameter(Mandatory)][string]$FileContent,
        [Parameter(Mandatory)][string]$FileName
    )

    # If a job is already processing, stop it
    if ($script:CurrentJob.Status -eq 'processing') {
        if ($null -ne $script:PowerShell) {
            $script:PowerShell.Stop()
            $script:PowerShell.Dispose()
        }
        if ($null -ne $script:Runspace) {
            $script:Runspace.Close()
            $script:Runspace.Dispose()
        }
    }

    # Generate job ID
    $jobId = "job-" + (Get-Date -Format 'yyyyMMdd-HHmmss')

    # Reset job state
    $script:CurrentJob.Id          = $jobId
    $script:CurrentJob.Status      = 'processing'
    $script:CurrentJob.Progress    = 0
    $script:CurrentJob.TotalRows   = 0
    $script:CurrentJob.Error       = $null
    $script:CurrentJob.Results     = $null
    $script:CurrentJob.StartedAt   = (Get-Date).ToString('o')
    $script:CurrentJob.CompletedAt = $null
    $script:CurrentJob.SourceFile  = $FileName

    # Resolve paths for dot-sourcing inside the Runspace
    $scriptRoot = $PSScriptRoot
    if ([string]::IsNullOrEmpty($scriptRoot)) {
        $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    # Go up one level from lib/ to project root
    $projectRoot = Split-Path -Parent $scriptRoot

    $ipv4Path = Join-Path $projectRoot 'data\IP2LOCATION-LITE-DB1.CSV'
    $ipv6Path = Join-Path $projectRoot 'data\IP2LOCATION-LITE-DB1.IPV6.CSV'

    # Create Runspace
    $script:Runspace = [RunspaceFactory]::CreateRunspace()
    $script:Runspace.Open()
    $script:Runspace.SessionStateProxy.SetVariable('JobState', $script:CurrentJob)

    # Create PowerShell instance
    $script:PowerShell = [PowerShell]::Create()
    $script:PowerShell.Runspace = $script:Runspace

    [void]$script:PowerShell.AddScript({
        param(
            [string]$FileContent,
            [string]$FileName,
            [string]$LibPath,
            [string]$IPv4CsvPath,
            [string]$IPv6CsvPath,
            [string]$ResultsDir
        )

        try {
            # Dot-source required modules
            . "$LibPath\FileParser.ps1"
            . "$LibPath\GeoLookup.ps1"
            . "$LibPath\DetectionEngine.ps1"

            # Initialize GeoDatabase inside the Runspace
            $null = Initialize-GeoDatabase -IPv4CsvPath $IPv4CsvPath -IPv6CsvPath $IPv6CsvPath

            # Parse the uploaded file
            $parseResult = Import-EntraSignInLog -Content $FileContent -FilePath $FileName

            $JobState.TotalRows = $parseResult.metadata.totalRows
            $JobState.Progress  = $parseResult.metadata.totalRows  # Parsing complete

            # Run detection engine
            $detectionResult = Invoke-DetectionEngine -Records $parseResult.records

            # Merge metadata
            $combinedResponse = @{
                jobId       = $JobState.Id
                status      = 'complete'
                processedAt = (Get-Date).ToString('o')
                metadata    = @{
                    totalRows          = $parseResult.metadata.totalRows
                    foreignEvents      = $detectionResult.metadata.foreignEvents
                    skippedPrivateIPs  = $detectionResult.metadata.skippedPrivateIPs
                    skippedNullIPs     = $detectionResult.metadata.skippedNullIPs
                    duplicatesRemoved  = $detectionResult.metadata.duplicatesRemoved
                    truncationWarning  = $parseResult.metadata.truncationWarning
                    sourceFile         = $FileName
                    sourceFormat       = $parseResult.metadata.sourceFormat
                }
                results     = $detectionResult.results
            }

            $jsonResults = $combinedResponse | ConvertTo-Json -Depth 5
            $JobState.Results = $jsonResults

            # Save results to disk
            if (-not (Test-Path $ResultsDir)) {
                New-Item -ItemType Directory -Path $ResultsDir -Force | Out-Null
            }
            $resultFile = Join-Path $ResultsDir "$($JobState.Id).json"
            [System.IO.File]::WriteAllText($resultFile, $jsonResults)

            $JobState.Status      = 'complete'
            $JobState.CompletedAt = (Get-Date).ToString('o')
        }
        catch {
            $JobState.Status = 'error'
            $JobState.Error  = $_.Exception.Message
        }
    })

    # Add arguments
    $libPath    = Join-Path $projectRoot 'lib'
    $resultsDir = Join-Path $projectRoot 'results'

    [void]$script:PowerShell.AddArgument($FileContent)
    [void]$script:PowerShell.AddArgument($FileName)
    [void]$script:PowerShell.AddArgument($libPath)
    [void]$script:PowerShell.AddArgument($ipv4Path)
    [void]$script:PowerShell.AddArgument($ipv6Path)
    [void]$script:PowerShell.AddArgument($resultsDir)

    $script:AsyncResult = $script:PowerShell.BeginInvoke()

    return $jobId
}

function Get-JobStatus {
    <#
    .SYNOPSIS
        Returns the current job status and progress.
    .OUTPUTS
        PSCustomObject with jobId, status, progress, totalRows, error, startedAt, completedAt.
    #>
    return [PSCustomObject]@{
        jobId       = $script:CurrentJob.Id
        status      = $script:CurrentJob.Status
        progress    = $script:CurrentJob.Progress
        totalRows   = $script:CurrentJob.TotalRows
        error       = $script:CurrentJob.Error
        startedAt   = $script:CurrentJob.StartedAt
        completedAt = $script:CurrentJob.CompletedAt
    }
}

function Get-JobResults {
    <#
    .SYNOPSIS
        Returns the completed job results as a JSON string.
    .OUTPUTS
        JSON string of results, or $null if no completed job.
    #>
    if ($script:CurrentJob.Status -ne 'complete') {
        return $null
    }
    return $script:CurrentJob.Results
}

function Set-EnrichedResults {
    <#
    .SYNOPSIS
        Updates stored job results with enriched (Intune-correlated) data.
    .PARAMETER JsonResults
        JSON string of enriched results.
    #>
    param(
        [Parameter(Mandatory)][string]$JsonResults
    )
    $script:CurrentJob.Results = $JsonResults
}

function Get-SavedResults {
    <#
    .SYNOPSIS
        Lists previously saved result files from the results/ directory.
    .OUTPUTS
        Array of objects with name, date, sizeKB properties.
    #>
    $scriptRoot = $PSScriptRoot
    if ([string]::IsNullOrEmpty($scriptRoot)) {
        $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
    $projectRoot = Split-Path -Parent $scriptRoot
    $resultsDir  = Join-Path $projectRoot 'results'

    if (-not (Test-Path $resultsDir)) {
        return @()
    }

    $files = Get-ChildItem -Path $resultsDir -Filter '*.json' -File -ErrorAction SilentlyContinue
    if (-not $files) {
        return @()
    }

    $savedResults = @()
    foreach ($f in $files) {
        $savedResults += [PSCustomObject]@{
            name   = $f.Name
            date   = $f.LastWriteTime.ToString('o')
            sizeKB = [math]::Round($f.Length / 1024, 1)
        }
    }

    return $savedResults
}
