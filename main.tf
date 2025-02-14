locals {
  network_name = var.network_name == null ? docker_network.k3s.0.name : var.network_name
  cluster_endpoint = coalesce(
    var.cluster_endpoint,
    docker_container.k3s_server.network_data[0].ip_address
  )
  server_config = var.cluster_endpoint == null ? var.server_config : concat(["--tls-san", var.cluster_endpoint], var.server_config)
}

# Mimics https://github.com/rancher/k3s/blob/master/docker-compose.yml
resource "docker_volume" "k3s_server" {
  name = "k3s-server-${var.cluster_name}"
}

resource "docker_network" "k3s" {
  count = var.network_name == null ? 1 : 0
  name  = "k3s-${var.cluster_name}"
}

resource "docker_image" "registry" {
  name         = "registry:2"
  keep_locally = true
}

resource "docker_container" "registry_mirror" {
  for_each = var.registry_mirrors
  image    = docker_image.registry.image_id
  name     = format("registry-%s-%s", replace(each.key, ".", "-"), var.cluster_name)
  restart  = var.restart
  env      = each.value

  networks_advanced {
    name = local.network_name
  }

  mounts {
    target = "/var/lib/registry"
    source = "registry"
    type   = "volume"
  }
}

resource "local_file" "registries_yaml" {
  content  = <<EOF
---
mirrors:
%{for key, registry_mirror in docker_container.registry_mirror~}
  ${key}:
    endpoint:
      - http://${registry_mirror.network_data[0].ip_address}:5000
%{endfor~}
EOF
  filename = "${path.module}/registries.yaml"
}

resource "docker_volume" "k3s_server_kubelet" {
  count = var.csi_support ? 1 : 0
  name  = "k3s-server-kubelet-${var.cluster_name}"
}

resource "docker_container" "k3s_server" {
  image      = docker_image.k3s.image_id
  name       = "k3s-server-${var.cluster_name}"
  restart    = var.restart
  command    = concat(["server"], local.server_config)
  privileged = true
  env = [
    "K3S_TOKEN=${var.k3s_token}",
  ]

  networks_advanced {
    name = local.network_name
  }

  mounts {
    target = "/run"
    type   = "tmpfs"
  }

  mounts {
    target = "/var/run"
    type   = "tmpfs"
  }

  mounts {
    target = "/etc/rancher/k3s/registries.yaml"
    source = abspath(local_file.registries_yaml.filename)
    type   = "bind"
  }

  mounts {
    target = "/var/lib/rancher/k3s"
    source = docker_volume.k3s_server.name
    type   = "volume"
  }

  dynamic "mounts" {
    for_each = var.csi_support ? [1] : []

    content {
      target = "/var/lib/kubelet"
      source = docker_volume.k3s_server_kubelet[0].mountpoint
      type   = "bind"

      bind_options {
        propagation = "rshared"
      }
    }
  }

  dynamic "ports" {
    for_each = var.server_ports

    content {
      internal = ports.value.internal
      external = ports.value.external
      ip       = ports.value.ip
      protocol = ports.value.protocol
    }
  }
}

resource "null_resource" "destroy_k3s_server" {
  triggers = {
    server_container_name = docker_container.k3s_server.name
    hostname              = docker_container.k3s_server.hostname
  }

  provisioner "local-exec" {
    when    = destroy
    command = "docker exec ${self.triggers.server_container_name} kubectl drain ${self.triggers.hostname} --delete-emptydir-data --disable-eviction --ignore-daemonsets --grace-period=60"
  }
}

module "worker_groups" {
  for_each              = var.worker_groups
  source                = "./modules/worker_group"
  image                 = docker_image.k3s.image_id
  containers_name       = format("%s-%s", var.cluster_name, each.key)
  restart               = var.restart
  network_name          = local.network_name
  k3s_token             = var.k3s_token
  k3s_url               = format("https://%s:6443", docker_container.k3s_server.network_data[0].ip_address)
  registries_yaml       = abspath(local_file.registries_yaml.filename)
  server_container_name = docker_container.k3s_server.name

  node_count  = each.value.node_count
  node_labels = each.value.node_labels
  node_taints = each.value.node_taints
}

resource "null_resource" "wait_for_cluster" {
  provisioner "local-exec" {
    command     = var.wait_for_cluster_cmd
    interpreter = var.wait_for_cluster_interpreter
    environment = {
      ENDPOINT = format("https://%s:6443", local.cluster_endpoint)
    }
  }
  depends_on = [
    docker_container.k3s_server,
  ]
}

data "external" "kubeconfig" {
  program = ["sh", "${path.module}/kubeconfig.sh"]

  query = {
    container_name       = docker_container.k3s_server.name
    container_ip_address = local.cluster_endpoint
  }

  depends_on = [
    null_resource.wait_for_cluster,
  ]
}
