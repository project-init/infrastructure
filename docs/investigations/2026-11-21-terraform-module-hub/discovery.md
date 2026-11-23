# [Terraform Module Hub](https://project-init.atlassian.net/browse/INIT-1020)

Develop every public Terraform module in `project-init/infrastructure` and publish each release to its
`terraform-aws-<name>` repository, where the Terraform and OpenTofu registries pick it up.

## Goals

- Change, test, and release all 19 public modules from one repository.
- Keep every registry address and pinned consumer version working, with no edits to consumers of the existing 17.
- Publish only reviewed code from the hub's `main`; no person pushes to a module repository.
- Document how to add a module, cut a release, and register a new module repository on both registries.

## Useful Context

INIT-1017 targets the roughly $500 per month the organization spends on AWS and GitHub. Every module repository is
public, so its GitHub Actions minutes cost nothing; this work saves maintainer time and CI noise, not dollars.

**The module repositories duplicate everything.** The organization publishes 17 public modules, each in its own
`terraform-aws-<name>` repository, because both registries require one repository per module with `vX.Y.Z` tags at its
root. A survey of all 17 on 2026-11-21 found:

- About 16 boilerplate files copied into every repository, roughly 270 copies in total. CODEOWNERS, `dependabot.yml`,
  `pr.yaml`, `.terraform-docs.yml`, and the issue templates match byte for byte.
- OpenTofu pinned at 8 versions, from 1.10.6 to 1.13.9.
- About 3,200 workflow runs across the 17 repositories, and 2–3 open Dependabot PRs in 11 of them.
- A release process with no checks: a maintainer types a tag into `mise start-release`, and release-drafter publishes
  notes. CI checks formatting and terraform-docs drift only; no repository runs `tofu validate` or `tofu test`.
- Rulesets made by hand per repository, already drifted on `strict_required_status_checks_policy` and
  `do_not_enforce_on_create`. Each covers the default branch; no repository protects its tags.
- Dependabot bumps that fail the docs check until a maintainer regenerates the README by hand, as in
  `terraform-aws-simple-network` #6.
- Commits in 6 of the 17 since 2026-05-22, 28 of the 40 in `rds` and `cognito`. The other 11 had none.

**Every module has consumers, all pinned exactly.** All 17 modules appear in infrastructure-platform, admin-platform,
business-platform, data-platform, project-vnext, or software-assembly-line. `account-context` has 6 consuming
repositories, `version-manager` has 5, and `rds` has 1,426 Terraform Registry downloads. Both registries list every tag
of all 17 modules. The Terraform Registry usually lists a new tag within seconds: of 45 sampled releases, 41 appeared
within five minutes, and the other four took 13 to 130 minutes. The OpenTofu Registry scans for tags every 15 minutes:
across 28 releases of seven modules since June 2026, it took a median of 17 minutes to find a tag, and 50 at the
slowest.

**The hub already exists.** `project-init/infrastructure` is public, and its README names it the module hub, with the
single-module repositories as "the output of this hub." It holds `modules/aws/s3` and `modules/aws/sqs` and has no
publish step. business-platform and data-platform consume those two through `git::` SHAs, and software-assembly-line
through the repo-wide tags `v0.0.2` and `v0.0.3`. The `sqs` example references `project-init/sqs/aws` 0.1.0, which
nobody has published yet.

**INIT-685 designed this once.** Its [investigation](../2026_%207_22_terraform_monorepo/problem.md) proposed importing
the 17 modules, versioning each with release-please, and syncing them out with `git subtree split`. Nobody built it.
Since then, the hub reset its layout on 2026-08-09 and replaced release-please with repo-wide tags cut by
`devex sre release` on 2026-11-16. This discovery differs from INIT-685 in four ways:

- It syncs with snapshot commits. A plain subtree split produces history unrelated to each module repository's `main`,
  and pushing it needs the force-push their rulesets block.
- It publishes `s3` and `sqs` as registry modules.
- It defines the publisher identity, rulesets, and failure handling.
- It versions modules by extending `devex sre release`, which the hub already uses, instead of release-please.

