# DetectionEngine.Tests.ps1 - Unit tests for foreign sign-in detection engine
# Tests: foreign detection, deduplication, legacy protocol flagging, field extraction

BeforeAll {
    . "$PSScriptRoot/../lib/GeoLookup.ps1"
    . "$PSScriptRoot/../lib/FileParser.ps1"
    . "$PSScriptRoot/../lib/DetectionEngine.ps1"
}

Describe 'Test-LegacyProtocol' {
    It 'Returns $true for IMAP' {
        Test-LegacyProtocol -ClientApp 'IMAP' | Should -BeTrue
    }

    It 'Returns $true for POP' {
        Test-LegacyProtocol -ClientApp 'POP' | Should -BeTrue
    }

    It 'Returns $true for SMTP' {
        Test-LegacyProtocol -ClientApp 'SMTP' | Should -BeTrue
    }

    It 'Returns $true for Exchange ActiveSync' {
        Test-LegacyProtocol -ClientApp 'Exchange ActiveSync' | Should -BeTrue
    }

    It 'Returns $true for MAPI' {
        Test-LegacyProtocol -ClientApp 'MAPI' | Should -BeTrue
    }

    It 'Returns $false for Browser' {
        Test-LegacyProtocol -ClientApp 'Browser' | Should -BeFalse
    }

    It 'Returns $false for Mobile Apps and Desktop clients' {
        Test-LegacyProtocol -ClientApp 'Mobile Apps and Desktop clients' | Should -BeFalse
    }

    It 'Returns $false for empty string' {
        Test-LegacyProtocol -ClientApp '' | Should -BeFalse
    }
}

