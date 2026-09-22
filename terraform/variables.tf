variable "kubeconfig_path" {
  type        = string
  description = "Path to a kubeconfig that can reach the local cluster (Kind, Minikube, or k3d)."
  default     = "~/.kube/config"
}

variable "kube_context" {
  type        = string
  description = "Kubeconfig context. Required so Terraform cannot apply to an unexpected cluster."

  validation {
    condition     = length(trimspace(var.kube_context)) > 0 && var.kube_context != "default"
    error_message = "Set kube_context to a local cluster such as \"sandbox\" (Minikube) or a Kind context. Do not leave it empty."
  }
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace for the sandbox release."
  default     = "sandbox"
}

variable "environment" {
  type        = string
  description = "Value injected as the ENVIRONMENT variable in the application."
  default     = "dev"
}

variable "image_repository" {
  type        = string
  description = "Container image repository (local tag or registry path)."
  default     = "confapi"
}

variable "image_tag" {
  type        = string
  description = "Immutable image tag. Prefer a git SHA in CI instead of latest."
  default     = "1.0.0"
}

variable "image_pull_policy" {
  type        = string
  description = "Image pull policy. Use IfNotPresent for images loaded into Minikube or Kind."
  default     = "IfNotPresent"
}

variable "release_name" {
  type        = string
  description = "Helm release name."
  default     = "sandbox"
}

variable "replica_count" {
  type        = number
  description = "Number of application replicas."
  default     = 1
}

variable "ingress_enabled" {
  type        = bool
  description = "Whether to create the Ingress resource."
  default     = false
}

variable "ingress_host" {
  type        = string
  description = "Hostname for the Ingress rule."
  default     = "confapi.local"
}
