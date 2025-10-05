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

//helm rlease for grafana
# 2) create ns
# kubectl create ns monitoring

# # 3) install kube-prometheus-stack (includes Grafana, Prometheus, Alertmanager)
# helm upgrade --install kube-prom \
#   prometheus-community/kube-prometheus-stack \
#   --namespace monitoring \
#   --set grafana.service.type=LoadBalancer \
#   --set grafana.adminPassword='S3cureP@ss' \
#   --set prometheus.service.type=ClusterIP