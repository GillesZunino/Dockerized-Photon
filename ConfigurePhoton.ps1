function Configure-Photon([string] $configFilePath, [string] $loadBalancerPublicIp)
{
    [xml] $config = Get-Configuration $configFilePath

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