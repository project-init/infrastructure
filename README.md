# Infrastructure

Repository meant to act as a mono repo for all of the infrastructure modules in use or maintained by Project vNext. The
usage of the modules will be via the Terraform and Tofu registries, which require a single repo to be associated to
them, but this repository can be thought of as the hub for all modules, and the single repositories will just be the
output of this hub for usage in the registries. This allows us to have a single place to update/maintain modules so that
we aren't having to upgrade everything individually, but can instead do it simultaneously where wanted, allowing for
individual updates where necessary.