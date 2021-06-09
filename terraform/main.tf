#Set the terraform required version
terraform {
  required_version = "~> 1.0.0"
  # Configure the Azure Provider
  required_providers {
    # It is recommended to pin to a given version of the Provider
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 2.62.0"
    }
    local = {
      version = "~> 1.4"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  # It is recommended to pin to a given version of the Provider
  features {}
}

# Make client_id, tenant_id, subscription_id and object_id variables
data "azurerm_client_config" "current" {}

variable "prefix" {
  type = string
}

variable "location" {
  type        = string
  description = "Azure region where to create resources."
  default     = "West US 2"
}

variable "sp_client_id" {
  type        = string
  description = "The Client ID for the service principal to use when setting up the Logic App connector to Event Grid"
}

variable "sp_client_secret" {
  type        = string
  description = "The Client Secret for the service principal to use when setting up the Logic App connector to Event Grid"
}

resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}-serverless-sample"
  location = var.location
  tags = {
    sample = "serverless-keyvault-secret-rotation-handling"
  }
}

##################################################################################
# AppInsights
##################################################################################

resource "azurerm_application_insights" "logging" {
  name                = "${var.prefix}-serverless-ai-first"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  application_type    = "web"
  tags = {
    sample = "serverless-keyvault-secret-rotation-handling"
  }
}

resource "azurerm_application_insights" "logging2" {
  name                = "${var.prefix}-serverless-ai-second"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  application_type    = "web"
  tags = {
    sample = "serverless-keyvault-secret-rotation-handling"
  }
}

##################################################################################
# Function App 
##################################################################################

resource "azurerm_storage_account" "fxnstor" {
  name                     = lower("${var.prefix}stor")
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  tags = {
    sample = "serverless-keyvault-secret-rotation-handling"
  }
}

resource "azurerm_app_service_plan" "fxnapp" {
  name                = "${var.prefix}-serverless-serviceplan"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  kind                = "functionapp"
  sku {
    tier = "Dynamic"
    size = "Y1"
  }
  tags = {
    sample = "serverless-keyvault-secret-rotation-handling"
  }
}

resource "azurerm_function_app" "fxn" {
  name                       = "${var.prefix}-serverless-functionapp"
  resource_group_name        = azurerm_resource_group.rg.name
  location                   = azurerm_resource_group.rg.location
  app_service_plan_id        = azurerm_app_service_plan.fxnapp.id
  storage_account_name       = azurerm_storage_account.fxnstor.name
  storage_account_access_key = azurerm_storage_account.fxnstor.primary_access_key
  version                    = "~3"
  identity {
    type = "SystemAssigned"
  }

  lifecycle {
    ignore_changes = [
      app_settings
    ]
  }
  tags = {
    sample = "serverless-keyvault-secret-rotation-handling"
  }
}

##################################################################################
# Key Vault
##################################################################################

resource "azurerm_key_vault" "shared_key_vault" {
  name                = "${var.prefix}-serverless-kv"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tenant_id           = data.azurerm_client_config.current.tenant_id

  sku_name = "standard"

  # access policy for creator
  access_policy {
    object_id = data.azurerm_client_config.current.object_id
    tenant_id = data.azurerm_client_config.current.tenant_id

    key_permissions = [
      "get",
      "list",
      "create",
      "delete"
    ]

    secret_permissions = [
      "get",
      "list",
      "set",
      "delete"
    ]
  }

  # access policy for azure function
  access_policy {
    object_id = azurerm_function_app.fxn.identity[0].principal_id
    tenant_id = data.azurerm_client_config.current.tenant_id

    secret_permissions = [
      "get",
    ]
  }
  tags = {
    sample = "serverless-keyvault-secret-rotation-handling"
  }
}

#############################
# Secrets
#############################

resource "azurerm_key_vault_secret" "logging_app_insights_key" {
  name         = "appinsights-instrumentationkey"
  value        = azurerm_application_insights.logging.instrumentation_key
  key_vault_id = azurerm_key_vault.shared_key_vault.id
  tags = {
    sample = "serverless-keyvault-secret-rotation-handling"
  }
}

##################################################################################
# Logic App
##################################################################################

resource "azurerm_log_analytics_workspace" "loganalytics" {
  name                = "${var.prefix}-serverless-law"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags = {
    sample = "serverless-keyvault-secret-rotation-handling"
  }
}

