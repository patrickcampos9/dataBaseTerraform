terraform {
  required_version = ">= 0.13"


  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 2.26"
    }
  }
}

provider "azurerm" {
  skip_provider_registration = true
  features {}
}

resource "azurerm_resource_group" "terraformgroupvmdb" {
    name     = "ResourceGroupVmDb"
    location = "eastus"
}

resource "azurerm_virtual_network" "myterraformnetwork" {
    name                = "VnetVmDb"
    address_space       = ["10.0.0.0/16"]
    location            = azurerm_resource_group.terraformgroupvmdb.location
    resource_group_name = azurerm_resource_group.terraformgroupvmdb.name
}

resource "azurerm_subnet" "terraformsubnetvmbd" {
    name                 = "Subnetvmdb"
    resource_group_name  = azurerm_resource_group.terraformgroupvmdb.name
    virtual_network_name = azurerm_virtual_network.myterraformnetwork.name
    address_prefixes       = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "terraformpublicipvmdb" {
    name                         = "myPublicIpVmDb"
    location                     = azurerm_resource_group.terraformgroupvmdb.location
    resource_group_name          = azurerm_resource_group.terraformgroupvmdb.name
    allocation_method            = "Static"
}

data "azurerm_public_ip" "ip_aula_data_db" {
  name                = azurerm_public_ip.terraformpublicipvmdb.name
  resource_group_name = azurerm_resource_group.terraformgroupvmdb.name
}

resource "azurerm_network_security_group" "terraformnsgvmdb" {
    name                = "NetworkSecurityGroupVmDb"
    location            = azurerm_resource_group.terraformgroupvmdb.location
    resource_group_name = azurerm_resource_group.terraformgroupvmdb.name

    security_rule {
        name                       = "SSH"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "3306"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }
}

resource "azurerm_network_interface" "terraformnicvmdb" {
    name                      = "NicVmDb"
    location                  = azurerm_resource_group.terraformgroupvmdb.location
    resource_group_name       = azurerm_resource_group.terraformgroupvmdb.name

    ip_configuration {
        name                          = "NicConfigurationVmDb"
        subnet_id                     = azurerm_subnet.terraformsubnetvmbd.id
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id          = azurerm_public_ip.terraformpublicipvmdb.id
    }
}

resource "azurerm_network_interface_security_group_association" "example" {
    network_interface_id      = azurerm_network_interface.terraformnicvmdb.id
    network_security_group_id = azurerm_network_security_group.terraformnsgvmdb.id
}

resource "azurerm_storage_account" "storagevmdb42" {
    name                        = "storagevmdb1"
    resource_group_name         = azurerm_resource_group.terraformgroupvmdb.name
    location                    = azurerm_resource_group.terraformgroupvmdb.location
    account_tier                = "Standard"
    account_replication_type    = "LRS"
    depends_on = [ azurerm_resource_group.terraformgroupvmdb ]
}
    

resource "azurerm_linux_virtual_machine" "terraformvmdb" {
    name                  = "VmDb"
    location              = azurerm_resource_group.terraformgroupvmdb.location
    resource_group_name   = azurerm_resource_group.terraformgroupvmdb.name
    network_interface_ids = [azurerm_network_interface.terraformnicvmdb.id]
    size                  = "Standard_D2s_v3"

    os_disk {
        name              = "myOsDisk"
        caching           = "ReadWrite"
        storage_account_type = "Premium_LRS"
    }

    source_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "18.04-LTS"
        version   = "latest"
    }

    computer_name  = "hostname"
    admin_username = "testeadmin"
    admin_password = "Password1234!"
    disable_password_authentication = false

     boot_diagnostics {
        storage_account_uri = azurerm_storage_account.storagevmdb42.primary_blob_endpoint
    }

    depends_on = [ azurerm_resource_group.terraformgroupvmdb, azurerm_network_interface.terraformnicvmdb, azurerm_storage_account.storagevmdb42, azurerm_public_ip.terraformpublicipvmdb ]

}

resource "time_sleep" "wait_30_seconds_db" {
  depends_on = [azurerm_linux_virtual_machine.terraformvmdb]
  create_duration = "30s"
}

resource "null_resource" "upload_db" {
    provisioner "file" {
        connection {
            type = "ssh"
            user = "testeadmin"
            password = "Password1234!"
            host = data.azurerm_public_ip.ip_aula_data_db.ip_address
        }
        source = "mysql"
        destination = "/home/testeadmin"
    }

    depends_on = [ time_sleep.wait_30_seconds_db ]
}

resource "null_resource" "deploy_db" {
    triggers = {
        order = null_resource.upload_db.id
    }
    provisioner "remote-exec" {
        connection {
            type = "ssh"
            user = "testeadmin"
            password = "Password1234!"
            host = data.azurerm_public_ip.ip_aula_data_db.ip_address
        }
        inline = [
            "sudo apt-get update",
            "sudo apt-get install -y mysql-server-5.7",
            "sudo cp -f /home/testeadmin/mysql/mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf",
            "sudo service mysql restart",
            "sleep 20",
        ]
    }
}


output "public_ip_address" {
  value = azurerm_public_ip.terraformpublicipvmdb.ip_address
}