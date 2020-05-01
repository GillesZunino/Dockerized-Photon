<#
.SYNOPSIS
    Configures Photon.
.DESCRIPTION
    Main entry point for Photon configuration in a Windows container.
.INPUTS
.OUTPUTS
.NOTES
    Expects the following environment variables to be set:
    * PHOTON_ENDPOINT : the public DNS name, IP Address of the Photon Server. use '127.0.0.1' or 'localhost' for the local server
#>

# Constants - Capture the location of various executables and files
[bool] $enablePerformanceCounters = $true
[string] $PhotonSocketServerDirectoryRelativePath = ".\deploy\bin_Win64"
[string] $PhotonSocketServerExecutableName = "PhotonSocketServer"

# Derived constants - Ready to use paths to various executable and files 
[string] $PhotonSocketServerExecutableRelativePath = Join-Path -Path $PhotonSocketServerDirectoryRelativePath -ChildPath $PhotonSocketServerExecutableName


# Include configuration functions
. .\Configure-LoadBalancingApp.ps1


function Resolve-PhotonEndpoint([string] $photonEndpoint, [string] $nameServer, [int] $numberOfRetries, [int] $secondsBetweenRetries)
{
    [int] $retries = $numberOfRetries
    [int] $waitInSeconds = $secondsBetweenRetries

    do {
        try {
            Write-Host "Resolving '$endpoint'"
            $dnsEntry = Resolve-DnsName -Name $endpoint -Type A -Server $nameServer
            return $dnsEntry.IPAddress
        }
        catch {
            Write-Host "Error resolving DNS name: $_"

            $retries = $retries - 1
            if ($retries -le 0) {
                throw $_
            }

            Write-Host "Remaining attempts $retries"
            Write-Host "Sleeping $waitInSeconds(s)"
            Start-Sleep $waitInSeconds
        }
    } while ($true)
}

function Get-PhotonPublicIp([string] $photonEndpoint)
{
    # Special case for localhost - Bypass DNS resolution
    if ($endpoint -eq "localhost") {
        return "127.0.0.1"
    }

    # Special case for IP addresses - Bypass DNS resolution
    [System.Net.IPAddress] $ipAddress = $null
    if ([ipaddress]::TryParse($photonEndpoint, [ref] $ipAddress)) {
        return $photonEndpoint
    }

    # CloudFlare nameserver
    [string] $cloudFlareNameserver = "1.1.1.1"

    # Number of attempts to resolve the DNS endpoint of the container
    [int] $retries = 10

    # Current Azure Container Instance TTL on A records is 14
    [int] $waitInSeconds = 15
    
    # Resolve 'myip.opendns.com' against 'resolver1.opendns.com' will return our public IP
    Write-Host "Resolving 'myip.opendns.com' using nameserver 'resolver1.opendns.com'" 
    [string] $inferedIp = Resolve-PhotonEndpoint "myip.opendns.com" "resolver1.opendns.com" $retries $waitInSeconds
    if (![string]::IsNullOrEmpty($inferedIp)) {
        Write-Host "OpenDNS resolved my IP to '$inferedIp'"
        return $inferedIp
    } else {
        # When re-creating a container shortly after deleting it, the DNS name may still point to the previous IP
        # We keep on resolving the IP and waiting for TTL to expire until we get to a stable IP
        Write-Host "Waiting for public IP to stabilize"
        [string] $ip1 = $null
        [string] $ip2 = $null
        do {
            $ip1 = $null
            $ip2 = $null

            $ip1 = Resolve-PhotonEndpoint $photonEndpoint $cloudFlareNameserver $retries $waitInSeconds
            Start-Sleep $waitInSeconds
            $ip2 = Resolve-PhotonEndpoint $photonEndpoint $cloudFlareNameserver $retries $waitInSeconds

            Write-Host "Resolved '$photonEndpoint' to '$ip1' and '$ip2'"
        } while ([string]::IsNullOrEmpty($ip1) -or [string]::IsNullOrEmpty($ip2) -or ($ip1 -ne $ip2))

        return $ip1
    }
}

function Register-PerformanceCounters([bool] $registerPerformanceCounters)
{
    if ($registerPerformanceCounters) {
        Write-Host "Registering performance counters"
        $photonSocketServerProcess = Start-Process -FilePath $PhotonSocketServerExecutableRelativePath -ArgumentList "/installCounters" -WorkingDirectory $PhotonSocketServerDirectoryRelativePath -NoNewWindow -Wait -PassThru
        [int] $photonExitCode = $photonSocketServerProcess.ExitCode
        if ($photonExitCode -ne 0) {
            throw "Failed to register performance counters - PhotonSocketServer exited - $photonExitCode"
        }
    } else {
        Write-Host "Skipping performance counters registration"
    }
}

## ----------------------------------------------------------------------------------------------------------------------------

[string] $endpoint = $Env:PHOTON_ENDPOINT
Write-Host "DNS Name: $endpoint"

[string] $loadBalancerPublicIP = Get-PhotonPublicIp $endpoint
Write-Host "Public IP: $loadBalancerPublicIP"

Write-Host "Configuring LoadBalancing application"
Configure-LoadBalancingApp $loadBalancerPublicIP $enablePerformanceCounters

# Register Windows performance counters
Register-PerformanceCounters $enablePerformanceCounters

# Start PhotonSocketServer
Write-Host "Starting PhotonSocketServer"
[System.Diagnostics.ProcessStartInfo] $processInfo = New-Object System.Diagnostics.ProcessStartInfo
$processInfo.WorkingDirectory = $PhotonSocketServerDirectoryRelativePath
$processInfo.FileName = $PhotonSocketServerExecutableRelativePath
$processInfo.Arguments = "/run LoadBalancing"
$processInfo.RedirectStandardInput = $false
$processInfo.RedirectStandardOutput = $false
$processInfo.RedirectStandardError = $false
$processInfo.UseShellExecute = $false
[System.Diagnostics.Process] $photonProcess = New-Object System.Diagnostics.Process
$photonProcess.StartInfo = $processInfo
$photonProcess.Start() | Out-Null

[int] $photonProcessId = $photonProcess.Id
Write-Host "PhotonSocketServer has PID '$photonProcessId'"

# Become a loving parent of PhotonSocketServer.exe
Write-Host "Waiting for PhotonSocketServer to exit"
$photonProcess.WaitForExit()

# Throws when it exits so we can indicate the container terminated
[int] $photonExitCode = $photonProcess.ExitCode
Write-Host "PhotonSocketServer has exited with code '$photonExitCode'"
throw "PhotonSocketServer exited - $photonExitCode"