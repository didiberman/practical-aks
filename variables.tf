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
