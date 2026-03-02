script "build" {
  description = "Build the module"
  job {
    commands = [
      ["mise", "run", "build:module", tm_substr(terramate.stack.path.absolute, 1, -1), env.VERSION],
    ]
  }
}

script "release" {
  description = "Release the module (no-op)"
  job {
    commands = [
      ["echo", "no-op"],
    ]
  }
}

script "test" {
  description = "Initialize and test the module"
  job {
    commands = [
      ["tofu", "init"],
      ["tofu", "test"],
    ]
  }
}

script "mark" "changed" {
  description = "Mark module as changed for release-please"
  job {
    commands = [
      ["mise", "run", "mark:changed-module", tm_substr(terramate.stack.path.absolute, 1, -1), env.PR_NUMBER],
    ]
  }
}
