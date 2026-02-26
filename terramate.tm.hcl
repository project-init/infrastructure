terramate {
  config {
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
        TF_PLUGIN_CACHE_DIR = "${terramate.root.path.fs}/.cache/opentofu"
        PATH                = "${terramate.root.path.fs}/scripts:${env.PATH}"
      }
    }
  }
}
