# Idempotent: safe to run on every bin/setup and in CI (db:seed:replant).
organization = Organization.first || Organization.create!(name: "Default")
Fleet.import(Rails.root.join("config/fleet.yml"), organization: organization)
