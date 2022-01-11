terraform {
  required_providers {
    alicloud = {
      source  = "aliyun/alicloud"
      version = "=1.151.0"
    }
  }
}

provider "alicloud" {
  region = var.region
}

data "alicloud_zones" "az" {
  network_type = "Vpc"
}

resource "alicloud_vpc" "hashicat" {
  cidr_block = var.address_space
  vpc_name   = "${var.prefix}-vpc"
}

resource "alicloud_vswitch" "hashicat" {
  vswitch_name = "${var.prefix}--vswitch"
  zone_id      = data.alicloud_zones.az.zones.0.id
  cidr_block   = var.subnet_prefix
  vpc_id       = alicloud_vpc.hashicat.id
}

resource "alicloud_security_group" "hashicat" {
  name   = "${var.prefix}-security-group"
  vpc_id = alicloud_vpc.hashicat.id
}

resource "alicloud_security_group_rule" "allow_ssh" {
  type              = "ingress"
  port_range        = "22/22"
  ip_protocol       = "tcp"
  cidr_ip           = "0.0.0.0/0"
  security_group_id = alicloud_security_group.hashicat.id
}

resource "alicloud_security_group_rule" "allow_http" {
  type              = "ingress"
  port_range        = "80/80"
  ip_protocol       = "tcp"
  cidr_ip           = "0.0.0.0/0"
  security_group_id = alicloud_security_group.hashicat.id
}

resource "alicloud_security_group_rule" "allow_https" {
  type              = "ingress"
  port_range        = "443/443"
  ip_protocol       = "tcp"
  cidr_ip           = "0.0.0.0/0"
  security_group_id = alicloud_security_group.hashicat.id
}

resource "alicloud_security_group_rule" "allow_all_outbound" {
  type              = "egress"
  port_range        = "-1/-1"
  ip_protocol       = "all"
  cidr_ip           = "0.0.0.0/0"
  security_group_id = alicloud_security_group.hashicat.id
}

data "alicloud_images" "ubuntu" {
  name_regex  = "^ubuntu_20.*x64"
  owners      = "system"
  most_recent = true
}

resource "alicloud_eip_address" "hashicat" {
  bandwidth            = 1
  address_name         = "tf-testAcc1234"
  isp                  = "BGP"
  internet_charge_type = "PayByBandwidth"
  payment_type         = "PayAsYouGo"
}

resource "alicloud_eip_association" "hashicat" {
  instance_id   = alicloud_instance.hashicat.id
  allocation_id = alicloud_eip_address.hashicat.id
}

# data "template_file" "user_data" {
#   template = file("files/deploy_app.sh")
# }

resource "alicloud_instance" "hashicat" {
  instance_name   = "${var.prefix}-hashicat"
  image_id        = data.alicloud_images.ubuntu.images.0.image_id
  instance_type   = var.instance_type
  vswitch_id      = alicloud_vswitch.hashicat.id
  security_groups = [alicloud_security_group.hashicat.id]

  key_name = alicloud_ecs_key_pair.hashicat.key_name

  # This could be used instead of the provisioner
  # user_data = "${data.template_file.user_data.template}"

  tags = {
    Department = "devops"
    Billable   = "true"
  }
}

# We're using a little trick here so we can run the provisioner without
# destroying the VM. Do not do this in production.

# If you need ongoing management (Day N) of your virtual machines a tool such
# as Chef or Puppet is a better choice. These tools track the state of
# individual files and can keep them in the correct configuration.

# Here we do the following steps:
# Sync everything in files/ to the remote VM.
# Set up some environment variables for our script.
# Add execute permissions to our scripts.
# Run the deploy_app.sh script.
resource "null_resource" "configure-cat-app" {
  depends_on = [alicloud_eip_association.hashicat]

  triggers = {
    build_number = timestamp()
  }

  provisioner "file" {
    source      = "files/"
    destination = "/root/"

    connection {
      type        = "ssh"
      user        = "root"
      private_key = tls_private_key.hashicat.private_key_pem
      host        = alicloud_eip_address.hashicat.ip_address
    }
  }

  provisioner "remote-exec" {
    inline = [
      "apt-get -qq -y update",
      "apt-get -qq -y install apache2",
      "systemctl start apache2",
      "chmod +x *.sh",
      "PLACEHOLDER=${var.placeholder} WIDTH=${var.width} HEIGHT=${var.height} PREFIX=${var.prefix} ./deploy_app.sh",
      "apt-get -qq -y install cowsay",
      "cowsay Mooooooooooo!",
    ]

    connection {
      type        = "ssh"
      user        = "root"
      private_key = tls_private_key.hashicat.private_key_pem
      host        = alicloud_eip_address.hashicat.ip_address
    }
  }
}

resource "tls_private_key" "hashicat" {
  algorithm = "RSA"
}

locals {
  private_key_filename = "${var.prefix}-ssh-key.pem"
}

resource "alicloud_ecs_key_pair" "hashicat" {
  key_pair_name = "hashicat-key"
  public_key    = tls_private_key.hashicat.public_key_openssh
}
