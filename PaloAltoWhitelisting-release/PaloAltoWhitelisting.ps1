Trace-VstsEnteringInvocation $MyInvocation

$PaloName= Get-VstsInput -Name "PaloName"
$username= Get-VstsInput -Name "username"
$password= Get-VstsInput -Name "password"
$DryRun = Get-VstsInput -name "DryRun" -AsBool
$EastUS2 = Get-VstsInput -name "EastUS2" -AsBool
$CentralUS = Get-VstsInput -name "CentralUS" -AsBool
$CosmosDB = Get-VstsInput -name "CosmosDB" -AsBool
$SQL = Get-VstsInput -name "SQL" -AsBool
$Storage = Get-VstsInput -name "Storage" -AsBool


function Call-PaloAPI ($URL) {

    $response = Try {
        Invoke-WebRequest -Uri $URL -UseBasicParsing -ErrorAction Stop
    }

    Catch { 
        Write-Error "An exception was caught: $($_.Exception.Message)"
    }

    [xml]$a = $response.Content
    Return $a.response
}
    
### Get API Key from Palo credentials ###
$response = Call-PaloAPI -URL "https://$paloname/api/?type=keygen&user=$username&password=$password"
$apikey = $response.result.key

### Get IP list from Microsoft ###
$URi = "https://www.microsoft.com/en-us/download/confirmation.aspx?id=56519&#8221" 
$downloadPage = Invoke-WebRequest -Uri $URi -usebasicparsing
$xmlFileUri = ($downloadPage.RawContent.Split('"') | where {$_ -match "ServiceTags_Public"})[0]
$response = Invoke-WebRequest -Uri $xmlFileUri -usebasicparsing
$JsonResponse = [System.Text.Encoding]::UTF8.GetString($response.Content) | ConvertFrom-Json
$AllAzureIPs = $JsonResponse | select -ExpandProperty Values

### Filter list to Selected IPs ###
$IPAddresses = @()
If ($EastUS2) {
    If ($CosmosDB) {
        Write-Host "##[debug]Collecting Azure IP's for AzureCosmosDB.EastUS2"
        $IPAddresses += ($AllAzureIPs | where {$_.name -eq "AzureCosmosDB.EastUS2"} | select -ExpandProperty Properties) | select -ExpandProperty addressPrefixes
    }
    If ($SQL) {
        Write-Host "##[debug]Collecting Azure IP's for Sql.EastUS2"
        $IPAddresses += ($AllAzureIPs | where {$_.name -eq "Sql.EastUS2"} | select -ExpandProperty Properties) | select -ExpandProperty addressPrefixes
    }
    If ($Storage) {
        Write-Host "##[debug]Collecting Azure IP's for Storage.EastUS2"
        $IPAddresses += ($AllAzureIPs | where {$_.name -eq "Storage.EastUS2"} | select -ExpandProperty Properties) | select -ExpandProperty addressPrefixes
    }
}
If ($CentralUS) {
    If ($CosmosDB) {
        Write-Host "##[debug]Collecting Azure IP's for AzureCosmosDB.CentralUS"
        $IPAddresses += ($AllAzureIPs | where {$_.name -eq "AzureCosmosDB.CentralUS"} | select -ExpandProperty Properties) | select -ExpandProperty addressPrefixes
    }
    If ($SQL) {
        Write-Host "##[debug]Collecting Azure IP's for Sql.CentralUS"
        $IPAddresses += ($AllAzureIPs | where {$_.name -eq "Sql.CentralUS"} | select -ExpandProperty Properties) | select -ExpandProperty addressPrefixes
    }
    If ($Storage) {
        Write-Host "##[debug]Collecting Azure IP's for Storage.CentralUS"
        $IPAddresses += ($AllAzureIPs | where {$_.name -eq "Storage.CentralUS"} | select -ExpandProperty Properties) | select -ExpandProperty addressPrefixes
    }
}

### Get existing Global Protect Gateway ###
Write-Host "##[debug]Getting name of existing Global Protect gateway"
$response = Call-PaloAPI -URL "https://$PaloName/api/?type=config&action=get&key=$apikey&xpath=/config/devices/entry[@name='localhost.localdomain']/vsys/entry[@name='vsys1']/global-protect/global-protect-gateway"
$Gateway = $response.result.'global-protect-gateway'.entry.name
if (!($Gateway)) { Write-Error "Unable to determine name of existing Global Protect gateway" }

