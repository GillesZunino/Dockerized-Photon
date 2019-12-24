#escape=`

FROM mcr.microsoft.com/windows/servercore:1809

SHELL [ "powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'Continue'; $verbosePreference='Continue';" ]

WORKDIR C:\
COPY Photon Photon
COPY *.ps1 Photon\

WORKDIR C:\Photon

EXPOSE 843/tcp 4530/tcp 4531/tcp 4533/tcp 5055/udp 5056/udp 5058/udp 6060/tcp 6061/tcp 6063/tcp 9090/tcp 9091/tcp 9093/tcp 19090/tcp 19091/tcp 19093/tcp  

ENV PHOTON_ENDPOINT localhost

ENTRYPOINT . ./EntryPoint.ps1