Describe 'Invoke-DetectionEngine' -Tag 'ForeignDetect' {
    BeforeAll {
        Mock Find-Country {
            param($IpAddress)
            switch ($IpAddress) {
                '203.0.113.42' { return 'CN' }
                '8.8.8.8'      { return 'US' }
                '198.51.100.5' { return 'RU' }
                default        { return $null }
            }
        }
        Mock Test-PrivateIP { return $false }

        $script:TestRecords = @(
            [PSCustomObject]@{
                userPrincipalName       = 'john.doe@contoso.com'
                userDisplayName         = 'John Doe'
                ipAddress               = '203.0.113.42'
                createdDateTime         = '2026-03-18T08:15:00Z'
                appDisplayName          = 'Microsoft Office 365'
                clientAppUsed           = 'Browser'
                correlationId           = 'corr-001'
                signInStatus            = 'Success'
                errorCode               = 0
                failureReason           = $null
                locationCity            = 'Beijing'
                locationCountryOrRegion = 'CN'
                riskLevel               = 'low'
            },
            [PSCustomObject]@{
                userPrincipalName       = 'jane.smith@contoso.com'
                userDisplayName         = 'Jane Smith'
                ipAddress               = '8.8.8.8'
                createdDateTime         = '2026-03-18T09:00:00Z'
                appDisplayName          = 'Microsoft Office 365'
                clientAppUsed           = 'Browser'
                correlationId           = 'corr-002'
                signInStatus            = 'Success'
                errorCode               = 0
                failureReason           = $null
                locationCity            = 'Mountain View'
                locationCountryOrRegion = 'US'
                riskLevel               = 'none'
            },
            [PSCustomObject]@{
                userPrincipalName       = 'bob@contoso.com'
                userDisplayName         = 'Bob'
                ipAddress               = $null
                createdDateTime         = '2026-03-18T10:00:00Z'
                appDisplayName          = 'Exchange Online'
                clientAppUsed           = 'SMTP'
                correlationId           = 'corr-003'
                signInStatus            = 'Failure'
                errorCode               = 50126
                failureReason           = 'Invalid credentials'
                locationCity            = $null
                locationCountryOrRegion = $null
                riskLevel               = 'medium'
            },
            [PSCustomObject]@{
                userPrincipalName       = 'alice@contoso.com'
                userDisplayName         = 'Alice'
                ipAddress               = '198.51.100.5'
                createdDateTime         = '2026-03-18T11:00:00Z'
                appDisplayName          = 'SharePoint Online'
                clientAppUsed           = 'Mobile Apps and Desktop clients'
                correlationId           = 'corr-004'
                signInStatus            = 'Success'
                errorCode               = 0
                failureReason           = $null
                locationCity            = 'Moscow'
                locationCountryOrRegion = 'RU'
                riskLevel               = 'low'
            },
            [PSCustomObject]@{
                userPrincipalName       = 'charlie@contoso.com'
                userDisplayName         = 'Charlie'
                ipAddress               = ''
                createdDateTime         = '2026-03-18T12:00:00Z'
                appDisplayName          = 'Exchange Online'
                clientAppUsed           = 'Browser'
                correlationId           = 'corr-005'
                signInStatus            = 'Success'
                errorCode               = 0
                failureReason           = $null
                locationCity            = $null
                locationCountryOrRegion = $null
                riskLevel               = 'none'
            },
            [PSCustomObject]@{
                userPrincipalName       = 'duplicate@contoso.com'
                userDisplayName         = 'Duplicate User'
                ipAddress               = '203.0.113.42'
                createdDateTime         = '2026-03-18T08:16:00Z'
                appDisplayName          = 'Microsoft Office 365'
                clientAppUsed           = 'Browser'
                correlationId           = 'corr-001'
                signInStatus            = 'Success'
                errorCode               = 0
                failureReason           = $null
                locationCity            = 'Beijing'
                locationCountryOrRegion = 'CN'
                riskLevel               = 'low'
            },
            [PSCustomObject]@{
                userPrincipalName       = 'legacy@contoso.com'
                userDisplayName         = 'Legacy User'
                ipAddress               = '203.0.113.42'
                createdDateTime         = '2026-03-18T13:00:00Z'
                appDisplayName          = 'Exchange Online'
                clientAppUsed           = 'IMAP'
                correlationId           = 'corr-006'
                signInStatus            = 'Success'
                errorCode               = 0
                failureReason           = $null
                locationCity            = 'Shanghai'
                locationCountryOrRegion = 'CN'
                riskLevel               = 'high'
            }
        )

        $script:Result = Invoke-DetectionEngine -Records $script:TestRecords
    }

    It 'Returns only non-US records' {
        $script:Result.results | ForEach-Object {
            $_.country | Should -Not -Be 'US'
        }
    }

    It 'Excludes US IP records from results' {
        $script:Result.results | Where-Object { $_.ipAddress -eq '8.8.8.8' } | Should -BeNullOrEmpty
    }

    It 'Excludes records with null ipAddress' {
        $script:Result.results | Where-Object { $_.userPrincipalName -eq 'bob@contoso.com' } | Should -BeNullOrEmpty
    }

    It 'Excludes records with empty ipAddress' {
        $script:Result.results | Where-Object { $_.userPrincipalName -eq 'charlie@contoso.com' } | Should -BeNullOrEmpty
    }

    It 'Counts skipped null IPs in metadata' {
        $script:Result.metadata.skippedNullIPs | Should -Be 2
    }
}

Describe 'Invoke-DetectionEngine' -Tag 'ForeignDetect' {
    Context 'Private IP handling' {
        BeforeAll {
            Mock Find-Country { return 'CN' }
            Mock Test-PrivateIP {
                param($IpString)
                if ($IpString -eq '10.0.0.1') { return $true }
                return $false
            }

            $privateRecords = @(
                [PSCustomObject]@{
                    userPrincipalName       = 'private@contoso.com'
                    userDisplayName         = 'Private User'
                    ipAddress               = '10.0.0.1'
                    createdDateTime         = '2026-03-18T14:00:00Z'
                    appDisplayName          = 'Exchange Online'
                    clientAppUsed           = 'Browser'
                    correlationId           = 'corr-priv-001'
                    signInStatus            = 'Success'
                    errorCode               = 0
                    failureReason           = $null
                    locationCity            = $null
                    locationCountryOrRegion = $null
                    riskLevel               = 'none'
                }
            )

            $script:PrivateResult = Invoke-DetectionEngine -Records $privateRecords
        }

        It 'Excludes private IP records from results' {
            $script:PrivateResult.results | Should -HaveCount 0
        }

        It 'Counts skipped private IPs in metadata' {
            $script:PrivateResult.metadata.skippedPrivateIPs | Should -Be 1
        }
    }
}

