resource "azurerm_resource_group" "rg" {
  name     = "${var.resource_prefix}-rg"
  location = var.azure_region
}

# 1. Network Resources
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.resource_prefix}-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.240.0.0/16"]
}

resource "azurerm_subnet" "aks_subnet" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.240.0.0/22"] # Supports up to 1024 IP addresses
}

# 2. Managed Identity for the AKS Control Plane
resource "azurerm_user_assigned_identity" "aks_identity" {
  name                = "${var.resource_prefix}-identity"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# 3. Role Assignment: Network Contributor
# The AKS Control Plane identity needs to manage the subnet in order to configure CNI Overlay networking.
resource "azurerm_role_assignment" "network_contributor" {
  scope                = azurerm_subnet.aks_subnet.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks_identity.principal_id
}

# 4. AKS Cluster
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.resource_prefix}-cluster"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "${var.resource_prefix}-k8s"

  # Use the User-Assigned Managed Identity for the control plane
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks_identity.id]
  }

  default_node_pool {
    name           = "systempool"
    node_count     = var.system_node_count
    vm_size        = var.system_node_vm_size
    vnet_subnet_id = azurerm_subnet.aks_subnet.id
    type           = "VirtualMachineScaleSets"
    os_sku         = "AzureLinux"
  }

  # Azure CNI Overlay Configuration
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    pod_cidr            = "192.168.0.0/16"
    service_cidr        = "172.16.0.0/16"
    dns_service_ip      = "172.16.0.10"
    network_policy      = "azure" # Azure Network Policies
  }

  # Modern AKS Features for learning
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  tags = {
    Environment = "Learning"
    ManagedBy   = "Terraform"
  }

  depends_on = [
    azurerm_role_assignment.network_contributor
  ]
}

# 5. Key Vault and Security Configuration
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "kv" {
  name                        = "${var.resource_prefix}-kv"
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"
  enable_rbac_authorization   = true # Use modern Azure RBAC instead of legacy access policies
  purge_protection_enabled    = false

  tags = {
    Environment = "Learning"
    ManagedBy   = "Terraform"
  }
}

# 6. Managed Identity for the Application Pod
resource "azurerm_user_assigned_identity" "app_identity" {
  name                = "${var.resource_prefix}-app-identity"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# 7. Role Assignment: Grant Key Vault Secrets User to App Identity
resource "azurerm_role_assignment" "app_kv_secrets_user" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.app_identity.principal_id
}

# 8. Federated Identity Credential for AKS Workload Identity
# Connects the K8s Service Account 'llm-service-sa' to the Azure Managed Identity
resource "azurerm_federated_identity_credential" "app_federated_credential" {
  name                = "${var.resource_prefix}-app-fed"
  resource_group_name = azurerm_resource_group.rg.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.app_identity.id
  subject             = "system:serviceaccount:default:llm-service-sa"
}

# 9. Azure Container Registry (ACR)
resource "azurerm_container_registry" "acr" {
  name                = "${replace(var.resource_prefix, "-", "")}acr"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Standard"
  admin_enabled       = false
}

# 10. Role Assignment: Allow AKS to pull images from ACR
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                            = azurerm_container_registry.acr.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}

