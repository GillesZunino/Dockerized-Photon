<#
.SYNOPSIS
Configure Photon 'LoadBalanding' application with the server's public IP. 

.DESCRIPTION
Configure Photon 'LoadBalanding' application with the server's public IP. Enables/disables performance counters.

.PARAMETER photonRoot
Path to Photon's root directory.

.PARAMETER loadBalancerPublicIp
Public IP of the Photon server.

.PARAMETER enablePerformanceCounters
$true to enable, $false to disable.

.PARAMETER photonVersion
PhotonSocketServer.exe version
#>

function Configure-LoadBalancingApp([string] $photonRoot, [string] $loadBalancerPublicIp, [bool] $enablePerformanceCounters, [Version] $photonVersion)
{
    if ($photonVersion.Major -eq 4) {
        Write-Host "Photon v4 configuration"
        Write-Host "[LoadBalancing] Configuring Master (Photon.LoadBalancing.dll.config)"
        Update-PhotonV4Configuration ( Join-Path -Path $photonRoot -ChildPath "Loadbalancing\Master\bin\Photon.LoadBalancing.dll.config" ) $loadBalancerPublicIP $enablePerformanceCounters
    
        Write-Host "[LoadBalancing] Configuring GameServer (Photon.LoadBalancing.dll.config)"
        Update-PhotonV4Configuration ( Join-Path -Path $photonRoot -ChildPath "Loadbalancing\GameServer\bin\Photon.LoadBalancing.dll.config" ) $loadBalancerPublicIP $enablePerformanceCounters
    } else {
        if ($photonVersion.Major -eq 5) {
            Write-Host "Photon v5 configuration"
            Write-Host "[NameServer] Configuring NameServer (Nameserver.xml.config)"
            Write-Host "[NameServer] Configuring NameServer (Nameserver.json)"

            Write-Host "[LoadBalancing] Configuring Master (Master.xml.config)"
            Update-LoadBalancingMasterV5Configuration ( Join-Path -Path $photonRoot -ChildPath "LoadBalancing\Master\bin\Master.xml.config") $false

            Write-Host "[LoadBalancing] Configuring GameServer (GameServer.xml.config)"
            Update-LoadBalancingGameServerV5Configuration ( Join-Path -Path $photonRoot -ChildPath "LoadBalancing\GameServer\bin\GameServer.xml.config" ) $loadBalancerPublicIP "localhost" $false
        }
    }
}

function Update-PhotonV4Configuration([string] $configFilePath, [string] $loadBalancerPublicIp, [bool] $enablePerformanceCounters)
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

function Update-LoadBalancingMasterV5Configuration([string] $configFilePath, [bool] $enableWebRPC)
{
    [xml] $config = Get-Configuration $configFilePath

    # Configure WebRPC
    $config.SelectSingleNode("//configuration/Photon/WebRpc").SetAttribute("Enabled", $enableWebRPC)

    Save-Configuration $config $configFilePath
}

function Update-LoadBalancingGameServerV5Configuration([string] $configFilePath, [string] $masterPublicHostName, [string] $masterPublicIp, [bool] $enableWebRPC)
{
    [xml] $config = Get-Configuration $configFilePath

    # Configure master IP and hostname
    $config.SelectSingleNode("//configuration/Photon/GameServer/S2S/MasterIPAddress").InnerText = $masterPublicIp
    $config.SelectSingleNode("//configuration/Photon/GameServer/Master/PublicIPAddress").InnerText = $masterPublicIp
    $config.SelectSingleNode("//configuration/Photon/GameServer/Master/PublicHostName").InnerText = $masterPublicHostName
    
    # Configure WebRPC
    $config.SelectSingleNode("//configuration/Photon/WebRpc").SetAttribute("Enabled", $enableWebRPC)

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