### Get existing Global Protect Gateway Client Config ###
Write-Host "##[debug]Getting name of existing Global Protect gateway client config"
$response = Call-PaloAPI -URL "https://$PaloName/api/?type=config&action=get&key=$apikey&xpath=/config/devices/entry[@name='localhost.localdomain']/vsys/entry[@name='vsys1']/global-protect/global-protect-gateway/entry[@name=`'$Gateway`']/remote-user-tunnel-configs"
$GWClient = $response.result.'remote-user-tunnel-configs'.entry.name
if (!($GWClient)) { Write-Error "Unable to determine name of existing Global Protect client config" }

### Get existing split tunneling rule
Write-Host "##[debug]Getting existing Global Protect split tunneling rule"
$response = Call-PaloAPI -URL "https://$PaloName/api/?type=config&action=get&key=$apikey&xpath=/config/devices/entry[@name='localhost.localdomain']/vsys/entry[@name='vsys1']/global-protect/global-protect-gateway/entry[@name=`'$Gateway`']/remote-user-tunnel-configs/entry[@name=`'$GWClient`']/split-tunneling/access-route"
# Accommodate new structure for newer PanOS 
if ($response.result.'access-route'.member.'#text') { 
    $ExistingMembers = $response.result.'access-route'.member.'#text'
}
else {
    $ExistingMembers = $response.result.'access-route'.member
}
if (!($ExistingMembers)) { Write-Error "Unable to determine list of existing Global Protect split tunneling rules" }

### Display Differences ###
$Differences = Compare-Object $ExistingMembers $IPAddresses | where {$_.sideIndicator -eq "=>"} | select -ExpandProperty InputObject

if (!($Differences)) {

    Write-Host "No new IP address ranges from Azure were found in the split-tunneling rules in the existing Global Protect configuration."
    Exit

}

If ($DryRun) {
    
    Write-Host "##[command]*** DryRun option selected.  No changes will be made ***"
    Write-host "The following additional IP address ranges were found for the selected Azure services.  These ranges would have been added to the split-tunneling rules in the existing Global Protect configuration."
    Write-Host $($IPAddresses | out-string)

}
Else {

    Write-host "The following additional IP address ranges were found for the selected Azure services.  These ranges will be added to the split-tunneling rules in the existing Global Protect configuration."
    Write-Host $($IPAddresses | out-string)

    ### Create XML collection of addresses for split tunneling ###
    $AllMembers = $IPAddresses + $ExistingMembers | select -Unique
    $AllXML = $AllMembers -join "</member><member>"

    ### Upload list to VPN gateway ###
    Write-Host "##[debug]Uploading new split tunneling rules"
    $SplitTunnelXML = "<access-route><member>$AllXML</member></access-route>"
    $response = Call-PaloAPI -URL "https://$PaloName/api/?type=config&action=edit&key=$apikey&xpath=/config/devices/entry[@name='localhost.localdomain']/vsys/entry[@name='vsys1']/global-protect/global-protect-gateway/entry[@name=`'$Gateway`']/remote-user-tunnel-configs/entry[@name=`'$GWClient`']/split-tunneling/access-route&element=$SplitTunnelXML"
    if ($response.status -eq "error") {
        Write-Error $($response.msg.line | out-string)
    }
    else {
        Write-Host $response.msg
    }

    ### Commit the changes ###
    Write-Host "##[debug]Committing configuration changes"
    $response = Call-PaloAPI -URL "https://$PaloName/api/?type=commit&key=$apikey&cmd=<commit></commit>"
    # Accommodate new structure for newer PanOS 
    if ($response.result.job) {$id = $Response.result.job}
    if ($response.msg) { Write-Host $response.msg }

    If ($id) {
        ### Query the status of the job using the job ID ###
        $response = Call-PaloAPI -URL "https://$PaloName/api/?type=op&key=$apikey&cmd=<show><jobs><id>$id</id></jobs></show>"
        if ($response.result.job.details.line) { Write-Host $($response.result.job.details.line | out-string)}
        if ($response.result.status) { Write-Host $($response.result.status | out-string)}
        if ($response.result.msg.line) { Write-Host $($response.result.msg.line | out-string)}
    }
    Else {
        write-host $response.result.job.details.line
    }
}

Trace-VstsLeavingInvocation $MyInvocation
