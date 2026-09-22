output "namespace" {
  description = "Namespace that holds the sandbox release."
  value       = kubernetes_namespace.sandbox.metadata[0].name
}

output "release_name" {
  description = "Helm release name."
  value       = helm_release.sandbox.name
}

output "image" {
  description = "Image that Terraform deployed."
  value       = "${var.image_repository}:${var.image_tag}"
}

output "ingress_host" {
  description = "Ingress hostname. Add it to /etc/hosts against the ingress IP."
  value       = var.ingress_host
}
