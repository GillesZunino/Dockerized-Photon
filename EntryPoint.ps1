# Include configuration functions
. .\ConfigurePhoton.ps1

function Resolve-PhotonEndpoint([string] $photonEndpoint, [int] $numberOfRetries, [int] $secondsBetweenRetries)
{
    [int] $retries = $numberOfRetries
    [int] $waitInSeconds = $secondsBetweenRetries

    do {
        try {
            Write-Host "Resolving '$endpoint'"
            $dnsEntry = Resolve-DnsName -Name $endpoint -Type A -Server 1.1.1.1
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

    # Number of attempts to resolve the DNS endpoint of the container
    [int] $retries = 10

    # Current Azure Container Instance TTL on A records is 14
    [int] $waitInSeconds = 15
    
    # When re-creating a container shortly after deleting it, the DNS name may still point to the previous IP
    # We keep on resolving the IP and waiting for TTL to expire until we get to a stable IP
    Write-Host "Waiting for public IP to stabilize"
    [string] $ip1 = $null
    [string] $ip2 = $null
    do {
        $ip1 = $null
        $ip2 = $null

        $ip1 = Resolve-PhotonEndpoint $photonEndpoint $retries $waitInSeconds
        Start-Sleep $waitInSeconds
        $ip2 = Resolve-PhotonEndpoint $photonEndpoint $retries $waitInSeconds

        Write-Host "Resolved '$photonEndpoint' to '$ip1' and '$ip2'"
    } while ([string]::IsNullOrEmpty($ip1) -or [string]::IsNullOrEmpty($ip2) -or ($ip1 -ne $ip2))

    return $ip1
}

## ----------------------------------------------------------------------------------------------------------------------------

[string] $endpoint = $Env:PHOTON_ENDPOINT
Write-Host "DNS Name: $endpoint"

[string] $loadBalancerPublicIP = Get-PhotonPublicIp $endpoint
Write-Host "Public IP: $loadBalancerPublicIP"

Write-Host "Configuring Master (Photon.LoadBalancing.dll.config)"
Configure-Photon ".\deploy\Loadbalancing\Master\bin\Photon.LoadBalancing.dll.config" $loadBalancerPublicIP

Write-Host "Configuring GameServer (Photon.LoadBalancing.dll.config)"
Configure-Photon ".\deploy\Loadbalancing\GameServer\bin\Photon.LoadBalancing.dll.config" $loadBalancerPublicIP

# Start PhotonSocketServer
Write-Host "Starting PhotonSocketServer"
[System.Diagnostics.ProcessStartInfo] $processInfo = New-Object System.Diagnostics.ProcessStartInfo
$processInfo.WorkingDirectory = ".\deploy\bin_Win64"
$processInfo.FileName = ".\deploy\bin_Win64\PhotonSocketServer"
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