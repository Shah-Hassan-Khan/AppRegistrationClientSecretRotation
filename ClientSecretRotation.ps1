$subscriptionId ="aaaaa-aaaaaa-aaaaaaa-aaaaa-aaaaa"  #Subscription ID
$storageAccountName = "Storage Name "
$resourceGroupName = "Resource Group Name" 
$containerName = "Container Name"
$connectionName = "AzureRunAsConnection"
try
{
    $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName
    "Logging in to Azure..."
    $connectionResult =  Connect-AzAccount -Tenant $servicePrincipalConnection.TenantID `
                             -ApplicationId $servicePrincipalConnection.ApplicationID   `
                             -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint `
                             -ServicePrincipal
    "Successfully Logged in."

}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

Select-AzSubscription -SubscriptionId $subscriptionId
$storageAccount  =Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName 
$ctx=$storageAccount.Context
$containers=Get-AzStorageContainer  -Context $ctx 
$myBlob = Get-AzStorageBlob -Container $containers.Name -Context $ctx -Blob "appregistration.json" 
$Text = $myBlob.ICloudBlob.DownloadText() 
$resultObject =  $Text | ConvertFrom-Json 
$data = $resultObject.appregistrations 
	$secretExpirationInDays = $resultObject.secretExpirationInDays
	$newSecreteExpirationInDays = $resultObject.newSecreteExpirationInDays

Write-Output "Connecting to AzureAD..."
$connection = Get-AutomationConnection -Name AzureRunAsConnection
Connect-AzureAD -TenantId $connection.TenantID -ApplicationId $connection.ApplicationID -CertificateThumbprint $connection.CertificateThumbprint
Write-Output "Connected to AzureAD!"
$futuredate = (Get-Date).AddDays($secretExpirationInDays).ToUniversalTime()
    foreach($appregistrationlist in $data) {
		$AppRegistrationId = $appregistrationlist.appregistrationid 
		$clientSecret = $appregistrationlist.secretid  
		Write-Output "App Registration ID = " $AppRegistrationId
		Write-Output  "Client Secret = "$clientSecret
		$secretkeys =Get-AzureADApplication -Filter "AppId  eq '$AppRegistrationId'"  
		foreach($secret in $secretkeys.PasswordCredentials){  
			if( ($secret.KeyId) -eq $clientSecret){
				$CurrentKeyId = $secret.KeyId
				$ExpiryDate = $secret.EndDate 
			}
		}
				if($CurrentKeyId -eq $clientSecret){ 
				if ($ExpiryDate -lt $futuredate ){  
					Write-Output  "Client Secret is expiring soon..." 
# Create new Client Secret

					$startDate = Get-Date
					$endDate = $startDate.AddDays($newSecreteExpirationInDays)
					$objectid = 'bbbbb-bbbbbb-bbbbbbb-bbbbb-bbbbbb'  #App Registration ID
					$aadAppKeyPwd = New-AzureADApplicationPasswordCredential -ObjectId $objectid -CustomKeyIdentifier (get-date -format "yyyy-MM-dd") -StartDate $startDate -EndDate $endDate 
					Write-Output "New key generated successfully "
					$NewSecretId =  $aadAppKeyPwd.Value
					#Write-Output  $NewSecretId
					$appregistrationlist.secretid = $NewSecretId  # Update with New ClientSecret Value

					$connection = Get-AutomationConnection -Name AzureRunAsConnection
					Connect-AzAccount -TenantId $connection.TenantID -ApplicationId $connection.ApplicationID -CertificateThumbprint $connection.CertificateThumbprint
					

					foreach($keyvault in $appregistrationlist.keyvaults ){
		   				Write-Output "VaultName = " $keyvault.vaultName  
		   				Write-Output "Secret =" $keyvault.secretName  
						$vault = $keyvault.vaultName.ToString()
						$secret = $keyvault.secretName.ToString()
						$secretvalue = 'e745e49a-1dd6-4d73-9a21-2912ca00745e'  
						$keyvault = Set-AzKeyVaultSecret -VaultName $vault -Name $secret  -SecretValue (ConvertTo-SecureString -String $NewSecretId -AsPlainText -Force)
						Write-Output "Key Vault secret updated... "  
						
	   				}
				} 
				else{
					
					Write-Output "Client secret is ok "
				}
			}
			else{
				
				Write-Output "No Client Secret matched"
			} 
    } 

$result = ConvertTo-Json @($resultObject) -Depth  10
$vFileName = "appregistration.json"
           $result | out-file $vFileName -Force
            $tmp2 = Set-AzStorageBlobContent -File $vFileName -Container $containers.Name -Context $ctx -Force 
Write-Output "Done"

