# Helm Release
# https://search.opentofu.org/provider/hashicorp/helm/latest/docs/resources/release

resource "helm_release" "base" {
  chart            = "base"
  create_namespace = true
  name             = "base"
  namespace        = "istio-system"
  repository       = var.chart_repository

  version = var.istio_version
}

resource "helm_release" "cni" {
  depends_on = [
    helm_release.istiod
  ]

  chart      = "cni"
  name       = "istio-cni"
  namespace  = "istio-system"
  repository = var.chart_repository

  values = [
    yamlencode(local.cni_helm_values)
  ]

  version = var.istio_version
}

resource "helm_release" "istiod" {
  depends_on = [
    helm_release.base
  ]

  chart      = "istiod"
  name       = "istiod"
  namespace  = "istio-system"
  repository = var.chart_repository

  values = [
    file("${path.module}/../helm/istiod.yml"),
    yamlencode(local.istiod_helm_values)
  ]

  version = var.istio_version
}

resource "helm_release" "ztunnel" {
  depends_on = [
    helm_release.cni
  ]

  chart      = "ztunnel"
  name       = "ztunnel"
  namespace  = "istio-system"
  repository = var.chart_repository

  values = [
    yamlencode(local.ztunnel_helm_values)
  ]

  version = var.istio_version
}
