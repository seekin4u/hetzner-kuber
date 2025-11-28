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

resource "kubernetes_secret" "eso_key" {
  metadata {
    name      = "awssm-secret"
    namespace = "external-secrets"
  }

  type = "Opaque"

  data = {
    "access-key" = var.eso_access_key
    "secret-access-key" = var.eso_secret_key
  }

  depends_on = [helm_release.eso]
}

resource "tls_private_key" "flux" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
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

  depends_on = [module.kubernetes]
}

# https://github.com/controlplaneio-fluxcd/flux-operator/blob/main/config/terraform/main.tf
resource "helm_release" "flux_operator" {
  name             = "flux-operator"
  namespace        = "flux-system"
  repository       = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  chart            = "flux-operator"
  create_namespace = true

  depends_on = [module.kubernetes]
}
resource "helm_release" "flux_instance" {
  depends_on = [helm_release.flux_operator]

  name       = "flux-instance"
  namespace  = "flux-system"
  repository = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  chart      = "flux-instance"

  # https://artifacthub.io/packages/helm/flux-instance/flux-instance?modal=values
  values = [
    yamlencode({
      instance = {
        distribution = {
          version   = "2.7.x"
          registry  = "ghcr.io/fluxcd"
          artifact  = "oci://ghcr.io/controlplaneio-fluxcd/flux-operator-manifests:latest"
        }

        components = [
          "source-controller",
          "kustomize-controller",
          "helm-controller",
          "notification-controller",
        ]

        cluster = {
          type   = "kubernetes"
          domain = "cluster.local"
        }

        # https://github.com/controlplaneio-fluxcd/flux-operator/blob/main/api/v1/fluxinstance_types.go#L272
        sync = {
          interval  = "1m"
          kind      = "GitRepository"
          name      = "hetzner-kuber"
          provider  = "generic"
          url       = "ssh://git@github.com/seekin4u/hetzner-kuber.git"
          ref       = "refs/heads/controlplane"
          path      = "./"
          pullSecret = "ssh-keypair"
        }
      }
    })
  ]
}

resource "kubernetes_namespace" "apps_preview" {
  depends_on = [ module.kubernetes ]
  metadata {
    name = "apps-preview"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

# flux -n app-preview create secret git github-auth \
#   --url=https://github.com/org/app \
#   --username=flux \
#   --password=${GITHUB_TOKEN}
 
 resource "kubernetes_secret" "github_auth" {
  metadata {
    name      = "github-auth"
    namespace = "apps-preview"
  }

  type = "Opaque"

  data = {
    "username" = "flux"
    "password" = var.github_pat
    "url"  = "https://github.com/seekin4u/hetzner-kuber"
  }

  depends_on = [kubernetes_namespace.apps_preview]
}