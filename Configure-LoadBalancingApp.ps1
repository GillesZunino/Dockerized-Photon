<#
.SYNOPSIS
Configure Photon 'LoadBalanding' application with the server's public IP. 

.DESCRIPTION
Configure Photon 'LoadBalanding' application with the server's public IP. Enables/disables performance counters.

.PARAMETER loadBalancerPublicIp
Public IP of the Photon server.

.PARAMETER enablePerformanceCounters
$true to enable, $false to disable.
#>

function Configure-LoadBalancingApp([string] $loadBalancerPublicIp, [bool] $enablePerformanceCounters)
{
    Write-Host "[LoadBalancing] Configuring Master (Photon.LoadBalancing.dll.config)"
    Update-PhotonConfiguration ".\deploy\Loadbalancing\Master\bin\Photon.LoadBalancing.dll.config" $loadBalancerPublicIP $enablePerformanceCounters

    Write-Host "[LoadBalancing] Configuring GameServer (Photon.LoadBalancing.dll.config)"
    Update-PhotonConfiguration ".\deploy\Loadbalancing\GameServer\bin\Photon.LoadBalancing.dll.config" $loadBalancerPublicIP $enablePerformanceCounters
}

function Update-PhotonConfiguration([string] $configFilePath, [string] $loadBalancerPublicIp, [bool] $enablePerformanceCounters)
{
    [xml] $config = Get-Configuration $configFilePath

    # Configure Performance Counters
    $config.SelectSingleNode("//configuration/applicationSettings/Photon.LoadBalancing.Common.CommonSettings/setting[@name='EnablePerformanceCounters']").SelectSingleNode("./value").InnerText = $enablePerformanceCounters

    # Configure master IP and game IP
    $config.SelectSingleNode("//configuration/applicationSettings/Photon.LoadBalancing.MasterServer.MasterServerSettings/setting[@name='PublicIPAddress']").SelectSingleNode("./value").InnerText = $loadBalancerPublicIp
    $config.SelectSingleNode("//configuration/applicationSettings/Photon.LoadBalancing.GameServer.GameServerSettings/setting[@name='PublicIPAddress']").SelectSingleNode("./value").InnerText = $loadBalancerPublicIp

    # Explicitely force IPV6 to be empty - Photon has a bug where <value></value> tag is interpreted as a 'valid' IP even though it is not
    $config.SelectSingleNode("//configuration/applicationSettings/Photon.LoadBalancing.GameServer.GameServerSettings/setting[@name='PublicIPAddressIPv6']").InnerXml = "<value/>"

    Save-Configuration $config $configFilePath
}

function Get-Configuration([string] $configFilePath)
{
    [xml] $config = Get-Content -Path $configFilePath
    return $config
}

function Save-Configuration([xml] $photonConfigXml, [string] $configFilePath)
{
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    $sw = New-Object System.IO.StreamWriter($configFilePath, $false, $utf8WithoutBom)
    $photonConfigXml.Save($sw)
    $sw.Close()
}