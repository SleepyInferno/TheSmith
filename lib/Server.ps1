# Server.ps1 -- HttpListener setup, route dispatch, request/response handling
# Exports: Start-Server

function Send-JsonResponse {
    <#
    .SYNOPSIS
        Sends a JSON response with proper headers.
    .PARAMETER Response
        The HttpListenerResponse object.
    .PARAMETER Body
        The JSON string to send.
    .PARAMETER StatusCode
        HTTP status code (default 200).
    #>
    param(
        [System.Net.HttpListenerResponse]$Response,
        [string]$Body,
        [int]$StatusCode = 200
    )

    $Response.ContentType = 'application/json; charset=utf-8'
    $Response.StatusCode  = $StatusCode
    $Response.Headers.Add('Access-Control-Allow-Origin', '*')

    $buffer = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $Response.ContentLength64 = $buffer.Length
    $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Response.OutputStream.Close()
}

function Handle-Upload {
    <#
    .SYNOPSIS
        Handles POST /upload -- parses multipart form-data and starts processing job.
    #>
    param(
        $Context,
        [string]$ScriptRoot
    )

    $request  = $Context.Request
    $response = $Context.Response

    # Only accept POST
    if ($request.HttpMethod -ne 'POST') {
        $errorBody = @{ error = 'Method not allowed. Use POST.' } | ConvertTo-Json
        Send-JsonResponse -Response $response -Body $errorBody -StatusCode 405
        return
    }

    try {
        # Parse multipart form-data
        $contentType = $request.ContentType
        $boundary = ($contentType -replace '.*boundary=', '') -replace '"', ''

        $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
        $body = $reader.ReadToEnd()
        $reader.Close()

        # Split on boundary and find file part
        $parts = $body -split "--$([regex]::Escape($boundary))"
        $fileContent = $null
        $filename = 'upload.json'

        foreach ($part in $parts) {
            if ($part -match 'filename="([^"]+)"') {
                $filename = $Matches[1]
                # File content starts after double CRLF
                $headerEnd = $part.IndexOf("`r`n`r`n")
                if ($headerEnd -ge 0) {
                    $fileContent = $part.Substring($headerEnd + 4)
                    # Trim trailing CRLF before next boundary
                    $fileContent = $fileContent.TrimEnd("`r`n")
                }
                break
            }
        }

        if ($null -eq $fileContent -or $fileContent.Length -eq 0) {
            $errorBody = @{ error = 'No file content found in upload. Please attach a JSON or CSV file.' } | ConvertTo-Json
            Send-JsonResponse -Response $response -Body $errorBody -StatusCode 400
            return
        }

        # Start processing job
        $jobId = Start-ProcessingJob -FileContent $fileContent -FileName $filename
        $responseBody = @{ jobId = $jobId; status = 'processing' } | ConvertTo-Json
        Send-JsonResponse -Response $response -Body $responseBody
    }
    catch {
        $errorBody = @{ error = "Upload failed: $($_.Exception.Message)" } | ConvertTo-Json
        Send-JsonResponse -Response $response -Body $errorBody -StatusCode 500
    }
}

function Handle-Status {
    <#
    .SYNOPSIS
        Handles GET /status -- returns current job progress.
    #>
    param($Context)

    $request  = $Context.Request
    $response = $Context.Response

    if ($request.HttpMethod -ne 'GET') {
        $errorBody = @{ error = 'Method not allowed. Use GET.' } | ConvertTo-Json
        Send-JsonResponse -Response $response -Body $errorBody -StatusCode 405
        return
    }

    $status = Get-JobStatus
    $responseBody = $status | ConvertTo-Json -Depth 3
    Send-JsonResponse -Response $response -Body $responseBody
}

function Handle-Results {
    <#
    .SYNOPSIS
        Handles GET /results -- returns completed job results.
    #>
    param($Context)

    $request  = $Context.Request
    $response = $Context.Response

    if ($request.HttpMethod -ne 'GET') {
        $errorBody = @{ error = 'Method not allowed. Use GET.' } | ConvertTo-Json
        Send-JsonResponse -Response $response -Body $errorBody -StatusCode 405
        return
    }

    $results = Get-JobResults
    if ($null -eq $results) {
        $currentStatus = Get-JobStatus
        $errorBody = @{
            error  = 'No completed results available'
            status = $currentStatus.status
        } | ConvertTo-Json
        Send-JsonResponse -Response $response -Body $errorBody -StatusCode 404
        return
    }

    # Results is already a JSON string from JobManager
    Send-JsonResponse -Response $response -Body $results
}

