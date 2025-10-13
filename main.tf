terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0.2"
    }
  }
}

provider "kubernetes" {
  config_path = "${path.module}/kubeconfig"
}

provider "helm" {
  kubernetes = {
    config_path = "${path.module}/kubeconfig"
  }
}

module "kubernetes" {
  source  = "hcloud-k8s/kubernetes/hcloud"
  version = "3.3.0"

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
