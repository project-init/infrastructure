terramate {
  config {
    disable_safeguards = [
      "git-untracked",
      "git-uncommitted"
    ]

    # Enable recommended experiments
    # tmgen: Required for Terramate Catalyst code generation
    # scripts: Enables the use of the 'script' block
    # outputs: Enables sharing outputs between stacks
    experiments = [
      "scripts",
      "outputs",
      "tmgen",
    ]

    run {
      env {
        TF_PLUGIN_CACHE_DIR = "${terramate.root.path.fs.absolute}/.cache/opentofu"
        PATH                = "${terramate.root.path.fs.absolute}/scripts:${env.PATH}"
      }
    }
  }
}
