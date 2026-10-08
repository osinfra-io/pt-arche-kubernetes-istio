moved {
  from = helm_release.base
  to   = module.runtime.helm_release.base
}

moved {
  from = helm_release.cni
  to   = module.runtime.helm_release.cni
}

moved {
  from = helm_release.istiod
  to   = module.runtime.helm_release.istiod
}

moved {
  from = helm_release.ztunnel
  to   = module.runtime.helm_release.ztunnel
}