Describe 'Invoke-DetectionEngine' -Tag 'Dedup' {
    BeforeAll {
        Mock Find-Country { return 'CN' }
        Mock Test-PrivateIP { return $false }

        $dedupRecords = @(
            [PSCustomObject]@{
                userPrincipalName       = 'user1@contoso.com'
                userDisplayName         = 'User One'
                ipAddress               = '203.0.113.42'
                createdDateTime         = '2026-03-18T08:15:00Z'
                appDisplayName          = 'Microsoft Office 365'
                clientAppUsed           = 'Browser'
                correlationId           = 'dup-corr-001'
                signInStatus            = 'Success'
                errorCode               = 0
                failureReason           = $null
                locationCity            = 'Beijing'
                locationCountryOrRegion = 'CN'
                riskLevel               = 'low'
            },
            [PSCustomObject]@{
                userPrincipalName       = 'user1@contoso.com'
                userDisplayName         = 'User One'
                ipAddress               = '203.0.113.42'
                createdDateTime         = '2026-03-18T08:16:00Z'
                appDisplayName          = 'Microsoft Office 365'
                clientAppUsed           = 'Browser'
                correlationId           = 'dup-corr-001'
                signInStatus            = 'Failure'
                errorCode               = 50076
                failureReason           = 'MFA required'
                locationCity            = 'Beijing'
                locationCountryOrRegion = 'CN'
                riskLevel               = 'low'
            },
            [PSCustomObject]@{
                userPrincipalName       = 'user2@contoso.com'
                userDisplayName         = 'User Two'
                ipAddress               = '198.51.100.5'
                createdDateTime         = '2026-03-18T09:00:00Z'
                appDisplayName          = 'SharePoint Online'
                clientAppUsed           = 'Browser'
                correlationId           = 'dup-corr-002'
                signInStatus            = 'Success'
                errorCode               = 0
                failureReason           = $null
                locationCity            = 'Moscow'
                locationCountryOrRegion = 'RU'
                riskLevel               = 'none'
            }
        )

        $script:DedupResult = Invoke-DetectionEngine -Records $dedupRecords
    }

    It 'Collapses duplicate correlationIds to first occurrence' {
        $script:DedupResult.results | Should -HaveCount 2
    }

    It 'Keeps the first occurrence of a duplicate correlationId' {
        $first = $script:DedupResult.results | Where-Object { $_.correlationId -eq 'dup-corr-001' }
        $first.signInStatus | Should -Be 'Success'
    }

    It 'Reports duplicatesRemoved count in metadata' {
        $script:DedupResult.metadata.duplicatesRemoved | Should -Be 1
    }
}

