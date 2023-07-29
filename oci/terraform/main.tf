terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 4.0.0"
    }
  }
}

provider "oci" {
  region = var.region
}

resource "oci_core_vcn" "this" {
  display_name   = "Gourami"
  compartment_id = var.compartment_id
  cidr_blocks    = ["10.15.0.0/16"]
  dns_label      = "gourami"

  defined_tags  = var.defined_tags
  freeform_tags = var.freeform_tags

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_core_internet_gateway" "this" {
  display_name   = "Gourami Internet Gateway"
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.this.id
  enabled        = true

  defined_tags  = var.defined_tags
  freeform_tags = var.freeform_tags

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_core_default_route_table" "this" {
  display_name               = "Gourami Default Routing Table"
  manage_default_resource_id = oci_core_vcn.this.default_route_table_id

  route_rules {
    description       = "Allow communication between the VCN and the internet (without this traffic from within the VCN will not find its way to the internet)"
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.this.id
  }

  defined_tags  = var.defined_tags
  freeform_tags = var.freeform_tags

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_core_default_security_list" "this" {
  display_name               = "Gourami Default Security List"
  manage_default_resource_id = oci_core_vcn.this.default_security_list_id

  egress_security_rules {
    description = "Allow all egress traffic (without this traffic from within the VCN will not be allowed to the internet)"
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  ingress_security_rules {
    description = "Allow HTTP from the anywhere (without this cannot HTTP to the website)"
    protocol    = "6"
    source      = "0.0.0.0/0"

    tcp_options {
      min = 80
      max = 80
    }
  }

  ingress_security_rules {
    description = "Allow HTTP from the anywhere (without this cannot HTTP to the website)"
    protocol    = "6"
    source      = "0.0.0.0/0"

    tcp_options {
      min = 8080
      max = 8080
    }
  }

  ingress_security_rules {
    description = "Allow HTTPS from the anywhere (without this cannot HTTPS to the website)"
    protocol    = "6"
    source      = "0.0.0.0/0"

    tcp_options {
      min = 443
      max = 443
    }
  }

  defined_tags  = var.defined_tags
  freeform_tags = var.freeform_tags

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

resource "oci_core_subnet" "public" {
  display_name               = "Gourami Public Subnet"
  compartment_id             = var.compartment_id
  vcn_id                     = oci_core_vcn.this.id
  cidr_block                 = "10.15.1.0/24"
  prohibit_internet_ingress  = false
  prohibit_public_ip_on_vnic = false
  dns_label                  = "public"

  defined_tags  = var.defined_tags
  freeform_tags = var.freeform_tags

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

data "oci_objectstorage_namespace" "this" {
  compartment_id = var.compartment_id
}

resource "oci_objectstorage_bucket" "website" {
  name           = "gourami"
  compartment_id = var.compartment_id
  namespace      = data.oci_objectstorage_namespace.this.namespace
  access_type    = "ObjectReadWithoutList"

  defined_tags  = var.defined_tags
  freeform_tags = var.freeform_tags

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

data "oci_identity_availability_domains" "available" {
  compartment_id = var.tenancy_id
}

resource "oci_container_instances_container_instance" "app" {
  display_name        = "Gourami Web Application Container Instance"
  compartment_id      = var.compartment_id
  availability_domain = lookup(data.oci_identity_availability_domains.available.availability_domains[0], "name")

  shape = "CI.Standard.E3.Flex"
  shape_config {
    memory_in_gbs = "16"
    ocpus         = "1"
  }

  containers {
    display_name = "Gourami Web Application Container"
    image_url    = "albertattard/gourami-app:latest"

    health_checks {
      name                     = "Demo HTTP Health Check"
      health_check_type        = "HTTP"
      initial_delay_in_seconds = 5
      interval_in_seconds      = 5
      path                     = "/actuator/health"
      port                     = 8080
      timeout_in_seconds       = 2
    }

    defined_tags  = var.defined_tags
    freeform_tags = var.freeform_tags
  }

  vnics {
    display_name          = "Gourami App"
    subnet_id             = oci_core_subnet.public.id
    is_public_ip_assigned = true
    hostname_label        = "gouramiapp"

    defined_tags  = var.defined_tags
    freeform_tags = var.freeform_tags
  }

  defined_tags  = var.defined_tags
  freeform_tags = var.freeform_tags

  lifecycle {
    ignore_changes = [defined_tags, containers[0].defined_tags, vnics[0].defined_tags]
  }
}

resource "oci_apigateway_gateway" "this" {
  display_name   = "Gourami API Gateway"
  compartment_id = var.compartment_id
  endpoint_type  = "PUBLIC"
  subnet_id      = oci_core_subnet.public.id

  defined_tags  = var.defined_tags
  freeform_tags = var.freeform_tags

  lifecycle {
    ignore_changes = [defined_tags]
  }
}

locals {
  bucket_url = "https://${oci_objectstorage_bucket.website.namespace}.objectstorage.${var.region}.oci.customer-oci.com/n/${oci_objectstorage_bucket.website.namespace}/b/${oci_objectstorage_bucket.website.name}"
}

resource "oci_apigateway_deployment" "website" {
  display_name   = "Gourami Web Application Deployment"
  compartment_id = var.compartment_id
  gateway_id     = oci_apigateway_gateway.this.id
  path_prefix    = "/"

  specification {

    logging_policies {
      access_log {
        is_enabled = true
      }
    }

    routes {
      backend {
        type                       = "HTTP_BACKEND"
        url                        = "http://gouramiapp.public.gourami.oraclevcn.com:8080/$${request.path[path]}"
        connect_timeout_in_seconds = 2
      }
      path    = "/api/{path*}"
      methods = ["GET", "POST", "PUT", "HEAD"]
    }

    routes {
      backend {
        type                       = "HTTP_BACKEND"
        url                        = "${local.bucket_url}/o/static/$${request.path[object]}"
        connect_timeout_in_seconds = 2
      }
      path    = "/static/{object*}"
      methods = ["GET", "HEAD"]
    }

    routes {
      backend {
        type                       = "HTTP_BACKEND"
        url                        = "${local.bucket_url}/o/favicon.ico"
        connect_timeout_in_seconds = 2
      }
      path    = "/favicon.ico"
      methods = ["GET", "HEAD"]
    }

    routes {
      backend {
        type                       = "HTTP_BACKEND"
        url                        = "${local.bucket_url}/o/index.html"
        connect_timeout_in_seconds = 2
      }
      path    = "/{object*}"
      methods = ["GET", "HEAD"]
    }
  }

  defined_tags  = var.defined_tags
  freeform_tags = var.freeform_tags

  lifecycle {
    ignore_changes = [defined_tags]
  }
}
