terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "3.45.0"
    }
  }
}

# Configure Provider
provider "azurerm" {
  # Configuration options
  subscription_id = var.subscription_id
  client_id = var.client_id
  client_secret = var.client_secret
  tenant_id = var.tenant_id
  features {}
}

# Declaring local variables to be used within main.tf 
locals {
  resource_group = "linux-app"
  location = "North Europe"
}

# Define cloud-init for linux vm
data "template_cloudinit_config" "linuxconfig" {
    gzip = true
    base64_encode = true

    part {
      content_type = "text/cloud-config"
      content = "package: ['nginx']"
    }
}

# Create a Resource Group
resource "azurerm_resource_group" "linux_app" {
    name = local.resource_group
    location = local.location
}

# Create an Azure Virtual Network
resource "azurerm_virtual_network" "linux_virtual_network" {
    name                = "linux-virtual-network"
    address_space       = ["10.0.0.0/16"]
    location            = local.location
    resource_group_name = local.resource_group
    depends_on = [
      azurerm_resource_group.linux_app
    ]
}

# Create a Network Subnet
resource "azurerm_subnet" "linux_subnet" {
    name                 = "linux-private-subnet"
    resource_group_name  = local.resource_group
    virtual_network_name = azurerm_virtual_network.linux_virtual_network.name
    address_prefixes     = ["10.0.1.0/24"]  
    depends_on = [
      azurerm_virtual_network.linux_virtual_network
    ]
}

# Creating a Public IP for SSH and HTTP connection
resource "azurerm_public_ip" "linux_public_ip" {
  name                = "linux-public-ip"
  resource_group_name = local.resource_group
  location            = local.location
  allocation_method   = "Dynamic"
}

# Create a Netwrok Interface: This is how you can assign an IP to the network
resource "azurerm_network_interface" "linux-net-interface" {
  name                = "linux-net-interface"
  location            = local.location
  resource_group_name =local.resource_group

  ip_configuration {
    name                          = "private-ip"
    subnet_id                     = azurerm_subnet.linux_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.linux_public_ip.id
  }
  depends_on = [
    azurerm_subnet.linux_subnet
  ]
}

#Creating a Network Security Group
resource "azurerm_network_security_group" "linux_network_sg" {
  name                = "linux-network-sg"
  location            = local.location
  resource_group_name = local.resource_group

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
  depends_on = [
    azurerm_resource_group.linux_app
  ]
}

# Creating NSG Association
resource "azurerm_subnet_network_security_group_association" "nsg_association" {
  subnet_id = azurerm_subnet.linux_subnet.id
  network_security_group_id = azurerm_network_security_group.linux_network_sg.id
  depends_on = [
    azurerm_network_security_group.linux_network_sg
  ]
}

# Creating a private key for Linux Instance
resource "tls_private_key" "linux_key" {
    algorithm = "RSA" 
    rsa_bits = 4096
}

# Saving the private key in our machine
resource "local_file" "linux_key_file" {
    filename = "linuxkey.pem"
    content = tls_private_key.linux_key.private_key_pem
}

# Create the Linux Instance
resource "azurerm_linux_virtual_machine" "linux-vm" {
    name                = "linux-vm"
    resource_group_name = local.resource_group
    location            = local.location
    size                = "Standard_F2"
    admin_username      = "linuxuser"
    custom_data = data.template_cloudinit_config.linuxconfig.rendered
    network_interface_ids = [
        azurerm_network_interface.linux-net-interface.id,
    ]

    admin_ssh_key {
        username   = "linuxuser"
        public_key = tls_private_key.linux_key.public_key_openssh
    }

    os_disk {
        caching              = "ReadWrite"
        storage_account_type = "Standard_LRS"
    }

    source_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "16.04-LTS"
        version   = "latest"
    }
    depends_on = [
      azurerm_network_interface.linux-net-interface,
      tls_private_key.linux_key
    ]
}