# Grateful Deploy — working notes for Claude Code

## Stack (fixed)
- Rails 8, **SQLite + Solid suite** (Queue/Cache/Cable). No Postgres/Redis/Sidekiq.
- Hotwire (Turbo + Stimulus). Server-rendered, minimal JS.
- Mail: **letter_opener** in dev, **MailerSend** (SMTP) in prod.
- Runs locally only (v1): bound to 127.0.0.1, never deployed. It drives Kamal in other repos under
  `config.x.repos_root` (~/Work by default).
- **Public repo, O'Saasy license.** Never commit anything about the owner's own fleet: real IPs,
  domains, app names or emails. Tests use `example.com` domains and documentation IPs (203.0.113.x, 198.51.100.x).

## What this app does
A button-based dashboard (like hatchbox.io) for Kamal deploys. The user never types commands:
each button maps to a fixed, allowlisted Kamal or SSH command built in the backend.
- Commands run with `Open3` argument arrays, never shell strings, inside the app's `repo_path`.
- Repo paths, destinations and config files come from the database (`config/fleet.yml` → `Fleet.import`;
  gitignored, copied from `config/fleet.example.yml` by `bin/setup`),
  never from request params. **Add app** (`/repos` → `apps#new`) is the one way in from the UI: it
  offers only repos `KamalRepo.scan` finds under `config.x.repos_root` (~/Work), reads their Kamal
  config without running its ERB, only on servers GD already knows, and writes the new entry into
  `config.x.fleet_file` (the source checkout's fleet.yml, linked into production by `bin/release`) to review.
- All output passes through `SecretScrubber` before it is stored or broadcast.
- One running deploy per app at a time.

## What already exists (built by the foundation script — do NOT recreate)
- **Auth:** Identity/User split, passwordless **6-digit magic-link** login. Working end to end:
  email → code emailed → code entry → session. See `SessionsController`, `Authentication`
  concern, `LoginMailer`, `Identity#issue_login_code!` / `#login_code_valid?`.
- **Tenancy:** `Current.organization` resolved in `ApplicationController#set_organization`
  (single-tenant via `Organization.first` today). `Current.user` set on sign-in.
- Root route → `apps#index` (the apps dashboard). `/servers` shows each server's RAM, disk and containers.
- **CI runs locally, not on GitHub Actions:** `.githooks/pre-push` runs `bin/ci` (steps in
  `config/ci.rb`), blocks the push if it fails, and marks the commit green with `gh signoff`
  when it passes. `bin/setup` enables the hook per clone. Add CI steps to `config/ci.rb`.

## Conventions
- **Delegated types** for "same role, different attributes" modeling; keep superclasses lean
  (only universal FKs on the parent), type-specific attributes on the type tables.
- **Shared behavior via concerns** with a common interface; let each type define divergent pieces.
- **Name entities, not values** (no `Year` table with a `year` column).
- **Tokenized public shares** (`has_secure_token` + unauthenticated token-scoped controller)
  instead of building logins for external/read-only users.
- **Route reads through `Current.organization`** — never a hardcoded id or `.first` outside
  `set_organization`. Keeps multi-tenancy a one-line change later.

## Deferred until actually needed
- Multi-tenant membership/roles/switching (single-tenant now; structure is ready).
- Stripe billing (add when the app monetizes).

## Build the domain on top
Add domain models/controllers/views. The foundation (auth, tenancy, mail) is done.