locals {
  parameters_body = {
    logicapp_keyvaulthandler_name = {
      value = "${var.prefix}-serverless-la"
    },
    vaults_rollingvault_externalid = {
      value = azurerm_key_vault.shared_key_vault.id
    },
    subscriptionId = {
      value = data.azurerm_client_config.current.subscription_id
    },
    diagnosticSettings_name = {
      value = azurerm_log_analytics_workspace.loganalytics.name
    },
    log_analytics_workspace_id = {
      value = azurerm_log_analytics_workspace.loganalytics.id
    },
    fxn_id = {
      value = azurerm_function_app.fxn.id
    },
    keysToWatch = {
      value = [azurerm_key_vault_secret.logging_app_insights_key.name]
    },
    client_id = {
      value = var.sp_client_id
    },
    client_secret = {
      value = var.sp_client_secret
    }
  }
}

resource "azurerm_template_deployment" "logicapp" {
  name                = "${var.prefix}-serverless-la-deployment"
  resource_group_name = azurerm_resource_group.rg.name
  deployment_mode     = "Incremental"
  parameters_body     = jsonencode(local.parameters_body)
  template_body       = <<DEPLOY
{
	"$schema": "https://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#",
	"contentVersion": "1.0.0.0",
	"parameters": {
		"logicapp_keyvaulthandler_name": {
			"type": "String"
		},
		"vaults_rollingvault_externalid": {
			"type": "String"
		},
		"subscriptionId": {
			"type": "String"
		},
		"location": {
			"defaultValue": "[resourceGroup().location]",
			"type": "String"
		},
		"diagnosticSettings_name": {
			"type": "String"
		},
		"log_analytics_workspace_id": {
			"type": "String"
		},
		"connections_azureeventgrid_name": {
			"defaultValue": "azureeventgrid",
			"type": "String"
		},
		"fxn_id": {
			"type": "String"
		},
		"keysToWatch": {
			"type": "array"
		},
		"client_id": {
			"type": "string"
		},
		"client_secret": {
			"type": "string"
		}
	},
	"variables": {},
	"resources": [
		{
			"type": "Microsoft.Web/connections",
			"apiVersion": "2016-06-01",
			"name": "[parameters('connections_azureeventgrid_name')]",
			"location": "[parameters('location')]",
			"tags": {
				"sample": "serverless-keyvault-secret-rotation-handling"
			},
			"properties": {
				"displayName": "Event Grid Connection",
				"customParameterValues": {},
				"api": {
					"id": "[concat('/subscriptions/', parameters('subscriptionId'), '/providers/Microsoft.Web/locations/', parameters('location'), '/managedApis/azureeventgrid')]"
				},
				"parameterValues": {
					"token:TenantId": "[subscription().tenantId]",
					"token:clientId": "[parameters('client_id')]",
					"token:clientSecret": "[parameters('client_secret')]",
					"token:grantType": "client_credentials"
				}
			}
		},
		{
			"type": "Microsoft.Logic/workflows",
			"apiVersion": "2017-07-01",
			"name": "[parameters('logicapp_keyvaulthandler_name')]",
			"tags": {
				"sample": "serverless-keyvault-secret-rotation-handling"
			},
			"location": "[parameters('location')]",
			"dependsOn": [
				"[parameters('connections_azureeventgrid_name')]"
			],
			"location": "[parameters('location')]",
			"identity": {
				"type": "SystemAssigned"
			},
			"properties": {
				"state": "Enabled",
				"definition": {
					"$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
					"contentVersion": "1.0.0.0",
					"parameters": {
						"$connections": {
							"defaultValue": {},
							"type": "Object"
						}
					},
					"triggers": {
						"When_a_key_vault_key_is_updated": {
							"splitOn": "@triggerBody()",
							"type": "ApiConnectionWebhook",
							"inputs": {
								"body": {
									"properties": {
										"destination": {
											"endpointType": "webhook",
											"properties": {
												"endpointUrl": "@{listCallbackUrl()}"
											}
										},
										"filter": {
											"includedEventTypes": [
												"Microsoft.KeyVault.SecretNewVersionCreated"
											]
										},
										"topic": "[parameters('vaults_rollingvault_externalid')]"
									}
								},
								"host": {
									"connection": {
										"name": "@parameters('$connections')['azureeventgrid']['connectionId']"
									}
								},
								"path": "[concat('/subscriptions/@{encodeURIComponent(''', parameters('subscriptionId'), ''')}/providers/@{encodeURIComponent(''Microsoft.KeyVault.vaults'')}/resource/eventSubscriptions')]",
								"queries": {
									"x-ms-api-version": "2017-06-15-preview"
								}
							}
						}
					},
					"actions": {
						"Condition": {
							"actions": {
								"Trigger_application_of_app_settings_(soft-restart_Function_App)": {
									"inputs": {
										"authentication": {
											"type": "ManagedServiceIdentity"
										},
										"method": "POST",
										"uri": "[concat('https://management.azure.com', parameters('fxn_id'), '/restart?softRestart=true&synchronous=true&api-version=2019-08-01')]"
									},
									"runAfter": {},
									"type": "Http"
								}
							},
							"expression": {
								"and": [
									{
										"contains": [
											"@variables('keysToWatch')",
											"@triggerBody()?['subject']"
										]
									}
								]
							},
							"runAfter": {
								"Init_keysToWatch": [
									"Succeeded"
								]
							},
							"type": "If"
						},
						"Init_keysToWatch": {
							"inputs": {
								"variables": [
									{
										"name": "keysToWatch",
										"type": "array",
										"value": "[parameters('keysToWatch')]"
									}
								]
							},
							"runAfter": {},
							"type": "InitializeVariable"
						}
					},
					"outputs": {}
				},
				"parameters": {
					"$connections": {
						"value": {
							"azureeventgrid": {
								"connectionId": "[resourceId('Microsoft.Web/connections', parameters('connections_azureeventgrid_name'))]",
								"connectionName": "azureeventgrid",
								"id": "[concat('/subscriptions/', parameters('subscriptionId'), '/providers/Microsoft.Web/locations/', parameters('location'), '/managedApis/azureeventgrid')]"
							}
						}
					}
				}
			},
			"resources": [
				{
					"type": "providers/diagnosticSettings",
					"name": "[concat('Microsoft.Insights/', parameters('diagnosticSettings_name'))]",
					"dependsOn": [
						"[parameters('logicapp_keyvaulthandler_name')]"
					],
					"apiVersion": "2017-05-01-preview",
					"properties": {
						"name": "[parameters('diagnosticSettings_name')]",
						"workspaceId": "[parameters('log_analytics_workspace_id')]",
						"logs": [
							{
								"category": "WorkflowRuntime",
								"enabled": true,
								"retentionPolicy": {
									"days": 0,
									"enabled": false
								}
							}
						],
						"metrics": [
							{
								"category": "AllMetrics",
								"enabled": false,
								"retentionPolicy": {
									"days": 0,
									"enabled": false
								}
							}
						]
					}
				}
			]
		}
	],
	"outputs": {
		"LogicAppServicePrincipalId": {
			"type": "string",
			"value": "[reference(concat('Microsoft.Logic/workflows/',parameters('logicapp_keyvaulthandler_name')), '2019-05-01', 'Full').identity.principalId]"
		}
	}
}
DEPLOY
}

