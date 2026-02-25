script "build" {
  description = "Build the module (no-op)"
  job {
    commands = [
      ["echo", "no-op"],
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
