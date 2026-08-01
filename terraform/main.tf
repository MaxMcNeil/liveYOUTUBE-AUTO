terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0.0"
    }
  }
}

# Utilise automatiquement ~/.oci/config (profil DEFAULT) — aucune clé
# en dur dans ce fichier. Créez ce fichier localement avec le contenu
# du "Configuration file preview" de la console OCI, en gardant la clé
# privée hors de ce dépôt (voir README.md).
provider "oci" {
  region = var.region
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_ocid
}

data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order                = "DESC"
}

resource "oci_core_vcn" "livestream_vcn" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = ["10.0.0.0/16"]
  display_name   = "livestream-vcn"
}

resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.livestream_vcn.id
  display_name   = "livestream-igw"
  enabled        = true
}

resource "oci_core_route_table" "rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.livestream_vcn.id
  display_name   = "livestream-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}

resource "oci_core_security_list" "sl" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.livestream_vcn.id
  display_name   = "livestream-sl"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  # SSH restreint à votre IP uniquement (voir var.ssh_allowed_cidr)
  ingress_security_rules {
    source   = var.ssh_allowed_cidr
    protocol = "6" # TCP
    tcp_options {
      min = 22
      max = 22
    }
  }
}

resource "oci_core_subnet" "subnet" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.livestream_vcn.id
  cidr_block                 = "10.0.1.0/24"
  display_name               = "livestream-subnet"
  route_table_id             = oci_core_route_table.rt.id
  security_list_ids          = [oci_core_security_list.sl.id]
  prohibit_public_ip_on_vnic = false
}

resource "oci_core_instance" "livestream_vm" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = "livestream-vps"
  shape                = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory_gb
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.subnet.id
    assign_public_ip = true
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ubuntu.images[0].id
  }

  metadata = {
    ssh_authorized_keys = file(var.ssh_public_key_path)
  }

  connection {
    type        = "ssh"
    host        = self.public_ip
    user        = "ubuntu"
    private_key = file(var.ssh_private_key_path)
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = ["mkdir -p /home/ubuntu/livestream"]
  }

  provisioner "file" {
    source      = "${path.module}/../orchestrator.js"
    destination = "/home/ubuntu/livestream/orchestrator.js"
  }
  provisioner "file" {
    source      = "${path.module}/../config.json"
    destination = "/home/ubuntu/livestream/config.json"
  }
  provisioner "file" {
    source      = "${path.module}/../package.json"
    destination = "/home/ubuntu/livestream/package.json"
  }
  provisioner "file" {
    source      = "${path.module}/../start_stream.sh"
    destination = "/home/ubuntu/livestream/start_stream.sh"
  }
  provisioner "file" {
    source      = "${path.module}/../deploy.sh"
    destination = "/home/ubuntu/livestream/deploy.sh"
  }
  provisioner "file" {
    source      = "${path.module}/../youtube_description.txt"
    destination = "/home/ubuntu/livestream/youtube_description.txt"
  }
  provisioner "file" {
    source      = "${path.module}/../create_daily_broadcast.js"
    destination = "/home/ubuntu/livestream/create_daily_broadcast.js"
  }
  provisioner "file" {
    source      = "${path.module}/../livestream.service"
    destination = "/home/ubuntu/livestream/livestream.service"
  }
  provisioner "file" {
    source      = "${path.module}/../livestream-start.service"
    destination = "/home/ubuntu/livestream/livestream-start.service"
  }
  provisioner "file" {
    source      = "${path.module}/../livestream-start.timer"
    destination = "/home/ubuntu/livestream/livestream-start.timer"
  }
  provisioner "file" {
    source      = "${path.module}/../livestream-stop.service"
    destination = "/home/ubuntu/livestream/livestream-stop.service"
  }
  provisioner "file" {
    source      = "${path.module}/../livestream-stop.timer"
    destination = "/home/ubuntu/livestream/livestream-stop.timer"
  }
  provisioner "file" {
    source      = "${path.module}/../youtube-metadata.service"
    destination = "/home/ubuntu/livestream/youtube-metadata.service"
  }
  provisioner "file" {
    source      = "${path.module}/../youtube-metadata.timer"
    destination = "/home/ubuntu/livestream/youtube-metadata.timer"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /opt/livestream",
      "if [ -n \"${var.google_refresh_token}\" ]; then sudo bash -c 'cat > /opt/livestream/.env <<EOF\nYOUTUBE_STREAM_KEY=${var.youtube_stream_key}\nGOOGLE_CLIENT_ID=${var.google_client_id}\nGOOGLE_CLIENT_SECRET=${var.google_client_secret}\nGOOGLE_REFRESH_TOKEN=${var.google_refresh_token}\nYOUTUBE_STREAM_ID=${var.youtube_stream_id}\nEOF'; sudo chmod 600 /opt/livestream/.env; fi",
      "chmod +x /home/ubuntu/livestream/deploy.sh",
      "cd /home/ubuntu/livestream && sudo -E env YOUTUBE_STREAM_KEY='${var.youtube_stream_key}' bash deploy.sh",
    ]
  }
}