##################################################################################
# Role Assignment
##################################################################################
resource "azurerm_role_assignment" "laToFunction" {
  scope                = azurerm_function_app.fxn.id
  role_definition_name = "Website Contributor"
  principal_id         = azurerm_template_deployment.logicapp.outputs["logicAppServicePrincipalId"]
}

##################################################################################
# Outputs
##################################################################################

output "AppInsightsKey-First" {
  value     = azurerm_application_insights.logging.instrumentation_key
  sensitive = true
}

output "AppInsightsKey-Second" {
  value     = azurerm_application_insights.logging2.instrumentation_key
  sensitive = true
}

resource "local_file" "app_deployment_script" {
  filename = "./deploy_app.sh"
  content  = <<CONTENT
#!/bin/bash

echo "Setting app insights instrumentation key on function app ..."
az functionapp config appsettings set -n ${azurerm_function_app.fxn.name} -g ${azurerm_resource_group.rg.name} --settings "APPINSIGHTS_INSTRUMENTATIONKEY=""@Microsoft.KeyVault(SecretUri=https://${azurerm_key_vault.shared_key_vault.name}.vault.azure.net/secrets/${azurerm_key_vault_secret.logging_app_insights_key.name}/)""" > /dev/null

echo "Deploying function code ..."
cd ../src ; func azure functionapp publish ${azurerm_function_app.fxn.name} --csharp > /dev/null ; cd ../terraform

echo "Application Insights keys:"
terraform state pull | jq -r '.outputs | to_entries | .[] | { instance: .key, key: .value.value } '

echo
echo "Done!"
CONTENT
}
