# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Style: Ruby", "bin/rubocop"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Importmap vulnerability audit", "bin/importmap audit"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"
  step "Tests: Rails", "bin/rails test"
  # Output kept in log/browser-last.log, so a flaky failure can be read afterwards.
  step "Tests: Browser", "bash -o pipefail -c 'bin/rails test:system 2>&1 | tee log/browser-last.log'"
  step "Tests: Seeds", "env RAILS_ENV=test bin/rails db:seed:replant"

  # Optional: Run system tests
  # step "Tests: System", "bin/rails test:system"

  # Signoff (the green GitHub status) happens in .githooks/pre-push, once the
  # commit is on GitHub.
end
