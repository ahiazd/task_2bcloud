variable "resource_group_name" {
  type        = string
  description = "RG name in Azure"
}
variable "location" {
  type        = string
  description = "Resources location in Azure"
}

variable "virtual_network" {
  type        = string
  description = "Virtual network of our VPC"

}

variable "azurerm_subnet" {
  type        = string
  description = "private subnet"
}

variable "azurerm_key_vault" {
  type        = string
  description = "key vaultt"
}

variable "cluster_name" {
  type        = string
  description = "AKS name in Azure"
}
variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version"
}
variable "system_node_count" {
  type        = number
  description = "Number of AKS worker nodes"
}
variable "acr_name" {
  type        = string
  description = "registry cluster name"

}

