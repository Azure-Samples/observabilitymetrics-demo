#!/bin/bash

prefix=$1
location=$2

tenant_Id=$3
subscriptionId=$4
client_Id=$5
client_Secret=$6

cluster_Url=$7
dbName=$8

METRICS_FOLDER_PATH=$9 ## json template path

## az login ## --identity
## az account set -s $subscriptionId

echo $subscriptionId
echo $prefix

az config set extension.use_dynamic_install=yes_without_prompt

echo "clientID: $client_Id"
echo "tenantID: $tenant_Id"

az grafana create --name $prefix-grafana --resource-group $prefix-RG --location $location --skip-role-assignments false --skip-system-assigned-identity false
sleep 5

# az grafana update  --name $prefix-grafana --api-key Enabled
# az grafana api-key create --key $prefix-grafana-api-key --name $prefix-grafana

# echo "Managed Grafana: waiting for key to activate..."
# sleep 5

echo "Managed Grafana: Creating folders..."
az grafana folder create --name $prefix-grafana --title ObservabilityDashboard

echo "Managed Grafana: Waiting for folder creation..."
sleep 5

echo "Managed Grafana: Creating Data Explorer Datasource"
az grafana data-source create -n $prefix-grafana --definition '{
  "name": "Observability Metrics Data Source",
  "type": "grafana-azure-data-explorer-datasource",
  "typeLogoUrl": "public/plugins/grafana-azure-data-explorer-datasource/img/logo.png",
  "access": "proxy",
  "url": "api/datasources/proxy/2",
  "password": "",
  "user": "",
  "database": "",
  "basicAuth": false,
  "isDefault": false,
  "jsonData": {
    "clientId": "'"$client_Id"'",
    "clusterUrl": "'"$cluster_Url"'",
    "dataConsistency": "strongconsistency",
    "defaultDatabase": "'"$dbName"'",
    "defaultEditorMode": "visual",
    "schemaMappings": [],
    "tenantId": "'"$tenant_Id"'"
    },
  "secureJsonData": {"clientSecret": "'"$client_Secret"'"},
  "readOnly": false
}'

echo "Managed Grafana: Grab the UID of the Azure Data Explorer data source..."
response=$(az grafana data-source show --data-source "Observability Metrics Data Source" --name $prefix-grafana)
uid=$( jq -r  '.uid' <<< "$response" )
echo $uid

echo $METRICS_FOLDER_PATH
# Populates the dashboards with the data source UID
function populate_datasource_uid() {
  FILE_LIST="$METRICS_FOLDER_PATH/*"
  for file in $FILE_LIST 
    do 
        echo "Managed Grafana: Updating datasource uid for $file file"
        echo "$( jq --arg uid "$uid" '.dashboard.panels[].datasource |= if (.type=="grafana-azure-data-explorer-datasource") then (.uid=$uid) else . end' $file)" > $file
        echo "$( jq --arg uid "$uid" '.dashboard.panels[].targets[]?.datasource |= if (.type=="grafana-azure-data-explorer-datasource") then (.uid=$uid) else . end' $file)" > $file
        echo "$( jq --arg dbName "$dbName" '.dashboard.panels[].targets[]?.database = $dbName' $file)" > $file
        echo "$( jq --arg uid "$uid" '.dashboard.templating.list[].datasource |= if (.type=="grafana-azure-data-explorer-datasource") then (.uid=$uid) else . end' $file)" > $file
        sleep 2
    done
}

populate_datasource_uid $uid $METRICS_FOLDER_PATH

function import_dashboards() {
  FILE_LIST="$METRICS_FOLDER_PATH/*"
  for file in $FILE_LIST 
    do 
        echo "Managed Grafana: Importing dashboard for $file file"
        az grafana dashboard update -g $prefix-RG -n $prefix-grafana --folder ObservabilityDashboard --overwrite true --definition @$file
        sleep 2
    done
}

import_dashboards $METRICS_FOLDER_PATH Metrics

