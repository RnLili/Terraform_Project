terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.1.0"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "2.3.7"
    }
    terracurl = {
      source  = "devops-rob/terracurl"
      version = "2.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.7.2"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}
data "azurerm_platform_image" "p-pi" {
  location  = azurerm_resource_group.p-rg.location
  publisher = "Debian"
  offer     = "debian-11"
  sku       = "11"
}
resource "random_password" "password" {
  length  = 12
  special = false
}
data "cloudinit_config" "config" {
  gzip          = true
  base64_encode = true

  part {
    filename     = "init.sh"
    content_type = "text/x-shellscript"

    content = templatefile("${path.module}/provision_basic.sh",
      {
        openai_user     = var.user,
        openai_password = random_password.password.result,
        openai_base     = var.base,
        openai_key      = var.key
    })
  }

  part {
    content_type = "text/cloud-config"

    content = file("${path.module}/init.yaml")
  }
}
resource "azurerm_resource_group" "p-rg" {
  name     = "p_resources"
  location = var.location
}

resource "azurerm_virtual_network" "p-vn" {
  name                = "p-network"
  resource_group_name = azurerm_resource_group.p-rg.name
  location            = azurerm_resource_group.p-rg.location
  address_space       = ["10.0.0.0/24"]

}

resource "azurerm_subnet" "p-subnet" {
  name                 = "p-subnet"
  resource_group_name  = azurerm_resource_group.p-rg.name
  virtual_network_name = azurerm_virtual_network.p-vn.name
  address_prefixes     = [cidrsubnet(one(azurerm_virtual_network.p-vn.address_space), 4, 0)]
}
resource "azurerm_network_interface" "server-nic" {
  name                = "server-nic"
  location            = azurerm_resource_group.p-rg.location
  resource_group_name = azurerm_resource_group.p-rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.p-subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.server-pub-ip.id
  }
}
resource "azurerm_network_security_group" "p-sg" {
  name                = "p-sg"
  location            = azurerm_resource_group.p-rg.location
  resource_group_name = azurerm_resource_group.p-rg.name

}

resource "azurerm_network_security_rule" "p-rule-tcp-in" {
  for_each                    = var.protocols
  name                        = "p-rule-tcp-in-${each.key}"
  priority                    = each.key == "http" ? 102 : 103
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = tostring(each.value)
  source_address_prefix       = "*"
  destination_address_prefix  = azurerm_network_interface.server-nic.private_ip_address
  resource_group_name         = azurerm_resource_group.p-rg.name
  network_security_group_name = azurerm_network_security_group.p-sg.name
}

resource "azurerm_network_security_rule" "p-rule-ssh-in" {
  name                        = "p-rule-ssh-in"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = 22
  source_address_prefix       = "*"
  destination_address_prefix  = azurerm_network_interface.client-nic.private_ip_address
  resource_group_name         = azurerm_resource_group.p-rg.name
  network_security_group_name = azurerm_network_security_group.p-sg.name
}

resource "azurerm_network_security_rule" "p-rule-tcp-out" {
  for_each                    = var.protocols
  name                        = "p-rule-tcp-out-${each.key}"
  priority                    = each.key == "http" ? 101 : 102
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = tostring(each.value)
  source_address_prefix       = azurerm_network_interface.server-nic.private_ip_address
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.p-rg.name
  network_security_group_name = azurerm_network_security_group.p-sg.name
}
resource "azurerm_network_security_rule" "p-rule-dns-out" {
  name                        = "p-rule-dns-out"
  priority                    = 100
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Udp"
  source_port_range           = 53
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.p-rg.name
  network_security_group_name = azurerm_network_security_group.p-sg.name
}

resource "azurerm_subnet_network_security_group_association" "p-sn-assoc" {
  subnet_id                 = azurerm_subnet.p-subnet.id
  network_security_group_id = azurerm_network_security_group.p-sg.id
}

resource "azurerm_public_ip" "server-pub-ip" {
  name                = "server-pub-ip"
  resource_group_name = azurerm_resource_group.p-rg.name
  location            = azurerm_resource_group.p-rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_linux_virtual_machine" "server-vm" {
  name                = "server-vm"
  resource_group_name = azurerm_resource_group.p-rg.name
  location            = azurerm_resource_group.p-rg.location
  size                = "Standard_F2"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.server-nic.id,
  ]

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("${path.module}/.ssh/azurekey.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = data.azurerm_platform_image.p-pi.publisher
    offer     = data.azurerm_platform_image.p-pi.offer
    sku       = data.azurerm_platform_image.p-pi.sku
    version   = data.azurerm_platform_image.p-pi.version
  }
  custom_data = data.cloudinit_config.config.rendered
}

resource "terracurl_request" "p-tr" {
  name   = "p-tr"
  url    = "http://${resource.azurerm_public_ip.server-pub-ip.ip_address}"
  method = "GET"

  response_codes = [200]
  max_retry      = 120
  retry_interval = 10
}


resource "azurerm_network_interface" "client-nic" {
  name                = "client-nic"
  location            = azurerm_resource_group.p-rg.location
  resource_group_name = azurerm_resource_group.p-rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.p-subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.client-pub-ip.id
  }
}

resource "azurerm_public_ip" "client-pub-ip" {
  name                = "client-pub-ip"
  resource_group_name = azurerm_resource_group.p-rg.name
  location            = azurerm_resource_group.p-rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_linux_virtual_machine" "client-vm" {
  name                = "client-vm"
  resource_group_name = azurerm_resource_group.p-rg.name
  location            = azurerm_resource_group.p-rg.location
  size                = "Standard_F2"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.client-nic.id,
  ]

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("${path.module}/.ssh/azurekey.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = data.azurerm_platform_image.p-pi.publisher
    offer     = data.azurerm_platform_image.p-pi.offer
    sku       = data.azurerm_platform_image.p-pi.sku
    version   = data.azurerm_platform_image.p-pi.version
  }
}

