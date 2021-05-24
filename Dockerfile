#escape=`

FROM mcr.microsoft.com/windows/servercore:20H2

SHELL [ "powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'Continue'; $verbosePreference='Continue';" ]

WORKDIR C:\

COPY Photon Photon
COPY *.ps1 Photon\

WORKDIR C:\Photon

#
# Photon ports can be found here : https://doc.photonengine.com/en-us/realtime/current/connection-and-authentication/tcp-and-udp-port-numbers
#
# 4520            TCP   S2S GameServer to Master (TCP)
# 4530            TCP	Client to Master Server (TCP)
# 4531            TCP	Client to Game Server (TCP)
# 4533	          TCP	Client to Nameserver (TCP)
# 5055 or 27001   UDP	Client to Master Server (UDP)
# 5056 or 27002   UDP	Client to Game Server (UDP)
# 5058 or 27000	  UDP	Client to Nameserver (UDP)
# 9090            TCP	Client to Master Server (WebSockets)
# 9091            TCP	Client to Game Server (WebSockets)
# 9093            TCP	Client to Nameserver (WebSockets)
# 19090           TCP	Client to Master Server (Secure WebSockets)
# 19091           TCP	Client to Game Server (Secure WebSockets)
# 19093           TCP	Client to Nameserver (WebSockets)
#

EXPOSE 843/tcp 4530/tcp 4531/tcp 4533/tcp 5055/udp 5056/udp 5058/udp 6060/tcp 6061/tcp 6063/tcp 9090/tcp 9091/tcp 9093/tcp 19090/tcp 19091/tcp 19093/tcp  

EXPOSE 4520/tcp 

ENV PHOTON_ENDPOINT localhost

ENTRYPOINT . ./EntryPoint.ps1