# Introduction
Photon is a game networking engine and multiplayer platform developed and licensed by Exit Games. According to the [company's web site](https://www.photonengine.com/), Photon is used by various developers and studios, including Disney, Ubisoft and Oculus.

Exit Games currently provides two versions of Photon: a cloud-based service and a self-hosted server. This repo shows one way to run the self-hosted server as a Windows Docker container. It configures the `LoadBalancing` (`Master` and `GameServer`) Photon application, forwards all [default Photon self-hosted server ports](https://doc.photonengine.com/en-us/pun/v2/connection-and-authentication/tcp-and-udp-port-numbers) and turns performance counters on.

**NOTE**: Exit Games Photon is not free software. At the time of writting, Exit Games offers an evaluation version of Photon Self Hosted Server limited to 20 concurrent connected users.

# Setup
1. Clone this repository in a convenient location, perhaps C:\DockerizedPhoton. We will call this location `<repo root>`,
2. Download [Exit Games Photon Server SDK 4.0.29.11263](https://dashboard.photonengine.com/download/photon-server-sdk_v4-0-29-11263.exe) or later. Other versions of Photon Server SDKs are available on the [Exit Games download page](https://www.photonengine.com/en-US/sdks#serverserver) (Exit Games login required),
3. Extract the Photon SDK in a directory called Photon. The directory structure should be as follows:
    ```
        <repo root>
            | .dockerignore
            | .gitignore
            | ConfigurePhoton.ps1
            | Dockerfile
            | EntryPoint.ps1
            | Template
            |     | template.json
            |
            | Photon
            |     | build
            |     | deploy
            |     | doc
            |     | lib
            |     | src-server
            |
            | LICENSE
            | README.md
    ```
4. Make sure Docker for Windows is installed, setup for Windows Containers and running,
5. (Optional) Configure Photon server performance and statistics monitoring - See [Monitoring Photon](#monitoring_photon) below.

## Building and running locally
1. Open a Powershell window and cd into `<repo root>`
2. Build and tag the image `photon:1.0` by running:
    ```powershell
    docker build -t photon:1.0 .
    ```
    Docker will pull Windows Server Core from the Microsoft Image Registry if needed (Windows Server Core 1809 - `mcr.microsoft.com/windows/servercore:1809`). This may take a while.
3. Create a custom NAT Docker network to run Photon locally. This only needs to be done once:
    ```powershell
    docker network create --driver=nat --subnet=172.24.1.0/24 --gateway=172.24.1.1 photon-nat
    ```
4. Run the container locally:
    ```powershell
    docker run --rm --interactive --tty --network photon-nat --ip 172.24.1.20 -e PHOTON_ENDPOINT=172.24.1.20 -p 843:843/tcp -p 4530:4530/tcp -p 4531:4531/tcp -p 4533:4533/tcp -p 5055:5055/udp -p 5056:5056/udp -p 5058:5058/udp -p 6060:6060/tcp -p 6061:6061/tcp  -p 6063:6063/tcp -p 9090:9090/tcp -p 9091:9091/tcp -p 19090:19090/tcp -p 19091:19091/tcp -p 19093:19093/tcp photon:1.0
    ```

    The image starts the standard `LoadBalancing` application. The Photon server is ready when the container displays the PID of `PhotonSocketServer` as follows:
    ```
    DNS Name: 172.24.1.20
    Public IP: 172.24.1.20
    Configuring Master (Photon.LoadBalancing.dll.config)
    Configuring GameServer (Photon.LoadBalancing.dll.config)
    Starting PhotonSocketServer
    PhotonSocketServer has PID '1976'
    Waiting for PhotonSocketServer to exit
    ```
    Photon Server is now available at `172.24.1.20` (the value passed as `PHOTON_ENDPOINT`) and game clients can now connect.

# Deploy to Azure Container Instance
You will need an active Azure subscription and an [Azure Image Registry](https://docs.microsoft.com/en-us/azure/container-registry/container-registry-get-started-portal) instance. A "Basic" SKU is sufficient. The following steps assume Administrative User access has been enabled. You will need to substitute `<registry login server>`, `<registry user name>` and `<registry password>` with actual login information for your registry. These can be found under the "Access keys" blade in the Azure portal.

1. Tag the image with the registry login server. You can either build and tag the image in one step:
    ```powershell
    docker build -t <registry login server>/gameserver/photon:1.0 .
    ```
    or tag an existing image:

    ```powershell
    docker tag photon:1.0 <registry login server>/gameserver/photon:1.0
    ```
2. Login to the registry and push the image. Provide `<registry user name>` and `<registry password>` if asked:
    ```powershell
    docker login <registry login server>
    docker push <registry login server>/gameserver/photon:1.0
    ```
3. Run the Photon image in an instance of [Azure Container Instance](https://docs.microsoft.com/en-us/azure/container-instances/). This can be done via [Azure Powershell](https://docs.microsoft.com/en-us/powershell/azure/overview?view=azps-2.1.0) :
    ```powershell
    New-AzureRmResourceGroupDeployment `
        -ResourceGroupName <resource group name> `
        -TemplateFile Template\template.json `
        -imageTag <registry login server>/gameserver/photon:1.0 `
        -containerRegistryServer <registry login server> `
        -containerRegistryUsername <registry user name> `
        -containerRegistryPassword <registry password> `
        -cpuCount=2 `
        -memoryGiB=2
    ```
    or [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest) :
    ```shell
    az deployment group create \
        --resource-group <resource group name> \
        --template-file Template/template.json \
        --parameters \
            imageTag=<registry login server>/gameserver/photon:1.0 \
            containerRegistryServer=<registry login server> \
            containerRegistryUsername=<registry user name> \
            containerRegistryPassword=<registry password>
    ```
    If the Container Instance Group exists, it is updated. Caution: all containers in the group are stopped first.

## Configure number of CPUs and memory size
The number of CPUs and memory size can be configured by passing the deployment parameters `cpuCount=<number of virtual cpus>` or `memoryGiB=<amount of memory>` respectively. This can be done via [Azure Powershell](https://docs.microsoft.com/en-us/powershell/azure/overview?view=azps-2.1.0) :
```powershell
New-AzureRmResourceGroupDeployment `
    -ResourceGroupName <resource group name> `
    -TemplateFile Template\template.json `
    -imageTag <registry login server>/gameserver/photon:1.0 `
    -containerRegistryServer <registry login server> `
    -containerRegistryUsername <registry user name> `
    -containerRegistryPassword <registry password> `
    -cpuCount=2 `
    -memoryGiB=2
```
or [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest) :
```shell
az deployment group create \
    --resource-group <resource group name> \
    --template-file Template/template.json \
    --parameters \
        imageTag=<registry login server>/gameserver/photon:1.0 \
        containerRegistryServer=<registry login server> \
        containerRegistryUsername=<registry user name> \
        containerRegistryPassword=<registry password> \
        cpuCount=2 \
        memoryGiB=2
```

## Retrieving Azure Container Registry credentials from Azure Key Vault
The previous instructions provide `<registry user name>` and `<registry password>` on the command line. It is best to store these secrets in [Azure Key Vault](https://docs.microsoft.com/en-us/azure/key-vault/) and retrieve them programatically during deployment.

You will need an instance of Azure Key Vault with at least one secret to store the container registry password. In commands below, substitute `<keyvault name>`, and `<registry password secret name>` with the name of the Key Vault instance and the name of the container registry password secret name. To deploy via [Azure Powershell](https://docs.microsoft.com/en-us/powershell/azure/overview?view=azps-2.1.0) :
```powershell
New-AzureRmResourceGroupDeployment `
    -ResourceGroupName <resource group name> `
    -TemplateFile Template\template.json `
    -imageTag <registry login server>/gameserver/photon:1.0 `
    -containerRegistryServer <registry login server> `
    -containerRegistryUsername <registry user name> `
    -containerRegistryPassword `
        { (Get-AzureKeyVaultSecret -VaultName <keyvault name> -Name <registry password secret name>).SecretValueText }
```
or [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest) :
```shell
az deployment group create \
    --resource-group <resource group name> \
    --template-file Template/template.json \
    --parameters \
        imageTag=<registry login server>/gameserver/photon:1.0 \
        containerRegistryServer=<registry login server> \
        containerRegistryUsername=<registry user name> \
        containerRegistryPassword=$(az keyvault secret show \
            --vault-name <keyvault name> \
            --name <registry password secret name> \
            --query value -o tsv)
```
For more information, refer to [Deploy to Azure Container Instances from Azure Container Registry](https://docs.microsoft.com/en-us/azure/container-instances/container-instances-using-azure-container-registry).

# <a name="monitoring_photon"></a>Monitoring Photon
Photon tracks server performance and statistics via [performance counters](https://doc.photonengine.com/en-us/server/current/performance/photon-counters). Applications can create their own performance counters (see [Implementing Custom Performance Counters](https://doc.photonengine.com/en-us/server/current/performance/photon-counters)).

By default, performance counters are only available in memory on the Photon server. Exit Games offers `CounterPublisher`, a mecanism to publish performance counters. CounterPublisher is extensible and can publish metrics via standard protocols (UDP, HTTP(s), PGM - see [Application Protocols](https://doc.photonengine.com/en-us/server/current/performance/photon-counters)) or to monitoring applications or services including:
* [StatsD](https://github.com/etsy/statsd/) - see [Publishing to StatsD](https://doc.photonengine.com/en-us/server/current/performance/photon-counters),
* [Graphite](https://graphite.wikidot.com/carbon) - see [Publishing to Graphite](https://doc.photonengine.com/en-us/server/current/performance/photon-counters),
* [InfluxDB](https://www.influxdata.com/) - see [Publishing to InfluxDB](https://doc.photonengine.com/en-us/server/current/performance/photon-counters),
* [NewRelic](https://newrelic.com/platform) - see [Publishing to NewRelic Platform](https://doc.photonengine.com/en-us/server/current/performance/photon-counters) and [this repository](https://github.com/PhotonEngine/photon.counterpublisher.newrelic)
* [Amazon CloudWatch](https://aws.amazon.com/cloudwatch/) - see [Publishing to Amazon AWS CloudWatch](https://doc.photonengine.com/en-us/server/current/performance/photon-counters) and [this repository](https://github.com/PhotonEngine/photon.counterpublisher.cloudwatch),
* [Azure Application Insights](https://docs.microsoft.com/en-us/azure/azure-monitor/app/app-insights-overview) - see [this repository](https://github.com/GillesZunino/Photon-Azure-CounterPublishers).

## Configuring `CounterPublisher` in the container
Configuring `CounterPublisher` is highly dependant on the protocol or the service to publish performances counters and statistics to. The steps below outline the typical procedure. For instructions specific to a protocol or service, refer to one of the links above.

1. (Optional) If the protocol or monitoring service requires a `CounterPublisher` plugin, copy all binaries and supporting files to the following directories:
   * `deploy\CounterPublisher\bin`
   * `deploy\Loadbalancing\GameServer\bin`
   * `deploy\Loadbalancing\Master\bin`

2. Update the `<Photon><CounterPublisher>...</CounterPublisher></Photon>` configuration section in the following configuration files:

   * `deploy\CounterPublisher\bin\CounterPublisher.dll.config`
   * `deploy\Loadbalancing\GameServer\bin\Photon.LoadBalancing.dll.config`
   * `deploy\Loadbalancing\Master\bin\Photon.LoadBalancing.dll.config`

    The default `<Photon><CounterPublisher>...</CounterPublisher></Photon>` publishes performance counters via Photon's own binary protocol over UDP:
    ```xml
    <Photon>
        <CounterPublisher enabled="True" updateInterval="1">
        <Sender
            endpoint="udp://255.255.255.255:40001"
            protocol="PhotonBinary"
            initialDelay="10"
            sendInterval="10" />
        </CounterPublisher>
    </Photon>
    ```

    Typical changes to this configuration section include specifying which plugin(s) to use, how frequently to publish metrics, ....

3. Rebuild and run the Docker image with updated configuration.

## Performance and Metrics tips

* It is possible to list all registered Windows Performance Counters exposed by Photon with the following powershell command:
    ```powershell
    Get-Counter -ListSet "Photon*"
    ```

* Retrieving the value of `Photon Socket Server: UDP(_Total)\UDP: Connections Active` every 10 seconds can be done with the following powershell command:
    ```powershell
    Get-Counter -Counter "\Photon Socket Server: UDP(_Total)\UDP: Connections Active" -SampleInterval 10 -Continuous
    ```

# Future work and known limitations

* Guidance on how to collect Photon logs (possibly with Azure Log Analytics or Azure Application Insights)
* Add a troubleshooting section
* Consider describing configuration for HTTPS or WebSocket / Secure WebSocket.