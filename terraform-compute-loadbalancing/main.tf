/*
 *  OCI: Execução de script de instalação do apache + load balancing - via Terraform
 *  
 *  
*/
variable "tenancy_ocid" {}
variable "user_ocid" {}
variable "fingerprint" {}
variable "compartment_ocid" {}
variable "region" {}
variable "private_key" {}
variable "private_key_openssh" {}
variable "ssh_public_key" {}
variable "images" {
  type = map(string)
  default = {
    # See https://docs.us-phoenix-1.oraclecloud.com/images/
    # Oracle-provided image "Oracle-Linux-7.5-2018.10.16-0"
    us-phoenix-1   = "ocid1.image.oc1.phx.aaaaaaaaoqj42sokaoh42l76wsyhn3k2beuntrh5maj3gmgmzeyr55zzrwwa"
    us-ashburn-1   = "ocid1.image.oc1.iad.aaaaaaaageeenzyuxgia726xur4ztaoxbxyjlxogdhreu3ngfj2gji3bayda"
    eu-frankfurt-1 = "ocid1.image.oc1.eu-frankfurt-1.aaaaaaaaitzn6tdyjer7jl34h2ujz74jwy5nkbukbh55ekp6oyzwrtfa4zma"
    uk-london-1    = "ocid1.image.oc1.uk-london-1.aaaaaaaa32voyikkkzfxyo4xbdmadc2dmvorfxxgdhpnk6dw64fa3l4jh7wa"
  }
}
variable "instance_shape" {
  default = "VM.Standard2.1"
}
variable "availability_domain" {
  default = 3
}
provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key      = var.private_key
  region           = var.region
}
data "oci_identity_availability_domain" "tcb_ad1" {
  compartment_id = var.tenancy_ocid
  ad_number      = 1
}
data "oci_identity_availability_domain" "tcb_ad2" {
  compartment_id = var.tenancy_ocid
  ad_number      = 2
}
/* Network */
resource "oci_core_vcn" "vcn1" {
  cidr_block     = "10.1.0.0/16"
  compartment_id = var.compartment_ocid
  display_name   = "vcn1"
  dns_label      = "vcn1"
}
resource "oci_core_subnet" "subnet1" {
  availability_domain = data.oci_identity_availability_domain.tcb_ad1.name
  cidr_block          = "10.1.20.0/24"
  display_name        = "subnet1"
  dns_label           = "subnet1"
  security_list_ids   = [oci_core_security_list.tcb_securitylist1.id]
  compartment_id      = var.compartment_ocid
  vcn_id              = oci_core_vcn.vcn1.id
  route_table_id      = oci_core_route_table.tcb_routetable1.id
  dhcp_options_id     = oci_core_vcn.vcn1.default_dhcp_options_id

  provisioner "local-exec" {
    command = "sleep 5"
  }
}
resource "oci_core_subnet" "subnet2" {
  availability_domain = data.oci_identity_availability_domain.tcb_ad2.name
  cidr_block          = "10.1.21.0/24"
  display_name        = "subnet2"
  dns_label           = "subnet2"
  security_list_ids   = [oci_core_security_list.tcb_securitylist1.id]
  compartment_id      = var.compartment_ocid
  vcn_id              = oci_core_vcn.vcn1.id
  route_table_id      = oci_core_route_table.tcb_routetable1.id
  dhcp_options_id     = oci_core_vcn.vcn1.default_dhcp_options_id
  provisioner "local-exec" {
    command = "sleep 5"
  }
}
resource "oci_core_internet_gateway" "tcb_internetgateway1" {
  compartment_id = var.compartment_ocid
  display_name   = "tcb_internetgateway1"
  vcn_id         = oci_core_vcn.vcn1.id
}

resource "oci_core_route_table" "tcb_routetable1" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.vcn1.id
  display_name   = "tcb_routetable1"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.tcb_internetgateway1.id
  }
}

resource "oci_core_public_ip" "test_reserved_ip" {
  compartment_id = "${var.compartment_ocid}"
  lifetime       = "RESERVED"
  lifecycle {
    ignore_changes = [private_ip_id]
  }
}
resource "oci_core_security_list" "tcb_securitylist1" {
  display_name   = "public"
  compartment_id = oci_core_vcn.vcn1.compartment_id
  vcn_id         = oci_core_vcn.vcn1.id
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 80
      max = 80
    }
  }
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 22
      max = 22
    }
  }
}
/* Instances */