The hub's `main` ruleset requires 2 approvals, last-push approval, and code-owner review, but the hub lacks a CODEOWNERS
file, so the code-owner rule does nothing. The ruleset requires no status checks, so a PR that fails CI can merge. The
hub also lacks Dependabot; its weekly `update-deps.yaml` runs `devex sre dependencies upgrade --all`, which the hub
configures for mise tools only.

The 16 private modules in `infrastructure-platform/terraform/modules` depend on the organization's account model and
stay there.

## Proposed Approach

Develop the 19 public modules in the hub, version each with an extended `devex sre release`, and publish every release
as a snapshot commit to its module repository through a dedicated GitHub App.

**Hub layout.** Modules live at `modules/aws/<name>/` and hold only module code: `.tf` files, `examples/`, `tests/`, and
a terraform-docs README. CI, Dependabot, CODEOWNERS (`* @project-init/Admin`), an MIT `LICENSE`, `.terraform-docs.yml`,
the mise toolchain, and the templates exist once, at the hub root, with one pinned OpenTofu version. The hub deletes the
`.terraform.lock.hcl` files `s3` and `sqs` commit today and ignores the name: OpenTofu reads a lock file in a root
module alone, and no module repository commits one.

**Versioning.** `devex sre release` learns per-module releases. With `--module=aws/rds`, it lists the commits since
`aws/rds-v*` that touch `modules/aws/rds/`, suggests a bump from their conventional-commit titles, and pushes an
annotated tag such as `aws/rds-v0.5.1` whose message carries the grouped changes. With a bare `--module`, it shows a
multi-select list of every module with releasable commits and asks for each picked module's bump, defaulting to its
suggestion. `--changed` releases all of them without prompting. `--bump` cannot combine with a bare `--module` or with
`--changed`, and `--module` cannot combine with `--changed`. Multi-module runs push each tag in its own `git push`,
because GitHub fires no push event for a push carrying more than three tags. A module with no hub tag yet starts from a
baseline version recorded in `.sre/release.yaml` (rds 0.5.0, secret 0.2.0, s3 and sqs 0.0.0, released at 0.1.0 with an
explicit minor bump), and `allowMajorVersionBump: false` still applies: a breaking change suggests a minor bump with a
warning. The devex change ships in its own devex release, and the hub then bumps its devex pin. The repo-wide `v*` tags,
`release.yaml`, and `release-drafter.yml` retire after the first per-module release, and `.sre/release.yaml` turns
repo-wide releases off; the published `v0.0.x` tags stay.

**Publishing.** An admin runs `devex sre release` locally, as today. Each pushed `aws/<name>-vX.Y.Z` tag triggers a hub
workflow that runs `scripts/publish-module.sh` in the `publish` environment, one run per tag, so modules released
together publish independently. For each tag, the script:

1. Maps the hub tag to `modules/aws/<name>` and `project-init/terraform-aws-<name>`, and fails unless the tagged commit
   is reachable from `origin/main`.
2. Mints a GitHub App token scoped to that one repository.
3. Skips steps 4 and 5 when the module repository's tag already sits on the step 5 commit for this hub SHA, so a rerun
   only finishes step 6. Fails when the tag points at any other commit.
4. Replaces the module repository's contents with the module directory, the hub's MIT `LICENSE`, and the module's
   terraform-docs README with a note that sends contributors to the hub.
5. Commits `release v0.5.1 from infrastructure@<sha>`, allowing an empty commit, and pushes the commit and tag `v0.5.1`
   in one `git push --atomic`.
6. Creates the GitHub Release from the hub tag's message, unless it exists.

The workflow holds a concurrency group per module, so two releases of one module never push at once. Its last step
dispatches a second workflow, `verify-module.yaml`, which polls both registries and fails unless the Terraform Registry
lists the version within 10 minutes and the OpenTofu Registry within 90. The publish run ends before any registry poll,
so `devex sre release` reports its result within its 30-minute watch.

A `workflow_dispatch` entry point republishes one hub tag, and `--dry-run` takes a module and a hub ref, builds the
snapshot, and prints its diff without an App token or a push.

**Module repositories become output-only.** Each loses its workflows, Dependabot configuration, templates, and issues,
and its README note and description point to the hub.

