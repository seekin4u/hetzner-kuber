module "kubernetes" {
  source  = "hcloud-k8s/kubernetes/hcloud"
  version = "3.12.2"

  cluster_name = "k8s"
  hcloud_token = var.hcloud

  cluster_kubeconfig_path  = "kubeconfig"
  cluster_talosconfig_path = "talosconfig"

  cert_manager_enabled  = true
  ingress_nginx_enabled = true

  control_plane_nodepools = [
    { name = "control", type = "cax11", location = "fsn1", count = 1 }
  ]
  worker_nodepools = [
    { name = "worker", type = "cax11", location = "fsn1", count = 2 }
  ]
  cluster_delete_protection = false
}

resource "kubernetes_namespace" "monitoring" {
  depends_on = [ module.kubernetes ]
  metadata {
    name = "monitoring"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

resource "helm_release" "kube_prometheus_stack" {
  depends_on       = [kubernetes_namespace.monitoring]
  name             = "monitoring"
  namespace        = "monitoring"
  create_namespace = true

  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"

  values = [
    yamlencode({
      prometheus = {
        prometheusSpec = { maximumStartupDurationSeconds = 300 }
      }
    })
  ]
}

resource "helm_release" "preview_sweeper" {
  depends_on       = [helm_release.kube_prometheus_stack]
  name             = "namespace-preview-sweeper"
  repository       = "oci://ghcr.io/seekin4u/helm"
  chart            = "namespace-preview-sweeper"
  version          = "0.2.0"
  namespace        = "namespace-preview-sweeper"
  create_namespace = true

  values = [
    yamlencode({
      image = { tag = "arm64"}
      replicaCount   = 1
      serviceMonitor = { enabled = false }
      leaderElection = { enabled = false }
      sweepEvery     = "1m"
      ttl            = "2m"
    })
  ]
}

# resource "helm_release" "headlamp" {
#   name       = "headlamp"
#   namespace  = "headlamp"
#   repository = "https://kubernetes-sigs.github.io/headlamp/"
#   chart      = "headlamp"

#   create_namespace = true

#   values = [
#     file("${path.module}/headlamp/headlamp-values.yaml")
#   ]
# }

# ingress:
#   enabled: true

#   ingressClassName: nginx

#   annotations:
#     nginx.ingress.kubernetes.io/rewrite-target: /$2

#   hosts:
#     - host: static.98.13.98.91.clients.your-server.de
#       paths:
#         - path: /headlamp(/|$)(.*)
#           type: ImplementationSpecific

#   tls: []

# config:
#   baseUrl: "/headlamp/"

resource "helm_release" "flux2" {
  repository = "https://fluxcd-community.github.io/helm-charts"
  chart      = "flux2"
  version    = "2.12.4"

  name      = "flux2"
  namespace = "flux-system"

  create_namespace = true
}

resource "kubernetes_secret" "ssh_keypair" {
  metadata {
    name      = "ssh-keypair"
    namespace = "flux-system"
  }

  type = "Opaque"

  data = {
    "identity.pub" = tls_private_key.flux.public_key_openssh
    "identity"     = tls_private_key.flux.private_key_pem
    "known_hosts"  = "github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg="
  }

  depends_on = [helm_release.flux2]
}

resource "helm_release" "flux2_sync" {
  repository = "https://fluxcd-community.github.io/helm-charts"
  chart      = "flux2-sync"
  version    = "1.8.2"

  name      = "flux-system"
  namespace = "flux-system"

  set = [
    {
      name  = "gitRepository.spec.url"
      value = "ssh://github.com/seekin4u/hetzner-kuber.git"
    },
    {
      name  = "gitRepository.spec.ref.branch"
      value = "main"
    },
    {
      name  = "gitRepository.spec.secretRef.name"
      value = kubernetes_secret.ssh_keypair.metadata[0].name
    },
    {
      name  = "gitRepository.spec.interval"
      value = "1m"
    }
  ]

  depends_on = [kubernetes_secret.ssh_keypair]
}
