BeforeAll {
    . "$PSScriptRoot/../lib/GeoLookup.ps1"
}

Describe 'GeoLookup' {

    BeforeAll {
        $fixtureDir = "$PSScriptRoot/fixtures"
        $result = Initialize-GeoDatabase -IPv4CsvPath "$fixtureDir/sample-ip2location-v4.csv" -IPv6CsvPath "$fixtureDir/sample-ip2location-v6.csv"
    }

    Context 'Initialize-GeoDatabase' -Tag 'Lookup' {

        It 'loads IPv4 CSV into sorted array with expected row count' {
            $result.IPv4Rows | Should -Be 9
        }

        It 'loads IPv6 CSV into sorted array with expected row count' {
            $result.IPv6Rows | Should -Be 7
        }
    }

    Context 'ConvertTo-IPNumber' -Tag 'Lookup' {

        It 'converts IPv4 "8.8.8.8" to decimal 134744072' {
            ConvertTo-IPNumber -IpAddress '8.8.8.8' | Should -Be 134744072
        }

        It 'converts IPv6 "2001:4860:4860::8888" to a positive decimal' {
            $num = ConvertTo-IPNumber -IpAddress '2001:4860:4860::8888'
            $num | Should -BeGreaterThan 0
            $num | Should -BeOfType [decimal]
        }

        It 'returns $null for invalid string "not-an-ip"' {
            ConvertTo-IPNumber -IpAddress 'not-an-ip' | Should -BeNullOrEmpty
        }
    }

    Context 'Test-PrivateIP' -Tag 'Lookup' {

        It 'returns $true for IPv4 private addresses' {
            Test-PrivateIP -IpString '10.0.0.1' | Should -BeTrue
            Test-PrivateIP -IpString '172.16.0.1' | Should -BeTrue
            Test-PrivateIP -IpString '192.168.1.1' | Should -BeTrue
        }

        It 'returns $true for loopback 127.0.0.1' {
            Test-PrivateIP -IpString '127.0.0.1' | Should -BeTrue
        }

        It 'returns $true for link-local 169.254.1.1' {
            Test-PrivateIP -IpString '169.254.1.1' | Should -BeTrue
        }

        It 'returns $true for IPv6 loopback ::1' -Tag 'IPv6' {
            Test-PrivateIP -IpString '::1' | Should -BeTrue
        }

        It 'returns $true for IPv6 ULA fc00::1' -Tag 'IPv6' {
            Test-PrivateIP -IpString 'fc00::1' | Should -BeTrue
        }

        It 'returns $true for IPv6 link-local fe80::1' -Tag 'IPv6' {
            Test-PrivateIP -IpString 'fe80::1' | Should -BeTrue
        }

        It 'returns $false for public IPv4 8.8.8.8' {
            Test-PrivateIP -IpString '8.8.8.8' | Should -BeFalse
        }

        It 'returns $false for public IPv4 203.0.113.1' {
            Test-PrivateIP -IpString '203.0.113.1' | Should -BeFalse
        }

        It 'returns $true for unparseable strings' {
            Test-PrivateIP -IpString 'garbage-text' | Should -BeTrue
        }
    }

    Context 'Find-Country' -Tag 'Lookup', 'IndependentLookup' {

        It 'returns "US" for known US IPv4 8.8.8.8' {
            Find-Country -IpAddress '8.8.8.8' | Should -Be 'US'
        }

        It 'returns "AU" for known AU IPv4 in 1.0.1.x range' {
            # 1.0.1.0 = 16778240 decimal, which is in the AU fixture range
            Find-Country -IpAddress '1.0.1.0' | Should -Be 'AU'
        }

        It 'returns $null for IP not in database range' {
            # 100.0.0.1 is not in any fixture range
            Find-Country -IpAddress '100.0.0.1' | Should -BeNullOrEmpty
        }

        It 'returns $null for private IPs' {
            Find-Country -IpAddress '192.168.1.1' | Should -BeNullOrEmpty
        }

        It 'returns correct country for IPv6 address' -Tag 'IPv6' {
            # 2001:4860:4860::8888 maps to the US range in the IPv6 fixture
            # Decimal: 42540488161975842760550356425300246536
            Find-Country -IpAddress '2001:4860:4860::8888' | Should -Be 'US'
        }
    }
}