**Access.** An org admin creates the GitHub App `project-init-module-publisher` with `contents: write`,
`workflows: write`, and the metadata read GitHub always grants, and installs it on the module repositories only. GitHub
rejects App pushes that remove workflow files unless the App holds `workflows: write`. Only an existing repository's
first snapshot removes workflow files, so the org admin drops `workflows: write` after the last import. The App's key
lives in the hub's `publish` environment, which accepts deployments from `main` and from `aws/*` tags alone. Terraform
in `infrastructure-platform/terraform/accounts/github` manages the App's installation and the module repositories'
rulesets from `csv/repos.csv`: only the App may push, force-push and deletion stay blocked, a new tag ruleset makes `v*`
tags immutable, and org admins keep break-glass bypass. The same Terraform adds a hub tag ruleset that lets only
`@project-init/Admin` create `aws/*` tags and blocks moving or deleting them. It also takes over the hub's hand-made
`main` ruleset and requires the hub's CI check.

**CI.** Hub PR CI keeps the format and docs drift check and adds `tofu init -backend=false && tofu validate` for changed
modules, plus `tofu test` for any changed module with a `tests/` directory. A PR that changes the root toolchain, such
as the OpenTofu pin, covers every module, as does a dispatched run. One job with a fixed name reports the combined
result, and the hub's `main` ruleset requires it, so a failing PR cannot merge.

**Dependencies.** A hub `.github/dependabot.yml` updates Terraform dependencies across `/modules/*/*` in one grouped
monthly PR and updates GitHub Actions. A bump must not fail the docs drift check, so `.terraform-docs.yml` hides the
requirements, providers, and modules tables in every module README, and handwritten README text names no versions. One
generated table in `modules/README.md` lists those versions for every module. PR CI never regenerates it; the weekly
`update-deps.yaml` run does, so the table trails a merged bump by up to a week. devex keeps updating mise tools in that
weekly PR. After the upgrade, the run also reruns `mise docs` and `mise format`, so a tool bump that changes generated
output still passes the drift check. The PR is opened with `GITHUB_TOKEN`, which starts no workflow run, so the workflow
dispatches PR CI on the PR's branch.

**Imports.** `scripts/import-module.sh` copies the `.tf` files, `examples/`, `tests/`, and README from a module
repository's `main` into `modules/aws/<name>/` and records its highest `v*` tag's version as the module's baseline.
Copying `main` means the import's patch release ships any module change merged since that tag. The script prints those
changes, and the import PR title names them, so the release notes carry them. Today only `simple-network` has one, a
`cloudposse/dynamic-subnets` bump from 3.0.1 to 3.1.1. devex fails a release of a module that has neither a tag nor a
baseline.

### Benefits

- Change CI, Dependabot, or the toolchain once instead of 17 times.
- Release several modules in one `devex sre release` run, or one module alone.
- Validate every module before release; today no repository does, and the hub's `main` requires no checks.
- Detect a missed registry ingest after every publish: 10 minutes for the Terraform Registry, 90 for OpenTofu.
- Publish only admin-tagged commits on `main`; today any maintainer's typed tag publishes.
- End ruleset drift by managing module repository rulesets in Terraform.

### Considerations

- **The devex extension gates the first publish.** The hub cannot cut a module tag until the devex release ships and the
  hub's pin moves to it.
- **Releases stay manual.** A merged change waits until an admin runs `devex sre release`, as it does today.
- **Module repositories keep only release history from here on.** Per-commit history after each import lives in the hub;
  earlier history stays intact in each module repository.
- **Org and repository admins can bypass the hub's `main` ruleset.** A direct admin push followed by an admin's tag
  would publish unreviewed code. The module repositories grant admins the same bypass today, so this adds no new path.
- **A module that uses another keeps the registry address.** `terraform-aws-vpn` uses `project-init/secret/aws` v0.1.0;
  a relative path breaks once the module publishes alone. Bumping that pin is a change to vpn.
- **A registry may skip a version.** The verify workflow fails, as it would have for the four Terraform Registry
  releases that listed 13 to 130 minutes late. The Terraform Registry offers a manual resync. OpenTofu offers none: we
  rerun the verify workflow after its next scan and raise an issue on `opentofu/registry` if the version stays missing.
