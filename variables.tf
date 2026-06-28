variable "resource_prefix" {
  description = "A prefix for all resources created in this example"
  type        = string
  default     = "aks-learn"
}

variable "azure_region" {
  description = "The Azure Region in which all resources should be created"
  type        = string
  default     = "eastus"
}

variable "system_node_count" {
  description = "The initial number of nodes for the default system node pool"
  type        = number
  default     = 2
}

variable "system_node_vm_size" {
  description = "The VM size for the AKS node pool nodes"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "azure_openai_deployment_name" {
  description = "The Azure OpenAI deployment name the application calls"
  type        = string
  default     = "gpt-4o-mini"
}

variable "azure_openai_model_name" {
  description = "The Azure OpenAI model name to deploy"
  type        = string
  default     = "gpt-4o-mini"
}

variable "azure_openai_model_version" {
  description = "The Azure OpenAI model version to deploy. Availability depends on region and subscription quota."
  type        = string
  default     = "2024-07-18"
}

variable "azure_openai_api_version" {
  description = "The Azure OpenAI data-plane API version used by the application"
  type        = string
  default     = "2024-10-21"
}
