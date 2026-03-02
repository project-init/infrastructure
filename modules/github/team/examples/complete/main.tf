module "example_team" {
  source = "../../"

  name        = "example-team"
  description = "An example GitHub team"
  privacy     = "secret"

  maintainers = ["alice", "bob"]
  members     = ["charlie", "david"]
}