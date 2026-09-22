resource "kubernetes_namespace" "sandbox" {
  metadata {
    name = var.namespace
    labels = {
      app         = "confapi"
      environment = var.environment
    }
  }
}

resource "helm_release" "sandbox" {
  name      = var.release_name
  chart     = "${path.module}/../helm"
  namespace = kubernetes_namespace.sandbox.metadata[0].name
  timeout   = 180
  wait      = true
  atomic    = true

  set {
    name  = "image.repository"
    value = var.image_repository
  }

  set {
    name  = "image.tag"
    value = var.image_tag
  }

  set {
    name  = "image.pullPolicy"
    value = var.image_pull_policy
  }

  set {
    name  = "environment"
    value = var.environment
  }

  set {
    name  = "replicaCount"
    value = tostring(var.replica_count)
    type  = "auto"
  }

  set {
    name  = "ingress.enabled"
    value = tostring(var.ingress_enabled)
    type  = "auto"
  }

  set {
    name  = "ingress.host"
    value = var.ingress_host
  }

  set {
    name  = "fullnameOverride"
    value = "confapi"
  }
}