## update drill down links
echo "Update drill down links"
endpoint=$(az grafana show --name $prefix-grafana --resource-group $prefix-RG -o tsv --query properties.endpoint)
echo $endpoint
queryparams="?orgId=1\${__url_time_range}&var-selecteddate=\${__data.fields.date}&\${Region:queryparam}&\${Subscriptions:queryparam}&\${Solution:queryparam}"

storageuid=$(az grafana dashboard list --name $prefix-grafana --resource-group $prefix-RG  --query "[?contains(@.title, 'Storage')].uid | [1]" -o tsv)
storagedrilldown=$endpoint/d/$storageuid/storage$queryparams
echo $storagedrilldown


keyvaultuid=$(az grafana dashboard list --name $prefix-grafana --resource-group $prefix-RG --query "[?contains(@.title, 'Keyvault')].uid" -o tsv)
keyvaultdrilldown=$endpoint/d/$keyvaultuid/keyvault$queryparams
echo $keyvaultdrilldown

aksuid=$(az grafana dashboard list --name $prefix-grafana --resource-group $prefix-RG --query "[?contains(@.title, 'AksServerNode')].uid" -o tsv)
aksdrilldown=$endpoint/d/$aksuid/aksservernode$queryparams
echo $aksdrilldown

firewalluid=$(az grafana dashboard list --name $prefix-grafana --resource-group $prefix-RG --query "[?contains(@.title, 'Firewalls')].uid" -o tsv)
firewalldrilldown=$endpoint/d/$firewalluid/firewalls$queryparams
echo $firewalldrilldown

lbuid=$(az grafana dashboard list --name $prefix-grafana --resource-group $prefix-RG --query "[?contains(@.title, 'Loadbalancer')].uid" -o tsv)
lbdrilldown=$endpoint/d/$lbuid/loadbalancer$queryparams
echo $lbdrilldown

cosmosdbuid=$(az grafana dashboard list --name $prefix-grafana --resource-group $prefix-RG --query "[?contains(@.title, 'CosmosDB')].uid" -o tsv)
cosmosdbdrilldown=$endpoint/d/$cosmosdbuid/cosmosdb-details$queryparams
echo $cosmosdbdrilldown

jsonfile=$METRICS_FOLDER_PATH/AzureResourceObservability-1679088842231.json
echo $jsonfile

echo "$(jq --arg storagedrilldown "$storagedrilldown" '.dashboard.panels[].fieldConfig.defaults.links[]? |= if(.title=="storage drill down details") then .url=$storagedrilldown else . end' $jsonfile)" > $jsonfile

echo  "$(jq --arg keyvaultdrilldown "$keyvaultdrilldown" '.dashboard.panels[].fieldConfig.defaults.links[]? |= if(.title=="keyvault drill down details") then .url=$keyvaultdrilldown else . end' $jsonfile)" > $jsonfile
        
echo  "$(jq --arg aksdrilldown "$aksdrilldown" '.dashboard.panels[].fieldConfig.defaults.links[]? |= if(.title=="aksservernode drill down details") then .url=$aksdrilldown else . end' $jsonfile)" > $jsonfile

echo  "$(jq --arg firewalldrilldown "$keyvaultdrilldown" '.dashboard.panels[].fieldConfig.defaults.links[]? |= if(.title=="firewall drill down details") then .url=$firewalldrilldown else . end' $jsonfile)" > $jsonfile

echo  "$(jq --arg lbdrilldown "$lbdrilldown" '.dashboard.panels[].fieldConfig.defaults.links[]? |= if(.title=="loadbalancer drill down details") then .url=$lbdrilldown else . end' $jsonfile)" > $jsonfile

echo  "$(jq --arg cosmosdbdrilldown "$cosmosdbdrilldown" '.dashboard.panels[].fieldConfig.defaults.links[]? |= if(.title=="cosmosdb drill down details") then .url=$cosmosdbdrilldown else . end' $jsonfile)" > $jsonfile


echo "Managed Grafana: Importing dashboard for $jsonfile file"
az grafana dashboard update -g $prefix-RG -n $prefix-grafana --folder ObservabilityDashboard --overwrite true --definition @$jsonfile
sleep 2