resource "oci_core_instance" "websiteha1" {
  availability_domain = data.oci_identity_availability_domain.tcb_ad1.name
  compartment_id      = var.compartment_ocid
  display_name        = "websiteha1"
  shape               = var.instance_shape

  create_vnic_details {
    subnet_id        = oci_core_subnet.subnet1.id
    display_name     = "primaryvnic"
    assign_public_ip = true
    hostname_label   = "websiteha1"
  }

  source_details {
    source_type = "image"
    source_id   = var.images[var.region]
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }

  provisioner "file" {
    source      = "deploy_niture.sh"
    destination = "/tmp/deploy_niture.sh"
    connection {
      type = "ssh"
      host = "${self.public_ip}"
      user = "opc"
      private_key = var.private_key_openssh
    }

  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/deploy_niture.sh",
      "/tmp/deploy_niture.sh",
    ]
    connection {
      type = "ssh"
      host = "${self.public_ip}"
      user = "opc"
      private_key = var.private_key_openssh
    }
  }
}
resource "oci_core_instance" "websiteha2" {
  availability_domain = data.oci_identity_availability_domain.tcb_ad1.name
  compartment_id      = var.compartment_ocid
  display_name        = "websiteha2"
  shape               = var.instance_shape

  create_vnic_details {
    subnet_id        = oci_core_subnet.subnet1.id
    display_name     = "primaryvnic"
    assign_public_ip = true
    hostname_label   = "websiteha2"
  }

  source_details {
    source_type = "image"
    source_id   = var.images[var.region]
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }

  provisioner "file" {
    source      = "deploy_niture.sh"
    destination = "/tmp/deploy_niture.sh"
    connection {
      type = "ssh"
      host = "${self.public_ip}"
      user = "opc"
      private_key = var.private_key_openssh
    }

  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/deploy_niture.sh",
      "/tmp/deploy_niture.sh",
    ]
    connection {
      type = "ssh"
      host = "${self.public_ip}"
      user = "opc"
      private_key = var.private_key_openssh
    }
  }
}


/* Load Balancer */

resource "oci_load_balancer" "tcb_lb1" {
  shape          = "100Mbps"
  compartment_id = var.compartment_ocid

  subnet_ids = [
    oci_core_subnet.subnet1.id,
    oci_core_subnet.subnet2.id,
  ]

  display_name = "tcb_lb1"
  reserved_ips {
    id = "${oci_core_public_ip.test_reserved_ip.id}"
  }
}


resource "oci_load_balancer_backend_set" "tcb-lb-beset1" {
  name             = "tcb-lb-beset1"
  load_balancer_id = oci_load_balancer.tcb_lb1.id
  policy           = "ROUND_ROBIN"

  health_checker {
    port                = "80"
    protocol            = "HTTP"
    response_body_regex = ".*"
    url_path            = "/"
  }
}


resource "oci_load_balancer_listener" "tcb-lb-listener1" {
  load_balancer_id         = oci_load_balancer.tcb_lb1.id
  name                     = "http"
  default_backend_set_name = oci_load_balancer_backend_set.tcb-lb-beset1.name
  port                     = 80
  protocol                 = "HTTP"

  connection_configuration {
    idle_timeout_in_seconds = "2"
  }
}


resource "oci_load_balancer_backend" "tcb-lb-be1" {
  load_balancer_id = oci_load_balancer.tcb_lb1.id
  backendset_name  = oci_load_balancer_backend_set.tcb-lb-beset1.name
  ip_address       = oci_core_instance.websiteha1.private_ip
  port             = 80
  backup           = false
  drain            = false
  offline          = false
  weight           = 1
}

resource "oci_load_balancer_backend" "tcb-lb-be2" {
  load_balancer_id = oci_load_balancer.tcb_lb1.id
  backendset_name  = oci_load_balancer_backend_set.tcb-lb-beset1.name
  ip_address       = oci_core_instance.websiteha2.private_ip
  port             = 80
  backup           = false
  drain            = false
  offline          = false
  weight           = 1
}


output "lb_public_ip" {
  value = [oci_load_balancer.tcb_lb1.ip_address_details]
}