Describe 'Invoke-DetectionEngine' -Tag 'Legacy' {
    BeforeAll {
        Mock Find-Country { return 'CN' }
        Mock Test-PrivateIP { return $false }

        $legacyRecords = @(
            [PSCustomObject]@{
                userPrincipalName       = 'imap-user@contoso.com'
                userDisplayName         = 'IMAP User'
                ipAddress               = '203.0.113.42'
                createdDateTime         = '2026-03-18T08:15:00Z'
                appDisplayName          = 'Exchange Online'
                clientAppUsed           = 'IMAP'
                correlationId           = 'leg-001'
                signInStatus            = 'Success'
                errorCode               = 0
                failureReason           = $null
                locationCity            = 'Beijing'
                locationCountryOrRegion = 'CN'
                riskLevel               = 'high'
            },
            [PSCustomObject]@{
                userPrincipalName       = 'browser-user@contoso.com'
                userDisplayName         = 'Browser User'
                ipAddress               = '198.51.100.5'
                createdDateTime         = '2026-03-18T09:00:00Z'
                appDisplayName          = 'Microsoft Office 365'
                clientAppUsed           = 'Browser'
                correlationId           = 'leg-002'
                signInStatus            = 'Success'
                errorCode               = 0
                failureReason           = $null
                locationCity            = 'Moscow'
                locationCountryOrRegion = 'RU'
                riskLevel               = 'none'
            }
        )

        $script:LegacyResult = Invoke-DetectionEngine -Records $legacyRecords
    }

    It 'Sets isLegacyAuth to $true for IMAP client' {
        $imapRecord = $script:LegacyResult.results | Where-Object { $_.clientAppUsed -eq 'IMAP' }
        $imapRecord.isLegacyAuth | Should -BeTrue
    }

    It 'Sets isLegacyAuth to $false for Browser client' {
        $browserRecord = $script:LegacyResult.results | Where-Object { $_.clientAppUsed -eq 'Browser' }
        $browserRecord.isLegacyAuth | Should -BeFalse
    }
}

Describe 'Invoke-DetectionEngine' -Tag 'FieldExtraction' {
    BeforeAll {
        Mock Find-Country { return 'CN' }
        Mock Test-PrivateIP { return $false }

        $fieldRecords = @(
            [PSCustomObject]@{
                userPrincipalName       = 'field-test@contoso.com'
                userDisplayName         = 'Field Test User'
                ipAddress               = '203.0.113.42'
                createdDateTime         = '2026-03-18T08:15:00Z'
                appDisplayName          = 'Microsoft Office 365'
                clientAppUsed           = 'Exchange ActiveSync'
                correlationId           = 'field-001'
                signInStatus            = 'Success'
                errorCode               = 0
                failureReason           = $null
                locationCity            = 'Beijing'
                locationCountryOrRegion = 'CN'
                riskLevel               = 'low'
            }
        )

        $script:FieldResult = Invoke-DetectionEngine -Records $fieldRecords
        $script:FirstRecord = $script:FieldResult.results[0]
    }

    It 'Has userPrincipalName field' {
        $script:FirstRecord.userPrincipalName | Should -Be 'field-test@contoso.com'
    }

    It 'Has userDisplayName field' {
        $script:FirstRecord.userDisplayName | Should -Be 'Field Test User'
    }

    It 'Has ipAddress field' {
        $script:FirstRecord.ipAddress | Should -Be '203.0.113.42'
    }

    It 'Has country field from GeoLookup' {
        $script:FirstRecord.country | Should -Be 'CN'
    }

    It 'Has countryName field' {
        $script:FirstRecord | Get-Member -Name 'countryName' -MemberType NoteProperty | Should -Not -BeNullOrEmpty
    }

    It 'Has city field from Entra location data' {
        $script:FirstRecord.city | Should -Be 'Beijing'
    }

    It 'Has timestamp field' {
        $script:FirstRecord.timestamp | Should -Be '2026-03-18T08:15:00Z'
    }

    It 'Has appDisplayName field' {
        $script:FirstRecord.appDisplayName | Should -Be 'Microsoft Office 365'
    }

    It 'Has clientAppUsed field' {
        $script:FirstRecord.clientAppUsed | Should -Be 'Exchange ActiveSync'
    }

    It 'Has isLegacyAuth field set to $true for Exchange ActiveSync' {
        $script:FirstRecord.isLegacyAuth | Should -BeTrue
    }

    It 'Has signInStatus field' {
        $script:FirstRecord.signInStatus | Should -Be 'Success'
    }

    It 'Has errorCode field' {
        $script:FirstRecord.errorCode | Should -Be 0
    }

    It 'Has riskLevel field' {
        $script:FirstRecord.riskLevel | Should -Be 'low'
    }

    It 'Has correlationId field' {
        $script:FirstRecord.correlationId | Should -Be 'field-001'
    }
}

