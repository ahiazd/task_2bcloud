terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0.0" 
    }
  }
}

provider "azurerm" {
  features {}

}

# region to work on
resource "azurerm_resource_group" "taskdev-rg" {
  name     = "taskdev-resource"
  location = "France Central"
  tags = {
    environment = "dev"
  }
}

resource "azurerm_virtual_network" "taskdev-vn" {
  name                = "taskdev-virtual-network"
  resource_group_name = azurerm_resource_group.taskdev-rg.name
  location            = azurerm_resource_group.taskdev-rg.location
  address_space       = ["10.123.0.0/16"]
  tags = {
    enviornment = "dev"
  }

}

resource "azurerm_subnet" "taskdev-subnet" {
  name                 = "taskdev-subnet"
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
    enviornment = "dev"
  }
}

# Add your SSH public key here
resource "azurerm_linux_virtual_machine" "taskdev_vm" {
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

    connection {
      type        = "ssh"
      user        = "adminuser"
      private_key = file("azure_key")
      host        = azurerm_public_ip.taskdev-ip.ip_address
    }
  }
}

# Create an Azure Container Registry (ACR)
resource "azurerm_container_registry" "acr" {
  name                = "taskdevacr"
  resource_group_name = azurerm_resource_group.taskdev-rg.name
  location            = azurerm_resource_group.taskdev-rg.location
  sku                 = "Standard"
  admin_enabled       = true
}


# Create an AKS cluster
resource "azurerm_kubernetes_cluster" "taskdev-k8s-cluster" {
  name                = "taskdev-k8s-cls"
  location            = azurerm_resource_group.taskdev-rg.location
  resource_group_name = azurerm_resource_group.taskdev-rg.name
  dns_prefix          = "deveks"

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_D2_v2"
  }

  identity {
    type = "SystemAssigned"
  }
  
 tags = {
    Environment = "dev"
  }
 
}



