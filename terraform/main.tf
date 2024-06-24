terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}



resource "azurerm_resource_group" "taskdev-rg" {
  name     = var.resource_group_name
  location = var.location
  tags = {
    environment = "dev"
  }
}

resource "azurerm_virtual_network" "taskdev-vn" {
  name                = var.virtual_network
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = ["10.123.0.0/16"]
  tags = {
    environment = "dev"
  }
}

resource "azurerm_subnet" "taskdev-subnet" {
  name                 = var.azurerm_subnet
  resource_group_name  = azurerm_resource_group.taskdev-rg.name
  virtual_network_name = azurerm_virtual_network.taskdev-vn.name
  address_prefixes     = ["10.123.1.0/24"]
}

resource "azurerm_network_security_group" "taskdev-sg" {
  name                = "taskdev-sg"
  location            = azurerm_resource_group.taskdev-rg.location
  resource_group_name = azurerm_resource_group.taskdev-rg.name
  tags = {
    environment = "dev"
  }
}

resource "azurerm_network_security_rule" "taskdev-sec-rule" {
  name                        = "taskdev-dev-rule"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "0.0.0.0/0"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.taskdev-rg.name
  network_security_group_name = azurerm_network_security_group.taskdev-sg.name
}

resource "azurerm_subnet_network_security_group_association" "taskdev-subnet-net-sga" {
  subnet_id                 = azurerm_subnet.taskdev-subnet.id
  network_security_group_id = azurerm_network_security_group.taskdev-sg.id
}

resource "azurerm_public_ip" "taskdev-ip" {
  name                = "taskdev-public-ip"
  resource_group_name = azurerm_resource_group.taskdev-rg.name
  location            = azurerm_resource_group.taskdev-rg.location
  allocation_method   = "Dynamic"
  tags = {
    environment = "dev"
  }
}

resource "azurerm_network_interface" "taskdev-net-int" {
  name                = "taskdev-network-int"
  location            = azurerm_resource_group.taskdev-rg.location
  resource_group_name = azurerm_resource_group.taskdev-rg.name
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.taskdev-subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.taskdev-ip.id
  }
  tags = {
    environment = "dev"
  }
}

# Add your SSH public key here
resource "azurerm_linux_virtual_machine" "taskdev-vm" {
  name                = "taskdev-vm"
  resource_group_name = azurerm_resource_group.taskdev-rg.name
  location            = azurerm_resource_group.taskdev-rg.location
  size                = "Standard_DS1_v2"
  admin_username      = "adminuser"

  network_interface_ids = [
    azurerm_network_interface.taskdev-net-int.id,
  ]

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("azure_key.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  tags = {
    environment = "dev"
  }

}

data "azurerm_public_ip" "taskdev-ip" {
  name                = azurerm_public_ip.taskdev-ip.name
  resource_group_name = azurerm_resource_group.taskdev-rg.name
}

resource "null_resource" "wait_for_ip" {
  depends_on = [azurerm_linux_virtual_machine.taskdev-vm]

  provisioner "local-exec" {
    command = "echo ${data.azurerm_public_ip.taskdev-ip.ip_address}"
  }
//Jenkins installation with docker and git
  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y docker.io git",
      "sudo systemctl start docker",
      "sudo systemctl enable docker",
      "sudo usermod -aG docker adminuser",
      "sudo apt-get install -y openjdk-11-jdk wget",
      "wget http://ftp.us.debian.org/debian/pool/main/i/init-system-helpers/init-system-helpers_1.60_all.deb",
      "sudo dpkg -i init-system-helpers_1.60_all.deb || sudo apt-get -f install -y",
      "curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null",
      "echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/ | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null",
      "sudo apt-get update",
      "sudo apt-get install -y jenkins",
      "sudo systemctl start jenkins",
      "sudo systemctl enable jenkins"
    ]
//kry pair i crated to connect to VM
    connection {
      type        = "ssh"
      user        = "adminuser"
      private_key = file("azure_key")
      host        = data.azurerm_public_ip.taskdev-ip.ip_address
    }
  }
}



data "azurerm_client_config" "current" {}
resource "azurerm_key_vault" "taskdev_key_vault" {
  name                       = var.azurerm_key_vault
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Create",
      "Get",
    ]

    secret_permissions = [
      "Set",
      "Get",
      "Delete",
      "Purge",
      "Recover"
    ]
  }
}

resource "azurerm_role_assignment" "role_acrpull" {
  scope                            = azurerm_container_registry.acr.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.aks.kubelet_identity.0.object_id
  skip_service_principal_aad_check = true
}

resource "azurerm_container_registry" "acr" {
  name                = var.acr_name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Standard"
  admin_enabled       = false
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name
  kubernetes_version  = var.kubernetes_version
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.cluster_name

  default_node_pool {
    name                = "system"
    node_count          = var.system_node_count
    vm_size             = "Standard_DS2_v2"
    type                = "VirtualMachineScaleSets"
    zones               = [1, 2, 3]
    enable_auto_scaling = false
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    load_balancer_sku = "standard"
    network_plugin    = "kubenet"
  }
}

resource "local_file" "kubeconfig" {
  depends_on = [azurerm_kubernetes_cluster.aks]
  filename   = "kubeconfig"
  content    = azurerm_kubernetes_cluster.aks.kube_config_raw
}
