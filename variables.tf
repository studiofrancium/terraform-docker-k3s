variable "cluster_name" {
  description = "The name of the Kubernetes cluster to create."
  type        = string
}

variable "k3s_version" {
  description = "The K3s version to use"
  type        = string
  default     = "v1.28.5-k3s1"
}

variable "k3s_token" {
  type      = string
  sensitive = true
}

variable "server_config" {
  description = "The command line flags passed to the K3s server"
  type        = list(string)
  default     = []
}

variable "worker_groups" {
  description = "A map defining worker group configurations"

  type = map(object({
    node_count  = number
    node_labels = list(string)
    node_taints = list(string)
  }))

  default = {
    "default" = {
      node_count  = 2
      node_labels = []
      node_taints = []
    },
  }
}

variable "network_name" {
  description = "Docker network to use. Creates a new one if null."
  type        = string
  default     = null
}

variable "wait_for_cluster_cmd" {
  description = "Custom local-exec command to execute for determining if the eks cluster is healthy. Cluster endpoint will be available as an environment variable called ENDPOINT"
  type        = string
  default     = "for i in `seq 1 60`; do if `command -v wget > /dev/null`; then wget --no-check-certificate -O - -q $ENDPOINT/ping >/dev/null && exit 0 || true; else curl -k -s $ENDPOINT/ping >/dev/null && exit 0 || true;fi; sleep 5; done; echo TIMEOUT && exit 1"
}

variable "wait_for_cluster_interpreter" {
  description = "Custom local-exec command line interpreter for the command to determining if the eks cluster is healthy."
  type        = list(string)
  default     = ["/bin/sh", "-c"]
}

variable "csi_support" {
  description = "Container Storage Interface requires /var/lib/kubelet to be mounted with rshared propagation, that can cause some issues."
  type        = bool
  default     = false
}

variable "registry_mirrors" {
  default = {
    "docker.io" = [
      "REGISTRY_PROXY_REMOTEURL=https://registry-1.docker.io",
    ],
    "quay.io" = [
      "REGISTRY_PROXY_REMOTEURL=https://quay.io/repository",
      "REGISTRY_COMPATIBILITY_SCHEMA1_ENABLED=true",
    ],
    "gcr.io" = [
      "REGISTRY_PROXY_REMOTEURL=https://gcr.io",
    ],
    "us.gcr.io" = [
      "REGISTRY_PROXY_REMOTEURL=https://us.gcr.io",
    ],
  }
}

variable "restart" {
  description = "Restart policy for the cluster."
  default     = "unless-stopped"
}

variable "server_ports" {
  description = "Port mappings of the server container."
  default     = []

  type = set(object({
    internal = number
    external = number
    ip       = string
    protocol = string
  }))
}

variable "cluster_endpoint" {
  description = "The api endpoint, when empty it's the container's IP."
  type        = string
  default     = null
}