function Handle-SavedResults {
    <#
    .SYNOPSIS
        Handles GET /saved-results -- lists previously saved result files.
    #>
    param($Context)

    $response = $Context.Response

    $saved = Get-SavedResults
    $responseBody = $saved | ConvertTo-Json -Depth 3
    # Handle empty array edge case (ConvertTo-Json returns $null for empty array)
    if ($null -eq $responseBody) {
        $responseBody = '[]'
    }
    Send-JsonResponse -Response $response -Body $responseBody
}

function Handle-StaticFile {
    <#
    .SYNOPSIS
        Serves static files from the web/ directory.
    #>
    param(
        $Context,
        [string]$ScriptRoot
    )

    $request  = $Context.Request
    $response = $Context.Response
    $urlPath  = $request.Url.LocalPath

    # Default to index.html
    if ($urlPath -eq '/' -or [string]::IsNullOrEmpty($urlPath)) {
        $urlPath = '/index.html'
    }

    # Map to file path under web/
    $filePath = Join-Path $ScriptRoot "web$($urlPath -replace '/', '\')"

    if (-not (Test-Path $filePath)) {
        $response.StatusCode = 404
        $buffer = [System.Text.Encoding]::UTF8.GetBytes('404 Not Found')
        $response.ContentLength64 = $buffer.Length
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.OutputStream.Close()
        return
    }

    # Determine Content-Type
    $extension = [System.IO.Path]::GetExtension($filePath).ToLower()
    $contentType = switch ($extension) {
        '.html' { 'text/html; charset=utf-8' }
        '.js'   { 'application/javascript; charset=utf-8' }
        '.css'  { 'text/css; charset=utf-8' }
        '.json' { 'application/json; charset=utf-8' }
        '.png'  { 'image/png' }
        '.ico'  { 'image/x-icon' }
        '.svg'  { 'image/svg+xml' }
        default { 'application/octet-stream' }
    }

    $response.ContentType = $contentType
    $response.StatusCode  = 200

    $fileBytes = [System.IO.File]::ReadAllBytes($filePath)
    $response.ContentLength64 = $fileBytes.Length
    $response.OutputStream.Write($fileBytes, 0, $fileBytes.Length)
    $response.OutputStream.Close()
}

function Handle-Shutdown {
    <#
    .SYNOPSIS
        Handles GET /shutdown -- gracefully stops the server.
    #>
    param(
        $Context,
        [System.Net.HttpListener]$Listener
    )

    $response = $Context.Response
    $buffer = [System.Text.Encoding]::UTF8.GetBytes('Shutting down')
    $response.ContentType = 'text/plain'
    $response.StatusCode  = 200
    $response.ContentLength64 = $buffer.Length
    $response.OutputStream.Write($buffer, 0, $buffer.Length)
    $response.OutputStream.Close()

    $Listener.Stop()
}

function Start-Server {
    <#
    .SYNOPSIS
        Starts the HTTP server on the specified port and handles requests.
    .PARAMETER Port
        TCP port to listen on (default 8080).
    .PARAMETER ScriptRoot
        Root directory of the project (for resolving static files and modules).
    #>
    param(
        [int]$Port = 8080,
        [string]$ScriptRoot
    )

    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://localhost:$Port/")
    $listener.Start()

    Write-Host "TheSmith server running on http://localhost:$Port"

    try {
        while ($listener.IsListening) {
            $context  = $listener.GetContext()
            $request  = $context.Request
            $response = $context.Response

            try {
                switch -Wildcard ($request.Url.LocalPath) {
                    '/upload'        { Handle-Upload $context $ScriptRoot }
                    '/status'        { Handle-Status $context }
                    '/results'       { Handle-Results $context }
                    '/saved-results' { Handle-SavedResults $context }
                    '/shutdown'      { Handle-Shutdown $context $listener }
                    default          { Handle-StaticFile $context $ScriptRoot }
                }
            }
            catch {
                try {
                    $errorBody = @{ error = $_.Exception.Message } | ConvertTo-Json
                    Send-JsonResponse -Response $response -Body $errorBody -StatusCode 500
                }
                catch {
                    # Response may already be closed
                }
            }
        }
    }
    finally {
        $listener.Stop()
        $listener.Close()
    }
}
