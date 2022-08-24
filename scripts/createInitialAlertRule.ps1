$TenantId = '02a141ef-0ce3-40b2-a174-d5e8bfc12345'
$SubscriptionId = 'a0043f78-f6a3-433e-96a2-59ae2b712345'

$LocationName = 'eastus'

$ClientId = 'fe0aac98-d3ec-47ce-b4f7-edd5df012345'
$ClientSecret='mni7Q~3jYaZdbDoVZA1KiwXbEmmeucBz12345'

$ResourceGroup = 'AADGroupsNameChangeRG'
$LogAnalyticsWorkspace = 'AADGroupsNameChangeLogAnalyticsWS'
$ActionGroupName = 'AADGroupsNameChangeEmailNotifications'

$AlertRulesName = 'AADGroupNameChange4'


$FinalJSON = @"
{
    "name": "$AlertRulesName",
    "type": "microsoft.insights/scheduledqueryrules",
    "location": "$LocationName",
    "properties": {
        "description": "Alert rule for Groups Name Changes in AAD",
        "displayName": "$AlertRulesName",
        "enabled": "true",
        "provisioningState": "Succeeded",
        "source": {
            "query": "AuditLogs 
                | where OperationName contains \"Add member to group\" or OperationName contains \"Remove member from group\" 
                | extend RemoveFromGroup_ = tostring(parse_json(tostring(parse_json(tostring(TargetResources[0].modifiedProperties))[1].oldValue))) 
                | extend AddToGroup_ = tostring(parse_json(tostring(parse_json(tostring(TargetResources[0].modifiedProperties))[1].newValue)))
                | where RemoveFromGroup_ contains \"jamf_amer_usa_ps\" or AddToGroup_ contains \"jamf_amer_usa_ps\"
                | extend userPrincipalName_ = tostring(TargetResources[0].userPrincipalName)
                | project ActivityDateTime, ActivityDisplayName, AddToGroup_, RemoveFromGroup_, userPrincipalName_",
            "dataSourceId": "/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroup/providers/microsoft.operationalinsights/workspaces/$LogAnalyticsWorkspace",
            "queryType": "ResultCount"
        },
        "schedule": {
            "frequencyInMinutes": 60,
            "timeWindowInMinutes": 60
        },
        "action": {
            "severity": "3",
            "aznsAction": {
                "actionGroup": ["/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/microsoft.insights/actionGroups/$ActionGroupName"]
            },
            "trigger": {
                "thresholdOperator": "GreaterThanOrEqual",
                "threshold": 1
            },
            "odata.type": "Microsoft.WindowsAzure.Management.Monitoring.Alerts.Models.Microsoft.AppInsights.Nexus.DataContracts.Resources.ScheduledQueryRules.AlertingAction"
        }
    }
}
"@


# Get Token for auth
$TokenParams = @{
    Uri = "https://login.microsoftonline.com/$TenantId/oauth2/token";
    Method = 'POST';
    Body = @{ 
        grant_type = 'client_credentials'; 
        resource = 'https://management.azure.com/'; 
        client_id = $ClientId; 
        client_secret = $ClientSecret
    }
}

$TokenResult = Invoke-RestMethod @TokenParams
$Token = $TokenResult.access_token


# Invoke the REST API to change the query for the Alert Rule
$RestParams = @{
    URI = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/microsoft.insights/scheduledqueryrules/$AlertRulesName" + "?api-version=2018-04-16"
    Method = 'PUT'
    Headers = @{
        'Content-Type'='application/json';
         'Authorization'='Bearer ' + $Token
    }
}


Invoke-RestMethod @RestParams -Body $FinalJSON

