resource "helm_release" "eso" {
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = "1.1.0"

  name      = "external-secrets"
  namespace = "external-secrets"

  values = [
    "${file("${path.module}/eso-values.yaml")}",
  ]

  create_namespace = true
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
