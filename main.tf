resource "azurerm_resource_group" "rg" {
  name     = "${var.resource_prefix}-rg"
  location = var.azure_region
}

data "azurerm_client_config" "current" {}

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

# 5. Managed Identity for the Application Pod
resource "azurerm_user_assigned_identity" "app_identity" {
  name                = "${var.resource_prefix}-app-identity"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# 6. Azure OpenAI account and model deployment
resource "azurerm_cognitive_account" "openai" {
  name                          = "${var.resource_prefix}-openai"
  location                      = azurerm_resource_group.rg.location
  resource_group_name           = azurerm_resource_group.rg.name
  kind                          = "OpenAI"
  sku_name                      = "S0"
  custom_subdomain_name         = "${var.resource_prefix}-openai"
  local_auth_enabled            = false
  public_network_access_enabled = true

  tags = {
    Environment = "Learning"
    ManagedBy   = "Terraform"
  }
}

resource "azurerm_cognitive_deployment" "chat" {
  name                 = var.azure_openai_deployment_name
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = var.azure_openai_model_name
    version = var.azure_openai_model_version
  }

  scale {
    type     = "Standard"
    capacity = 1
  }
}

# 7. Role Assignment: Grant inference access to the App Identity
resource "azurerm_role_assignment" "app_openai_user" {
  scope                = azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services OpenAI User"
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

# 11. Managed Identity for GitHub Actions app deployments
resource "azurerm_user_assigned_identity" "github_actions_identity" {
  name                = "${var.resource_prefix}-github-actions-identity"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_federated_identity_credential" "github_actions_main" {
  name                = "${var.resource_prefix}-github-actions-main"
  resource_group_name = azurerm_resource_group.rg.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  parent_id           = azurerm_user_assigned_identity.github_actions_identity.id
  subject             = "repo:${var.github_repository}:ref:refs/heads/${var.github_actions_branch}"
}

resource "azurerm_role_assignment" "github_actions_acr_push" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.github_actions_identity.principal_id
}

resource "azurerm_role_assignment" "github_actions_reader" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.github_actions_identity.principal_id
}

# 12. Kubernetes and Helm Providers Configuration
provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
  }
}

# 13. Bootstrap ArgoCD via Helm
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.1.3"
  namespace        = "argocd"
  create_namespace = true

  set {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }
}

# 14. Deploy the application via ArgoCD Apps Helm chart
resource "helm_release" "argocd_apps" {
  name             = "argocd-apps"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argocd-apps"
  version          = "2.0.1"
  namespace        = "argocd"
  create_namespace = true

  values = [
    yamlencode({
      applications = {
        aks-learning-app = {
          namespace = "argocd"
          project   = "default"
          source = {
            repoURL        = "https://github.com/didiberman/practical-aks.git"
            targetRevision = "main"
            path           = "k8s/chart"
            helm = {
              parameters = [
                {
                  name  = "appIdentityClientId"
                  value = azurerm_user_assigned_identity.app_identity.client_id
                },
                {
                  name  = "azureOpenAI.endpoint"
                  value = azurerm_cognitive_account.openai.endpoint
                },
                {
                  name  = "azureOpenAI.deployment"
                  value = var.azure_openai_deployment_name
                },
                {
                  name  = "azureOpenAI.apiVersion"
                  value = var.azure_openai_api_version
                },
                {
                  name  = "acrLoginServer"
                  value = azurerm_container_registry.acr.login_server
                }
              ]
            }
          }
          destination = {
            server    = "https://kubernetes.default.svc"
            namespace = "default"
          }
          syncPolicy = {
            automated = {
              prune    = true
              selfHeal = true
            }
            syncOptions = ["CreateNamespace=true"]
          }
        }
      }
    })
  ]

  depends_on = [helm_release.argocd]
}
