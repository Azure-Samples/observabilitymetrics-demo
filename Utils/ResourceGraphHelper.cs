
using Azure.Identity;
using Azure.ResourceManager;
using Azure.ResourceManager.ResourceGraph;
using Azure.ResourceManager.ResourceGraph.Models;
using Observability.Utils.Data;
using Microsoft.Azure.Management.ResourceGraph.Models;
using Newtonsoft.Json;
using System.Text;
using Microsoft.Identity.Client;
using Azure.Core;
using System.Net.Http.Headers;
using Newtonsoft.Json.Linq;
using Microsoft.Azure.Management.ResourceManager.Fluent.Models;

namespace Observability.Utils
{
    //TODO: Make methods asynchronous
    public class ResourceGraphHelper
    {
        private static HttpClient _httpClient = new HttpClient();

        ArmClient client;

        public ResourceGraphHelper(IConfiguration config)
        {

            client = new ArmClient(
                new ManagedIdentityCredential(config.GetValue<string>("msiclientId")));
        }

        public ResourceQueryResult QueryGraph(string subscriptionId, string resourceType)
        {
            var tenant = client.GetTenants().FirstOrDefault();

            string query = $"Resources | where subscriptionId == '{subscriptionId}' | where type == '{resourceType}' | distinct id, name, subscriptionId, location | sort by location asc";

            var request = new QueryRequest(query);

            var queryContent = new ResourceQueryContent(query);

            var response = tenant.GetResources(queryContent);

            var result = response.Value;

            var resources = new List<AzureResource>();

            return result;
        }
        
        public async Task<String> GetTenantDomainAsync(IConfiguration config)
        {
            //var tenant = client.GetTenants().FirstOrDefault().Id;
            string managementUrl = "https://management.azure.com/tenants?api-version=2022-12-01";

            using HttpRequestMessage httpRequest = new HttpRequestMessage(HttpMethod.Get, managementUrl);

            string userAssignedClientId = config.GetValue<string>("msiclientId");
            var credential = new DefaultAzureCredential(new DefaultAzureCredentialOptions { ManagedIdentityClientId = userAssignedClientId });
            var accessToken = credential.GetToken(new TokenRequestContext(new[] { "https://management.azure.com/" }));

            httpRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken.Token);

            //httpRequest.Content = new StringContent(jsonResouces, Encoding.UTF8, "application/json");

            using var response = await _httpClient.SendAsync(httpRequest);

            var result = await response.Content.ReadAsStringAsync();

            JToken responseJson = JToken.Parse(result);
            JArray value = (JArray)responseJson["value"];


            /*foreach (JToken tenantid in value)
            {
                string id = tenantid["tenantId"].ToString();
                if (id == tenant.ToString())
                {
                    string defaultDomain = tenantid["defaultDomain"].ToString();
                    return defaultDomain;
                }
            }

            return "Default Domain Name not found for Tenant ID";*/

            string defaultDomain = value[0]["defaultDomain"].ToString();
            return defaultDomain;

        }

        public string GetSubscriptionName(string subscriptionId)

        {
            var tenant = client.GetTenants().FirstOrDefault();
            string query = $"resourcecontainers | where id == \"/subscriptions/{subscriptionId}\" | project name";

            var request = new QueryRequest(query);

            var queryContent = new ResourceQueryContent(query);

            var response = tenant.GetResources(queryContent);
            var result = response.Value.Data;

            var stringSub = Encoding.ASCII.GetString(result);

            List<dynamic> results = JsonConvert.DeserializeObject<List<dynamic>>(stringSub);

            var subscriptionName = results[0].name;

            return subscriptionName;
        }
    }
}