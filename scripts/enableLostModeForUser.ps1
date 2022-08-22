param
(
    [Parameter (Mandatory=$false)]
    [object] $WebhookData
)


####################################################
# Get Username and Password from KeyVault
####################################################

# Variables for retrieving the correct secret from the correct vault
$VaultName = "KeyVaultJamfPro"
$SecretName = "JSSUsername"
$SecretPassword = "JSSPassword"

# Import PS modules to use Keyvault
Import-Module AZ.KeyVault
Import-Module AZ.Accounts

# Sign in to your Azure subscription
Connect-AzAccount -Identity

# Retrieve value from Key Vault
$Username = Get-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName -AsPlainText
$Password = Get-AzKeyVaultSecret -VaultName $VaultName -Name $SecretPassword -AsPlainText


####################################################
# Part 1: The Token
####################################################

# Some Jamf Pro variables to change...
$JssUri = Get-AutomationVariable -Name JSSUrl

# Command to send to the device (for now it's only made for lost mode)):
$CommandToSend = 'EnableLostMode'

####################################################
# Part 2: The Infos From Azure
####################################################

if ($WebhookData){
    
    $WebookDataJson = $WebhookData | ConvertTo-Json

	$WebookDataJson

    $JsonTmp = ($WebookDataJson | ConvertFrom-Json).RequestBody 

    $JsonData = ($JsonTmp | ConvertFrom-Json).data.alertContext.SearchResults  
    $Columns = $JsonData.tables.columns.Name


    $TableList = 
        ForEach($Row in $JsonData.tables.rows )
        {
            $TmpHash = [Ordered]@{}
            For($i = 0; $i -lt $Row.Length; ++$i )
            {
                $TmpHash.Add( $JsonData.tables.columns.name[$i], $Row[$i] )
            }
            [PSCustomObject]$TmpHash
        }

    $TableList 

} else {

    # Error
    Write-Error "This runbook is meant to be started from an Azure alert webhook only."

}


####################################################
# Part 3: The Token
####################################################

# Prepare for token acquisition
$CombineCreds = "$($Username):$($Password)"
$EncodeCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($CombineCreds))
$BasicAuthValue = "Basic $EncodeCreds"


# Use either a token or basic authentication depending on Jamf Pro version
$JamfProVersion = ((Invoke-RestMethod $JssUrl/JSSCheckConnection).Split(".")[0,1]) -join ''

If ( $JamfProVersion -lt 1035) {

    $AuthValue = $BasicAuthValue

} else {

    # Get Token for auth
    $TokenParams = @{
    Uri = "$JssUrl/api/v1/auth/token";
    Method = 'POST';
    Headers = @{ 
        Authorization = $BasicAuthValue;
        accept = "application/json"
        }
    }

    # Extract token
    $TokenResult = Invoke-RestMethod @TokenParams
    $Token = $TokenResult.token
    $AuthValue = "Bearer $Token"

}


####################################################
# Part 4: The Devices
####################################################

# Let's get a list of users in Jamf Pro
# Let's prepare to talk to Jamf Pro
$UsersApiAccessParams = @{
    Uri = "$JssUrl/JSSResource/users";
    Method = 'GET';
    Headers = @{ 
        Authorization = $AuthValue
        accept = "application/json"
    }
}

# Let's talk to Jamf Pro
$JamfProUsers = Invoke-RestMethod @UsersApiAccessParams | ConvertTo-Json

# Create PSObject to store informations
$FullListOfItems = @()

# Loop through the list of users to check if they are in Jamf Pro and if they have devices
ForEach($User in $TableList.userPrincipalName_){

    # Check if user exists in Jamf Pro
    if($JamfProUsers | Select-String -pattern "$User" -quiet){
    
        # Encode the username (if ever it contains special characters such as an @)
        $EncodedUserPrincipalName = [System.Web.HTTPUtility]::UrlEncode("$User")
    
        # Let's prepare to talk to Jamf Pro
        $ItemApiAccessParams = @{
            Uri = "$JssUrl/JSSResource/users/name/$EncodedUserPrincipalName";
            Method = 'GET';
            Headers = @{ 
                Authorization = $AuthValue
                accept = "application/xml"
            }
        }
    
        # Let's talk to Jamf Pro
        $AllItems = Invoke-RestMethod @ItemApiAccessParams
    
        # Get all mobile devices
        $GetAllItems = $AllItems.user.links.mobile_devices.mobile_device

        $UserItemID = $GetAllItems.id
        $UserItemName = $GetAllItems.name

        if ($UserItemID) { 

            $TmpListOfItems = New-Object -TypeName PSObject 
            $TmpListOfItems | Add-Member -Type NoteProperty -Name id -Value $UserItemID 
            $TmpListOfItems | Add-Member -Type NoteProperty -Name name -Value $UserItemName
            $TmpListOfItems | Add-Member -Type NoteProperty -Name user -Value $User
    
            $FullListOfItems += $TmpListOfItems

        } Else {

            Write-Host "$User does not have mobile devices assigned"
        }
    
    
      }else{
    
        Write-Output "$User does not exist in Jamf Pro"
    
      }
}

$FullListOfItems | FT -AutoSize

####################################################
# Part 5: The Action
####################################################

# Loop through each ID    
ForEach($Item in $FullListOfItems) { 
        
    # Get the ID and the name of the mobile device
    $ItemID = $Item.id
    $ItemName = $Item.name

    # Let's prepare to talk to Jamf Pro
    $ItemApiAccessParamsDevice = @{
        Uri = "$JssUrl/JSSResource/mobiledevicecommands/command/$CommandToSend";
        Method = 'POST';
        Headers = @{
            Authorization = $AuthValue
            accept = "application/xml"
        };
        Body = "<mobile_device_command><lost_mode_message>Device has been reported as Lost</lost_mode_message><mobile_devices><mobile_device><id>$ItemID</id></mobile_device></mobile_devices></mobile_device_command>"
    }

    # Let's talk to Jamf Pro
    $ResultCommand = Invoke-RestMethod @ItemApiAccessParamsDevice

    # Show the user name
    $UserPrincipalName

    # Show the results of the API call
    $ResultCommand.mobile_device_command.command
    $ResultCommand.mobile_device_command.mobile_devices.mobile_device.id
    $ResultCommand.mobile_device_command.mobile_devices.mobile_device.management_id

}