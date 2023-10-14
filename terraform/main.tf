#Set the terraform required version
terraform {
  required_version = "~> 1.0"
  # Configure the Azure Provider
  required_providers {
    # It is recommended to pin to a given version of the Provider
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0.0"
    }
    local = {
      version = "~> 1.4"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  # It is recommended to pin to a given version of the Provider
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
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

resource "azurerm_log_analytics_workspace" "loganalyticsai1" {
  name                = "${var.prefix}-serverless-law-ai-first"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags = {
    sample = "serverless-keyvault-secret-rotation-handling"
  }
}

resource "azurerm_application_insights" "logging" {
  name                = "${var.prefix}-serverless-ai-first"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  workspace_id        = azurerm_log_analytics_workspace.loganalyticsai1.id
  application_type    = "web"
  tags = {
    sample = "serverless-keyvault-secret-rotation-handling"
  }
}

resource "azurerm_log_analytics_workspace" "loganalyticsai2" {
  name                = "${var.prefix}-serverless-law-ai-second"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags = {
    sample = "serverless-keyvault-secret-rotation-handling"
  }
}

resource "azurerm_application_insights" "logging2" {
  name                = "${var.prefix}-serverless-ai-second"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  workspace_id        = azurerm_log_analytics_workspace.loganalyticsai2.id
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

resource "azurerm_service_plan" "fxnapp" {
  name                = "${var.prefix}-serverless-serviceplan"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku_name            = "Y1"
  os_type             = "Windows"

  tags = {
    sample = "serverless-keyvault-secret-rotation-handling"
  }
}

resource "azurerm_windows_function_app" "fxn" {
  name                        = "${var.prefix}-serverless-functionapp"
  resource_group_name         = azurerm_resource_group.rg.name
  location                    = azurerm_resource_group.rg.location
  service_plan_id             = azurerm_service_plan.fxnapp.id
  storage_account_name        = azurerm_storage_account.fxnstor.name
  storage_account_access_key  = azurerm_storage_account.fxnstor.primary_access_key
  functions_extension_version = "~4"
  site_config {}
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
      "Get",
      "List",
      "Create",
      "Delete"
    ]

    secret_permissions = [
      "Get",
      "List",
      "Set",
      "Delete",
      "Purge"
    ]
  }

  # access policy for azure function
  access_policy {
    object_id = azurerm_windows_function_app.fxn.identity[0].principal_id
    tenant_id = data.azurerm_client_config.current.tenant_id

    secret_permissions = [
      "Get"
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
  name                = "${var.prefix}-serverless-law-logicapp"
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
    vaults_rollingvault_name = {
      value = azurerm_key_vault.shared_key_vault.name
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
      value = azurerm_windows_function_app.fxn.id
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

resource "azurerm_resource_group_template_deployment" "logicapp" {
  name                = "${var.prefix}-serverless-la-deployment1"
  resource_group_name = azurerm_resource_group.rg.name
  deployment_mode     = "Incremental"
  parameters_content      = jsonencode(local.parameters_body)
  template_content         = <<LOGICAPP
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
        "vaults_rollingvault_name": {
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
                                "Get_Current_AppSettings": {
                                    "inputs": {
                                        "authentication": {
                                            "type": "ManagedServiceIdentity"
                                        },
                                        "method": "POST",
                                        "uri": "[concat('https://management.azure.com', parameters('fxn_id'), '/config/appsettings/list?api-version=2021-02-01')]"
                                    },
                                    "runAfter": {
                                        "NewSecretVersion": [
                                            "Succeeded"
                                        ]
                                    },
                                    "type": "Http"
                                },
                                "NewSecretVersion": {
                                    "inputs": "@triggerBody()?['data'].Version",
                                    "runAfter": {},
                                    "type": "Compose"
                                },
                                "Parse_AppSettings_Response": {
                                    "inputs": {
                                        "content": "@body('Get_Current_AppSettings')",
                                        "schema": {
                                            "properties": {
                                                "id": {
                                                    "type": "string"
                                                },
                                                "location": {
                                                    "type": "string"
                                                },
                                                "name": {
                                                    "type": "string"
                                                },
                                                "properties": {
                                                    "properties": {
                                                        "APPINSIGHTS_INSTRUMENTATIONKEY": {
                                                            "type": "string"
                                                        },
                                                        "AzureWebJobsDashboard": {
                                                            "type": "string"
                                                        },
                                                        "AzureWebJobsStorage": {
                                                            "type": "string"
                                                        },
                                                        "FUNCTIONS_EXTENSION_VERSION": {
                                                            "type": "string"
                                                        },
                                                        "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING": {
                                                            "type": "string"
                                                        },
                                                        "WEBSITE_CONTENTSHARE": {
                                                            "type": "string"
                                                        }
                                                    },
                                                    "type": "object"
                                                },
                                                "tags": {
                                                    "properties": {
                                                        "sample": {
                                                            "type": "string"
                                                        }
                                                    },
                                                    "type": "object"
                                                },
                                                "type": {
                                                    "type": "string"
                                                }
                                            },
                                            "type": "object"
                                        }
                                    },
                                    "runAfter": {
                                        "Get_Current_AppSettings": [
                                            "Succeeded"
                                        ]
                                    },
                                    "type": "ParseJson"
                                },
                                "Update_secret_version_app_setting": {
                                    "inputs": {
                                        "authentication": {
                                            "type": "ManagedServiceIdentity"
                                        },
                                        "body": {
                                            "properties": "[concat('@setProperty(body(''Parse_AppSettings_Response'')?[''properties''], ''APPINSIGHTS_INSTRUMENTATIONKEY'', concat(''@Microsoft.KeyVault(SecretUri=https://'', ''',parameters('vaults_rollingvault_name'), ''', ''.vault.azure.net/secrets/appinsights-instrumentationkey/'', outputs(''NewSecretVersion''), '')''))')]"
                                        },
                                        "method": "PUT",
                                        "uri": "[concat('https://management.azure.com', parameters('fxn_id'), '/config/appsettings?api-version=2021-02-01')]"
                                    },
                                    "runAfter": {
                                        "Parse_AppSettings_Response": [
                                            "Succeeded"
                                        ]
                                    },
                                    "type": "Http"
                                }
                            },
                            "else": {
                                "actions": {
                                    "Terminate": {
                                        "inputs": {
                                            "runStatus": "Cancelled"
                                        },
                                        "runAfter": {},
                                        "type": "Terminate"
                                    }
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
        "logicAppServicePrincipalId": {
            "type": "string",
            "value": "[reference(concat('Microsoft.Logic/workflows/',parameters('logicapp_keyvaulthandler_name')), '2019-05-01', 'Full').identity.principalId]"
        }
    }
}
LOGICAPP
}

##################################################################################
# Role Assignment
##################################################################################
resource "azurerm_role_assignment" "laToFunction" {
  scope                = azurerm_windows_function_app.fxn.id
  role_definition_name = "Website Contributor"
  principal_id         = jsondecode(azurerm_resource_group_template_deployment.logicapp.output_content).logicAppServicePrincipalId.value
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
az functionapp config appsettings set -n ${azurerm_windows_function_app.fxn.name} -g ${azurerm_resource_group.rg.name} --settings "APPINSIGHTS_INSTRUMENTATIONKEY=""@Microsoft.KeyVault(SecretUri=https://${azurerm_key_vault.shared_key_vault.name}.vault.azure.net/secrets/${azurerm_key_vault_secret.logging_app_insights_key.name}/)""" > /dev/null
az functionapp config set --net-framework-version v6.0 -n ${azurerm_windows_function_app.fxn.name} -g ${azurerm_resource_group.rg.name}

echo "Deploying function code ..."
cd ../src ; func azure functionapp publish ${azurerm_windows_function_app.fxn.name} --csharp > /dev/null ; cd ../terraform

echo "Application Insights keys:"
terraform state pull | jq -r '.outputs | to_entries | .[] | { instance: .key, key: .value.value } '

echo
echo "Done!"
CONTENT
}
