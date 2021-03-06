#################################################################################################################################
#  Name        : Configure-WinRM.ps1                                                                                            #
#                                                                                                                               #
#  Description : Configures the WinRM on a local machine                                                                        #
#                                                                                                                               #
#  Arguments   : HostName, specifies the FQDN of machine or domain                                                              #
#              : PortNumber, specifies the port to be used for https inbound traffic                                            #
#################################################################################################################################

param
(    
    [Parameter(Mandatory = $true)]
    [string] $HostName,
    [Parameter(Mandatory = $true)]
    [string] $Port
)

Set-PSDebug -Strict 
$ErrorActionPreference = "Stop"

#################################################################################################################################
#                                             Helper Functions                                                                  #
#################################################################################################################################

function Delete-WinRMListener
{
    try
    {
        $config = Winrm enumerate winrm/config/listener
        foreach($conf in $config)
        {
            if($conf.Contains("HTTPS"))
            {
                winrm delete winrm/config/Listener?Address=*+Transport=HTTPS
                break
            }
        }
    }
    catch
    {
        Write-Verbose -Verbose "Exception while deleting the listener: " + $_.Exception.Message
    }
}

function Configure-WinRMHttpsListener
{
    param([string] $HostName)

    #Delete the WinRM Https listener if it is already configure
    Delete-WinRMListener
    
    # Create a test certificate
    $thumbprint = (Get-ChildItem cert:\LocalMachine\My | Where-Object { $_.Subject -eq "CN=" + $HostName } | Select-Object -Last 1).Thumbprint
    if(-not $thumbprint)
    {
    # makecert ocassionally produces negative serial numbers
	# which golang tls/crypto <1.6.1 cannot handle
	# https://github.com/golang/go/issues/8265
        $serial = Get-Random
        .\makecert -r -pe -n CN=$Hostname -b 01/01/2012 -e 01/01/2022 -eku 1.3.6.1.5.5.7.3.1 -ss my -sr localmachine -sky exchange -sp "Microsoft RSA SChannel Cryptographic Provider" -sy 12 -# $serial
        $thumbprint=(Get-ChildItem cert:\Localmachine\my | Where-Object { $_.Subject -eq "CN=" + $HostName } | Select-Object -Last 1).Thumbprint
        
		if(-not $thumbprint)
        {
            throw "Failed to create the test certificate."
        }
    }    

    $response = cmd.exe /c $currentLocation\winrmconf.cmd $HostName $thumbprint
	
    Write-Host "The response is... "
    Write-Host $response
}

function Add-FirewallException
{
    param([string] $port)

    # Delete an exisitng rule
    netsh advfirewall firewall delete rule name="Windows Remote Management (HTTPS-In)" dir=in protocol=TCP localport=$port

	# Add a new firewall rule
    netsh advfirewall firewall add rule name="Windows Remote Management (HTTPS-In)" dir=in action=allow protocol=TCP localport=$port
}

#################################################################################################################################
#                                              Configure WinRM                                                                  #
#################################################################################################################################

$currentLocation=Split-Path -parent $MyInvocation.MyCommand.Definition

# Configure https listener
Configure-WinRMHttpsListener $HostName

# Add firewall exception
Add-FirewallException -port $port

#################################################################################################################################
#################################################################################################################################