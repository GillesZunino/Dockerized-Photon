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
[string] $PhotonRoot = ".\deploy"
[string] $PhotonSocketServerDirectoryRelativePath = ( Join-Path -Path $PhotonRoot -ChildPath "bin_Win64" )
[string] $PhotonSocketServerExecutableName = "PhotonSocketServer.exe"

# CloudFlare nameserver
[string] $NameServer = "1.1.1.1"

# Number of attempts to resolve the DNS endpoint of the container
[int] $DnsRetries = 10

# Current Azure Container Instance TTL on A records is 14
[int] $DnsWaitInSeconds = 15


# Derived constants - Ready to use paths to various executable and files 
[string] $PhotonSocketServerExecutableRelativePath = Join-Path -Path $PhotonSocketServerDirectoryRelativePath -ChildPath $PhotonSocketServerExecutableName


# Include configuration functions
. .\Configure-LoadBalancingApp.ps1


function Resolve-PhotonEndpoint([string] $endpoint, [string] $nameServer, [int] $numberOfRetries, [int] $secondsBetweenRetries)
{
    [int] $retries = $numberOfRetries
    [int] $waitInSeconds = $secondsBetweenRetries

    do {
        try {
            Write-Host "Resolve-DnsName -Name $endpoint -Type A -Server $nameServer"
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

    # Special case for PHOTON_ENDPOINT null or empty - Lookup 'myip.opendns.com' against 'resolver1.opendns.com'
    if ([string]::IsNullOrEmpty($photonEndpoint)) {
        Write-Host "Resolving 'myip.opendns.com' using nameserver 'resolver1.opendns.com'" 
        [string] $inferedIp = Resolve-PhotonEndpoint "myip.opendns.com" "resolver1.opendns.com" $DnsRetries $DnsWaitInSeconds

        if (![string]::IsNullOrEmpty($inferedIp)) {
            Write-Host "OpenDNS resolved my IP to '$inferedIp'"
            return $inferedIp
        }
    }

    # When re-creating a container shortly after deleting it in Azure Container Instances, the DNS name may still point to the previous IP
    # We keep on resolving the IP and waiting for TTL to expire until we get to a stable IP
    Write-Host "Resolving '$photonEndpoint' using '$NameServer' and waiting for IP addresses to stabilize"
    [string] $ip1 = $null
    [string] $ip2 = $null
    do {
        $ip1 = $null
        $ip2 = $null

        $ip1 = Resolve-PhotonEndpoint $photonEndpoint $NameServer $DnsRetries $DnsWaitInSeconds
        Start-Sleep $DnsWaitInSeconds
        $ip2 = Resolve-PhotonEndpoint $photonEndpoint $NameServer $DnsRetries $DnsWaitInSeconds

        Write-Host "Resolved '$photonEndpoint' to '$ip1' and '$ip2'"
    } while ([string]::IsNullOrEmpty($ip1) -or [string]::IsNullOrEmpty($ip2) -or ($ip1 -ne $ip2))

    return $ip1
}

function Register-PerformanceCounters([bool] $registerPerformanceCounters, [Version] $photonVersion)
{
    if ($registerPerformanceCounters) {
        if ($photonVersion.Major -eq 4) {
            Write-Host "Registering performance counters"
            $photonSocketServerProcess = Start-Process -FilePath $PhotonSocketServerExecutableRelativePath -ArgumentList "/installCounters" -WorkingDirectory $PhotonSocketServerDirectoryRelativePath -NoNewWindow -Wait -PassThru
            [int] $photonExitCode = $photonSocketServerProcess.ExitCode
            if ($photonExitCode -ne 0) {
                throw "Failed to register performance counters - PhotonSocketServer exited - $photonExitCode"
            }
        } else {
            Write-Host "Performance counter registration not yet supported for Photon v5"
        }
    } else {
        Write-Host "Skipping performance counters registration"
    }
}

function Get-PhotonVersion()
{
    [string] $photonSocketServerPath = Join-Path -Path $PhotonSocketServerDirectoryRelativePath -ChildPath $PhotonSocketServerExecutableName
    return (Get-ChildItem $photonSocketServerPath).VersionInfo.FileVersion
}

## ----------------------------------------------------------------------------------------------------------------------------
$photonVersion = Get-PhotonVersion
Write-Host "Photon Version: $photonVersion"

[string] $endpoint = $Env:PHOTON_ENDPOINT
Write-Host "PHOTON_ENDPOINT: $endpoint"

[string] $loadBalancerPublicIP = Get-PhotonPublicIp $endpoint
Write-Host "GameServer client accessible IP: $loadBalancerPublicIP"

if (-not [string]::IsNullOrEmpty($loadBalancerPublicIP)) {
    Write-Host "Configuring LoadBalancing application"
    Configure-LoadBalancingApp $PhotonRoot $loadBalancerPublicIP $enablePerformanceCounters $photonVersion

    # Register Windows performance counters
    Register-PerformanceCounters $enablePerformanceCounters $photonVersion

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
} else {
    throw "Could not find GameServer client accessible IP"
}