Describe 'Invoke-DetectionEngine Metadata' -Tag 'ForeignDetect' {
    BeforeAll {
        Mock Find-Country {
            param($IpAddress)
            switch ($IpAddress) {
                '203.0.113.42' { return 'CN' }
                '8.8.8.8'      { return 'US' }
                default        { return $null }
            }
        }
        Mock Test-PrivateIP {
            param($IpString)
            if ($IpString -eq '10.0.0.1') { return $true }
            return $false
        }

        $metaRecords = @(
            [PSCustomObject]@{
                userPrincipalName = 'foreign@contoso.com'; userDisplayName = 'Foreign'
                ipAddress = '203.0.113.42'; createdDateTime = '2026-03-18T08:15:00Z'
                appDisplayName = 'Office'; clientAppUsed = 'Browser'
                correlationId = 'meta-001'; signInStatus = 'Success'; errorCode = 0
                failureReason = $null; locationCity = 'Beijing'; locationCountryOrRegion = 'CN'; riskLevel = 'low'
            },
            [PSCustomObject]@{
                userPrincipalName = 'us@contoso.com'; userDisplayName = 'US User'
                ipAddress = '8.8.8.8'; createdDateTime = '2026-03-18T09:00:00Z'
                appDisplayName = 'Office'; clientAppUsed = 'Browser'
                correlationId = 'meta-002'; signInStatus = 'Success'; errorCode = 0
                failureReason = $null; locationCity = 'NYC'; locationCountryOrRegion = 'US'; riskLevel = 'none'
            },
            [PSCustomObject]@{
                userPrincipalName = 'null-ip@contoso.com'; userDisplayName = 'Null IP'
                ipAddress = $null; createdDateTime = '2026-03-18T10:00:00Z'
                appDisplayName = 'Office'; clientAppUsed = 'Browser'
                correlationId = 'meta-003'; signInStatus = 'Success'; errorCode = 0
                failureReason = $null; locationCity = $null; locationCountryOrRegion = $null; riskLevel = 'none'
            },
            [PSCustomObject]@{
                userPrincipalName = 'private@contoso.com'; userDisplayName = 'Private'
                ipAddress = '10.0.0.1'; createdDateTime = '2026-03-18T11:00:00Z'
                appDisplayName = 'Office'; clientAppUsed = 'Browser'
                correlationId = 'meta-004'; signInStatus = 'Success'; errorCode = 0
                failureReason = $null; locationCity = $null; locationCountryOrRegion = $null; riskLevel = 'none'
            },
            [PSCustomObject]@{
                userPrincipalName = 'dup@contoso.com'; userDisplayName = 'Dup'
                ipAddress = '203.0.113.42'; createdDateTime = '2026-03-18T08:16:00Z'
                appDisplayName = 'Office'; clientAppUsed = 'Browser'
                correlationId = 'meta-001'; signInStatus = 'Success'; errorCode = 0
                failureReason = $null; locationCity = 'Beijing'; locationCountryOrRegion = 'CN'; riskLevel = 'low'
            }
        )

        $script:MetaResult = Invoke-DetectionEngine -Records $metaRecords
    }

    It 'Returns foreignEvents count in metadata' {
        $script:MetaResult.metadata.foreignEvents | Should -Be 1
    }

    It 'Returns skippedNullIPs count in metadata' {
        $script:MetaResult.metadata.skippedNullIPs | Should -Be 1
    }

    It 'Returns skippedPrivateIPs count in metadata' {
        $script:MetaResult.metadata.skippedPrivateIPs | Should -Be 1
    }

    It 'Returns duplicatesRemoved count in metadata' {
        $script:MetaResult.metadata.duplicatesRemoved | Should -Be 1
    }
}
