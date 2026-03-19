BeforeAll {
    . "$PSScriptRoot/../lib/IntuneParser.ps1"
}

Describe 'IntuneParser' {
    Describe 'Import-IntuneDevices' -Tag 'Parse' {
        It 'parses Graph API format CSV into normalized device objects' {
            $csvContent = Get-Content "$PSScriptRoot/fixtures/sample-intune-devices.csv" -Raw
            $devices = Import-IntuneDevices -Content $csvContent
            $devices.Count | Should -Be 4
            $devices[0].userPrincipalName | Should -Be 'jdoe@contoso.com'
            $devices[0].deviceName | Should -Be 'DESKTOP-ABC123'
            $devices[0].os | Should -Be 'Windows'
            $devices[0].complianceState | Should -Be 'Compliant'
        }

        It 'parses Admin Center format CSV into normalized device objects' {
            $csvContent = Get-Content "$PSScriptRoot/fixtures/sample-intune-devices-admincenter.csv" -Raw
            $devices = Import-IntuneDevices -Content $csvContent
            $devices.Count | Should -Be 4
            $devices[0].userPrincipalName | Should -Be 'jdoe@contoso.com'
            $devices[0].deviceName | Should -Be 'DESKTOP-ABC123'
        }

        It 'normalizes compliance states correctly' {
            $csvContent = Get-Content "$PSScriptRoot/fixtures/sample-intune-devices.csv" -Raw
            $devices = Import-IntuneDevices -Content $csvContent
            # InGracePeriod -> Non-compliant
            $grace = $devices | Where-Object { $_.deviceName -eq 'PIXEL-GHI012' }
            $grace.complianceState | Should -Be 'Non-compliant'
        }

        It 'throws clear error for unrecognized CSV format' {
            { Import-IntuneDevices -Content "col1,col2,col3`nval1,val2,val3" } | Should -Throw '*Unrecognized*'
        }
    }

    Describe 'Merge-IntuneWithResults' -Tag 'Correlate' {
        It 'adds device fields to matching results by UPN' {
            $devices = @(
                [PSCustomObject]@{ userPrincipalName='jdoe@contoso.com'; deviceName='DESKTOP-ABC'; os='Windows'; complianceState='Compliant' }
            )
            $results = @(
                [PSCustomObject]@{ userPrincipalName='jdoe@contoso.com'; userDisplayName='Jane Doe'; ipAddress='1.2.3.4'; country='CN' }
            )
            $merged = Merge-IntuneWithResults -Devices $devices -Results $results
            $merged[0].deviceName | Should -Be 'DESKTOP-ABC'
            $merged[0].deviceOS | Should -Be 'Windows'
            $merged[0].complianceState | Should -Be 'Compliant'
        }

        It 'sets device fields to empty string when no UPN match' {
            $devices = @(
                [PSCustomObject]@{ userPrincipalName='other@contoso.com'; deviceName='OTHER-PC'; os='Windows'; complianceState='Compliant' }
            )
            $results = @(
                [PSCustomObject]@{ userPrincipalName='jdoe@contoso.com'; userDisplayName='Jane Doe'; ipAddress='1.2.3.4'; country='CN' }
            )
            $merged = Merge-IntuneWithResults -Devices $devices -Results $results
            $merged[0].deviceName | Should -Be ''
            $merged[0].complianceState | Should -Be ''
        }

        It 'uses worst compliance state when user has multiple devices' -Tag 'Correlate' {
            $devices = @(
                [PSCustomObject]@{ userPrincipalName='jdoe@contoso.com'; deviceName='DESKTOP-ABC'; os='Windows'; complianceState='Compliant' },
                [PSCustomObject]@{ userPrincipalName='jdoe@contoso.com'; deviceName='IPHONE-XYZ'; os='iOS'; complianceState='Non-compliant' }
            )
            $results = @(
                [PSCustomObject]@{ userPrincipalName='jdoe@contoso.com'; userDisplayName='Jane Doe'; ipAddress='1.2.3.4'; country='CN' }
            )
            $merged = Merge-IntuneWithResults -Devices $devices -Results $results
            $merged[0].complianceState | Should -Be 'Non-compliant'
            $merged[0].deviceName | Should -Be 'IPHONE-XYZ'
            $merged[0].deviceOS | Should -Be 'iOS'
        }
    }

    Describe 'Build-CsvExportRow' -Tag 'Export' {
        It 'produces CSV row string with all required fields' {
            $evt = [PSCustomObject]@{
                userPrincipalName='jdoe@contoso.com'; userDisplayName='Jane Doe';
                ipAddress='1.2.3.4'; country='CN'; city='Beijing';
                timestamp='2026-03-18T08:23:11Z'; appDisplayName='Office 365';
                clientAppUsed='Browser'; isLegacyAuth=$false;
                signInStatus='Success'; errorCode='0'; riskLevel='none';
                deviceName='DESKTOP-ABC'; deviceOS='Windows'; complianceState='Compliant'
            }
            $row = Build-CsvExportRow -Event $evt
            $row | Should -Match 'jdoe@contoso.com'
            $row | Should -Match 'Compliant'
        }

        It 'properly escapes fields containing commas' {
            $evt = [PSCustomObject]@{
                userPrincipalName='jdoe@contoso.com'; userDisplayName='Doe, Jane';
                ipAddress='1.2.3.4'; country='CN'; city='Beijing';
                timestamp='2026-03-18T08:23:11Z'; appDisplayName='Office 365';
                clientAppUsed='Browser'; isLegacyAuth=$false;
                signInStatus='Success'; errorCode='0'; riskLevel='none';
                deviceName=''; deviceOS=''; complianceState=''
            }
            $row = Build-CsvExportRow -Event $evt
            $row | Should -Match '"Doe, Jane"'
        }
    }
}
