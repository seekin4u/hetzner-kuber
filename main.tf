module "kubernetes" {
  source  = "hcloud-k8s/kubernetes/hcloud"
  version = "5.0.0"

  cluster_name = "k8s"
  hcloud_token = var.hcloud

  cluster_kubeconfig_path  = "kubeconfig"
  cluster_talosconfig_path = "talosconfig"

  cert_manager_enabled       = true
  cilium_gateway_api_enabled = true

  talos_public_ipv6_enabled            = false
  cluster_autoscaler_discovery_enabled = false

  control_plane_nodepools = [
    { name = "control", type = "cx23", location = "nbg1", count = 1 }
  ]
  worker_nodepools = [
    { name = "worker", type = "cx23", location = "nbg1", count = 2 }
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

resource "helm_release" "eso" {
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = "1.1.0"

  name      = "external-secrets"
  namespace = "external-secrets"

  create_namespace = true

  values = [
    <<-EOF
    installCRDs: true
    crds:
      createClusterExternalSecret: true
      createClusterSecretStore: true
    EOF
  ]
}
 