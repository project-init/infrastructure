# [Consolidate Terraform Modules into Infrastructure Mono Repo](https://project-init.atlassian.net/browse/INIT-685)

There are 17 separate public repositories housing individual Terraform modules. Maintaining them independently creates overhead, dependency updates (e.g., dependabot), releases, and configuration changes must be repeated across every repo. The goal is to consolidate these modules into a single mono repo (project-init/infrastructure) that serves as the source of truth, with an automated release process that pushes updates to the individual module repos and registries.

## Who is Impacted?

* Organizations - Maintaining these modules is an internal infrastructure concern. It affects project-init infrastructure code maintainers.
* Teams - Infrastructure/platform team primarily. Any team that uses or contributes to terraform modules.
* People - Engineers who maintain the terraform modules, engineers who consume them in their projects, and anyone doing releases.

## Useful Context

There are currently 17 separate public terraform module repositories under the
`project-init` GitHub organization, all following the `terraform-aws-<name>` naming
convention required by the Terraform/OpenTofu registry:

- terraform-aws-rds
- terraform-aws-rds-migration-task
- terraform-aws-github-repo-bootstrap
- terraform-aws-simple-network
- terraform-aws-api-service
- terraform-aws-vpn
- terraform-aws-internal-service
- terraform-aws-account-bootstrap
- terraform-aws-secret
- terraform-aws-account-context
- terraform-aws-traffic-management
- terraform-aws-worker-service
- terraform-aws-version-manager
- terraform-aws-subdomain
- terraform-aws-cron
- terraform-aws-cognito
- terraform-aws-ec2-backed-ecs

These modules are consumed by application repos ( like admin-platform, business-platform,
data-platform) via registry short-form source addresses like
`source = "project-init/secret/aws"` with pinned versions.

The `project-init/infrastructure` repo already exists as a partial mono repo with 14
modules under `modules/aws/` and `modules/github/`, managed by Terramate for stack
orchestration and release-please for versioning. All are at v0.0.0 (never released).
The modules currently in the mono repo (e.g., account, identity-center, ipam,
platform-dns) are different from the ones published to the registry -- there is no
overlap yet.

The Terraform and OpenTofu public registries require each module to live in its own
GitHub repository named `terraform-<PROVIDER>-<NAME>`, with semver git tags for
releases. This means the mono repo cannot directly replace the individual repos for
registry publishing. The mono repo must serve as the development source of truth, with
an automated release process that syncs module code out to the individual repos and
tags them for registry pickup.

The toolchain is OpenTofu (not HashiCorp Terraform), though some older lock files
still reference `registry.terraform.io`. The repo also houses non-terraform assets
(apps/, packages/, proto/, gen/), so the directory structure must account for
coexistence with other tooling.

## Suggested Solution

Consolidate the 17 separate terraform module repos into the existing
`project-init/infrastructure` mono repo, establish an automated release pipeline
that syncs changes back to the individual repos for registry compatibility, and
validate the approach end-to-end with a single module before scaling to all.

### Details

1. Define the directory structure for housing both the existing 14 mono repo modules
   and the 17 incoming registry modules under `modules/`, organized by provider
   (e.g., `modules/aws/<name>`, `modules/github/<name>`). Ensure coexistence with
   non-terraform assets already in the repo (apps/, packages/, proto/, gen/).

2. Audit the 17 registry module repos to confirm which are actively used and should
   be brought in first. Cross-reference against module sources in other projects to prioritize actively consumed modules.

3. Build an automated release and sync mechanism (likely GitHub Actions + mise) that,
   on a mono repo release, pushes updated module code to its corresponding
   `terraform-aws-<name>` repo and creates a semver git tag so the Terraform/OpenTofu
   registry picks up the new version.

4. Extend the existing release-please configuration to cover the newly imported
   modules with per-module versioning, tying version bumps to the sync/publish step
   so only changed modules get new releases.

5. Validate the full workflow end-to-end with one module (e.g., terraform-aws-rds):
   import the code, perform a release from the mono repo, confirm the individual repo
   is updated and the registry reflects the new version. If it works for one, it should work
   for all.

6. Confirm that consuming repos (admin-platform, business-platform, data-platform)
   require no source changes, since the individual repos and registry entries remain
   intact as the public interface.

7. Account for CLI and tooling coexistence. The mono repo is intended to also house
   tools that interact with infrastructure modules (e.g., CLIs). The directory
   structure and release process should accommodate this alongside terraform modules.

8. Identify any private terraform modules that should be made public as a separate
   follow-up investigation, rather than bundling that discovery into this effort.

## Knowns

* There are 17 separate public terraform module repos under the project-init GitHub org.
* The infrastructure mono repo already exists with 14 modules, Terramate, and
  release-please configured (all at v0.0.0, never released).
* The Terraform/OpenTofu public registry requires one module per repo with the naming
  convention `terraform-<PROVIDER>-<NAME>` and semver git tags for releases.
* The individual `terraform-aws-*` repos must continue to exist for registry
  compatibility -- the mono repo cannot replace them as the registry source.
* The existing modules in the mono repo and the registry-published modules have no
  overlap.
* The toolchain is OpenTofu.
* Consuming repos use registry short-form source addresses
  (e.g., `source = "project-init/secret/aws"`).

## Assumptions

* All currently public registry modules should be brought into the mono repo.
* release-please can handle per-module versioning across 30+ modules in a single repo without issues (it is already configured for 14).
* The sync-to-individual-repo approach (mono repo -> individual repo on release) is the right pattern vs. alternatives like switching consumers to git source with subdirectory syntax.
* All 17 module repos follow a consistent enough structure to be imported without significant refactoring.
* The existing `modules/aws/<name>` directory convention in the mono repo will work for the incoming modules.

## Unknowns

* The exact mechanism for syncing code from the mono repo to individual repos on
  release (subtree split, GitHub Actions copy, or another approach).
* Whether any of the 17 module repos are legacy/unused and can be excluded.
* How per-module version tracking works when a shared dependency (e.g., AWS provider) is updated -- does every module get a version bump, or only affected ones?
* What the release-please tag format should be to avoid collisions across 30+ modules in one repo (e.g., `aws-rds-v1.0.0` vs `v1.0.0`).
* Whether there are private terraform modules that should also be made public and included.