- **Registry verification outlasts the release command.** devex stops watching a run after 30 minutes, and 9 of the 28
  sampled OpenTofu listings took longer. `devex sre release` therefore reports the publish alone; a missed version fails
  the verify workflow later, in the Actions tab.
- **The hub's version table can lag.** `modules/README.md` trails a merged bump by up to a week; the `.tf` files and the
  registries stay authoritative.
- **Hub CI tests against the newest providers.** Without lock files, a new provider release can fail CI on an unrelated
  PR. Consumers would meet the same break.
- **A bad release stays published.** Consumers pin exact versions, so fix forward with a patch release; never delete or
  move a tag.
- **A root-only change releases nothing.** devex counts only commits that touch a module's directory, so bumping the
  hub's OpenTofu pin affects CI alone.

### Alternatives

- **Subtree split with full history.** Import each repository with `git subtree add` so later splits fast-forward.
  Rejected: fragile imports, root files forced into each module directory, and any divergence breaks the push.
- **Force-push mirror.** Rejected: rewrites public history, needs force-push bypass, and breaks links to old commits.
- **Seventeen repositories with shared boilerplate.** Keep each module repository, move CI into a reusable workflow, and
  manage rulesets in Terraform. Rejected: each repository keeps its own toolchain pin, Dependabot queue, and unchecked
  release, and `s3` and `sqs` still need a publish path.
- **Lockstep repo-wide versions.** Rejected: every module jumps to one shared version and releases with no changes.
- **release-please in monorepo mode.** Rejected: its release PRs need an identity other than `GITHUB_TOKEN` to trigger
  CI, which means either a second GitHub App to manage or a publisher key that can also approve hub PRs and push hub
  tags.
- **Consumers on `git::` subdirectory sources.** Rejected: drops the registries and changes every consumer.
- **A fine-grained PAT as publisher.** Rejected: tied to one person, expires, and bypasses rulesets only through that
  person's admin role.
- **Infrastructure-platform or a new repository as hub.** Rejected: infrastructure-platform is private, and a new
  repository strands `s3` and `sqs`.

## Phasing

Estimates are rough and assume one engineer.

1. **Foundations (2–3 weeks).** Create the GitHub App; add its installation, the rulesets, and the `terraform-aws-s3`
   and `terraform-aws-sqs` rows in infrastructure-platform; move boilerplate, CODEOWNERS, Dependabot, and validation
   into the hub, move dependency versions to one table, then require the hub's CI check on `main`; extend and release
   devex, then pin the hub to it; build the publish workflow and script, and the import script.
2. **Pilots (2–3 days).** Publish `s3` and `sqs` v0.1.0 to new repositories to prove creation and registry sign-up.
   Import `subdomain` and publish v0.1.1 over its existing repository to prove the snapshot path.
3. **Imports (1–2 weeks).** Import the remaining 16 modules with the import script, one PR each, ending with a patch
   release. Import `secret` before `vpn`, then the rest by consumer count, lowest first. Drop the App's
   `workflows: write` after the last one.
4. **Consumers and docs (3 days).** Move `s3` and `sqs` consumers to registry addresses and write the hub guides.

## Ownership and Access

The `@project-init/Admin` team owns the hub and keeps owning the module repositories. An org admin creates the GitHub
App and holds its key. Contributors open PRs against the hub. Modules stay public on both registries.

## Assumptions

- GitHub environment deployment policies accept an `aws/*` tag pattern, so tag-triggered runs can read the App key.
- Both registries ingest tags on snapshot commits as they ingest hand-pushed tags today.
- The OpenTofu Registry lists a version within 90 minutes of its tag; the slowest of the 28 sampled releases took 50.
- Registering a new module repository on each registry takes a one-time manual step, which for OpenTofu is a submission
  issue on `opentofu/registry`; the `s3` and `sqs` pilot records the exact steps.
- A Dependabot `directories` glob of `/modules/*/*` picks up every module, including modules added later.
- A PR CI run that the weekly dependency workflow dispatches with `GITHUB_TOKEN` satisfies the required check on its PR.

## Unknowns

None. A work item verifies each assumption above.
