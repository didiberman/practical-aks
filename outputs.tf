output "resource_group_name" {
  description = "The name of the resource group in which the resources are created"
  value       = azurerm_resource_group.rg.name
}

output "kubernetes_cluster_name" {
  description = "The name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.name
}

output "oidc_issuer_url" {
  description = "The OIDC issuer URL for Workload Identity integration"
  value       = azurerm_kubernetes_cluster.aks.oidc_issuer_url
}

output "kube_config_command" {
  description = "The Azure CLI command to retrieve the kubeconfig context for this cluster"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.rg.name} --name ${azurerm_kubernetes_cluster.aks.name}"
}

output "app_identity_client_id" {
  description = "The client ID of the user-assigned identity for the application pod"
  value       = azurerm_user_assigned_identity.app_identity.client_id
}

output "azure_openai_endpoint" {
  description = "The endpoint of the Azure OpenAI account"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "azure_openai_deployment_name" {
  description = "The Azure OpenAI deployment name used by the application"
  value       = var.azure_openai_deployment_name
}

output "azure_openai_api_version" {
  description = "The Azure OpenAI data-plane API version used by the application"
  value       = var.azure_openai_api_version
}

output "acr_name" {
  description = "The name of the Azure Container Registry"
  value       = azurerm_container_registry.acr.name
}

output "acr_login_server" {
  description = "The login server URI of the Azure Container Registry"
  value       = azurerm_container_registry.acr.login_server
}
