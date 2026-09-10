# Infrastructure

Repository meant to act as a mono repo for all of the infrastructure modules in use or maintained by Project vNext. The
usage of the modules will be via the Terraform and Tofu registries, which require a single repo to be associated to
them, but this repository can be thought of as the hub for all modules, and the single repositories will just be the
output of this hub for usage in the registries. This allows us to have a single place to update/maintain modules so that
we aren't having to upgrade everything individually, but can instead do it simultaneously where wanted, allowing for
individual updates where necessary.

## Module documentation

Modules live under `modules/<provider>/<module>/`. Place usage examples in
each module's `examples/` directory and link to them from its README.

Keep handwritten explanations outside these markers:

```markdown
<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
```

The content between the markers is generated from the module's Terraform
definitions. Update variable and output descriptions in the `.tf` files.

After changing a module, run from the repository root:

```sh
mise format
mise docs
```

`mise docs` updates every module README using the shared `.terraform-docs.yml`
configuration. Modules added under the same directory layout are included
automatically.

Commit the generated documentation alongside your changes. Pull request CI
runs formatting and documentation generation and fails if either produces
uncommitted changes.