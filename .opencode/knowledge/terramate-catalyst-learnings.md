# Terramate Catalyst Knowledge Base

This document contains a synthesis of learnings about Terramate Catalyst, a tool for enabling self-service Infrastructure-as-Code (IaC).

## 1. Executive Summary
Terramate Catalyst is a "self-service" layer that sits on top of existing IaC tools like Terraform, OpenTofu, or Terragrunt. It allows **Platform Engineers** to package infrastructure patterns into **Components** and **Bundles**, which **Developers** can then easily "scaffold" (instantiate) without writing low-level IaC code themselves.

## 2. Core Primitives

### Components
- **Definition**: Reusable, opinionated infrastructure blueprints defined by platform engineers.
- **Purpose**: Encode organizational standards, governance, naming conventions, and security policies.
- **Content**: Can contain Terraform/OpenTofu resources, modules, Kubernetes manifests, etc.
- **Key Files**:
    - `component.tm.hcl`: Metadata (class, version, name).
    - `inputs.tm.hcl`: Defines inputs (variables) the component accepts.
    - `main.tf.tmgen` (or similar): Terramate templates that generate the actual IaC code based on inputs.

### Bundles
- **Definition**: A collection of one or more Components grouped into a deployable unit.
- **Purpose**: The unit of consumption for developers. Abstracts complexity (state management, provider config).
- **Key Files**:
    - `bundle.tm.hcl`: Metadata and **scaffolding configuration** (where the generated code should go).
    - `inputs.tm.hcl`: High-level inputs exposed to the developer (e.g., "Environment", "Bucket Name").
    - `stack_<name>.tm.hcl`: Defines the Terramate Stack configuration, orchestration rules, and maps Bundle inputs to Component inputs.

## 3. Personas & Responsibilities

| Persona | Responsibility | Action |
| :--- | :--- | :--- |
| **Platform Engineer** | Design, Compliance, Best Practices | Defines `components/` and `bundles/`. Manages the "engine" (Terraform/OpenTofu). |
| **Developer** | Consumes Infrastructure | Runs `terramate scaffold`, selects a Bundle, provides inputs, and deploys via `terramate generate` + `terramate run`. |

## 4. Directory Structure (Best Practice)
Based on `terramate-catalyst-examples`, a recommended repository structure is:

```
.
├── bundles/              # Bundle definitions (Platform Engineer owned)
│   └── example.com/
│       ├── tf-aws-s3/v1/
│       └── ...
├── components/           # Component definitions (Platform Engineer owned)
│   └── example.com/
│       ├── terramate-aws-s3-bucket/v1/
│       └── ...
├── stacks/               # Generated infrastructure (Developer owned / Generated)
│   ├── dev/
│   │   └── s3/
│   │       └── my-bucket/
│   │           ├── _bundle_instance.tm.yml  # The instance definition
│   │           ├── component_main.tf        # Generated Terraform
│   │           └── stack.tm.hcl             # Generated Stack config
│   └── ...
├── imports/              # Shared configuration/mixins
└── terramate.tm.hcl      # Global Terramate config
```

## 5. Workflow

### Step 1: Definition (Platform Engineer)
1.  Create a **Component** in `components/`. Define its inputs and the Terraform code it generates.
2.  Create a **Bundle** in `bundles/`. Define the user-facing inputs and how they map to the Component's inputs. Define the `scaffolding` block to control where stacks are created (e.g., `/stacks/${env}/${name}`).

### Step 2: Consumption (Developer)
1.  Run `terramate scaffold`.
2.  Select a Bundle from the interactive list.
3.  Answer prompts for inputs (e.g., "Enter bucket name", "Select Environment").
4.  Catalyst creates a **Bundle Instance** file (e.g., `_bundle_s3_my-bucket.tm.yml`) in the target directory.

### Step 3: Generation & Deployment (Developer)
1.  Run `terramate generate`. Catalyst reads the Bundle Instance file and generates the actual Terraform code (`.tf`) and Terramate stack config (`stack.tm.hcl`) using the templates defined in the Component.
2.  Run `terramate run -- terraform init`.
3.  Run `terramate run -- terraform apply`.

## 6. Technical Details & Syntax

### Bundle Scaffolding
In `bundle.tm.hcl`:
```hcl
define bundle {
  # Unique alias for the bundle instance
  alias = tm_join("-", [tm_slug(bundle.input.name.value), bundle.input.env.value])

  scaffolding {
    # Dynamic path generation based on inputs
    path = "/stacks/${bundle.input.env.value}/s3/_bundle_s3_${tm_slug(bundle.input.name.value)}.tm.hcl"
    name = tm_slug(bundle.input.name.value)
  }
}
```

### Component Metadata
In `component.tm.hcl`:
```hcl
define component metadata {
  class   = "example.com/tf-aws-s3/v1"
  version = "1.0.0"
  name    = "AWS S3 Bucket Component"
}
```

### Bundle Instance File (Generated)
A YAML file representing the user's choice:
```yaml
apiVersion: terramate.io/cli/v1
kind: BundleInstance
metadata:
  name: my-bucket
  uuid: <uuid>
spec:
  source: /bundles/example.com/tf-aws-s3/v1
  inputs:
    env: dev
    name: my-bucket
    visibility: private
```

## 7. Advanced Capabilities
-   **Cross-Stack Dependencies**: Bundles can query other bundles. For example, an "App" bundle can query existing "Cluster" bundles to let the user select which cluster to deploy to.
-   **Data Sources**: Components can use standard Terraform `data` sources to look up resources (like VPCs) created by other stacks, often using tags (e.g., filtering by `bundle-uuid` or `bundle-alias`).
-   **Reconfiguration**: Users can edit the Bundle Instance YAML file and re-run `terramate generate` to update infrastructure settings (e.g., changing S3 visibility from `private` to `public`). Alternatively, they can run `terramate scaffold reconfigure` to update values interactively.
-   **Automated Onboarding**: The `terramate component create` command can be run inside an existing Terraform or OpenTofu module to automatically generate Catalyst configuration (`component.tm.hcl`, `inputs.tm.hcl`) and wrap the module without writing boilerplate code manually.

## 8. Installation
-   **Integration**: Catalyst is now built directly into the Terramate CLI. 
-   **Via asdf**: `asdf plugin add terramate`
-   **Via Homebrew**: `brew install terramate`
-   *Note: Catalyst features (Scaffolding, Bundles, Components) are available in Terramate CLI Catalyst edition, which is free to use for small projects.*
