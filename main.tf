terraform {
  required_providers {
    kaniko = {
      source  = "seal-io/kaniko"
      version = "0.0.3"
    }
  }
}

#######
# Build
#######

resource "kaniko_image" "image" {
  # Only handle git context. Explicitly use the git scheme.
  context     = "${local.formal_git_url}#refs/heads/${var.git_branch}"
  dockerfile  = var.dockerfile
  destination = var.image

  git_username      = var.git_auth ? var.git_username : ""
  git_password      = var.git_auth ? var.git_password : ""
  registry_username = var.registry_auth ? var.registry_username : ""
  registry_password = var.registry_auth ? var.registry_password : ""

  always_run = true
}

########
# Deploy 
########

module "deployment" {
  depends_on = [resource.kaniko_image.image]

  # disable wait for all pods be ready.
  #
  wait_for_rollout = false

  # Use local paths to avoid accessing external networks
  # This module comes from terraform registry "terraform-iaac/deployment/kubernetes 1.4.2"
  source = "./modules/deployment/kubernetes"

  name      = local.name
  namespace = local.namespace
  image     = var.image
  replicas  = var.replicas
  resources = {
    request_cpu    = var.request_cpu == "" ? null : var.request_cpu
    limit_cpu      = var.limit_cpu == "" ? null : var.limit_cpu
    request_memory = var.request_memory == "" ? null : var.request_memory
    limit_memory   = var.limit_memory == "" ? null : var.limit_memory
  }
  env = var.env
}

module "service" {
  depends_on = [resource.kaniko_image.image]

  # Use local paths to avoid accessing external networks
  # This module comes from terraform registry "terraform-iaac/service/kubernetes 1.0.4"
  source = "./modules/service/kubernetes"

  app_name      = local.name
  app_namespace = local.namespace
  type          = "NodePort"
  port_mapping = [for p in var.ports :
    {
      name          = "port-${p}"
      internal_port = p
      external_port = p
      protocol      = "TCP"
  }]
}

data "kubernetes_service" "service" {
  depends_on = [module.service]

  metadata {
    name      = local.name
    namespace = local.namespace
  }
}

########
# Common
########

locals {
  name           = coalesce(try(var.name, null), try(var.walrus_metadata_service_name, null), try(var.context["resource"]["name"], null))
  namespace      = coalesce(try(var.namespace, null), try(var.walrus_metadata_namespace_name, null), try(var.context["environment"]["namespace"], null))
  formal_git_url = replace(var.git_url, "https://", "git://")
}
