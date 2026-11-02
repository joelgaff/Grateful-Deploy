# Grateful Deploy

A local dashboard for Kamal deploys, in the spirit of hatchbox.io. Each app gets
a card with its running version, health and memory, and a page with Deploy,
Roll back and Logs buttons. Every button runs one fixed, allowlisted Kamal or
SSH command inside that app's own repo; nothing is typed.

It runs on your own machine, bound to 127.0.0.1, with your SSH keys and your
app repos. It's built for Linux with a systemd user service; the app launcher
entry is for [Omarchy](https://omarchy.org) and is skipped elsewhere.

## Setup

```sh
bin/setup --skip-server     # gems, databases, the pre-push CI hook, and config/fleet.yml
bin/rails credentials:edit  # makes config/master.key and your own credentials
```

Then list your servers and apps in `config/fleet.yml` (see [Apps and servers](#apps-and-servers))
and run `bin/release`.

Grateful Deploy looks for app repos under `~/Work`; set `GRATEFUL_DEPLOY_REPOS_ROOT`
to use another folder.

## Using it

Open <http://127.0.0.1:3100> and sign in with your email; a 6-digit code is
emailed (see [Mail](#mail)).

Production runs as a systemd user service from its own checkout
(`~/.local/share/grateful-deploy`) of the last pushed commit, so local edits never
go live by accident.

```sh
bin/release                                   # put the last pushed commit live (refuses while a deploy runs)
systemctl --user status grateful-deploy        # is it running?
journalctl --user -u grateful-deploy -f        # its log
systemctl --user stop grateful-deploy          # stop it (start it again with start)
```

`bin/release` installs the service the first time and starts it at login, and
adds **Grateful Deploy** to the app launcher (Super+Space). Opening it starts the
service if it isn't running, then shows Grateful Deploy in its own window. Closing
the window leaves the service running, so status checks and deploys carry on.

## Apps and servers

`config/fleet.yml` lists the servers and the apps Kamal deploys to them; it is
the only place an app's repo, Kamal destination or config file comes from.
`bin/setup` copies it from `config/fleet.example.yml`. It stays out of git,
since it maps out your servers. After editing it, run `bin/release` to load it.

**Add app** (`/repos`) and **Add server** write new entries into it for you to review.

Per app:

- `destination: production` runs `kamal -d production`; `config_file: config/deploy.production.yml` runs `kamal -c …`.
- `kamal_binary: global` uses the `kamal` on PATH instead of the repo's `bin/kamal`.
- `kamal_env:` plain values the repo's `deploy.yml` reads from ENV (a server IP, a domain). Never secrets:
  those stay in the repo's own `.env`. A name with no value keeps Deploy off until it's filled in.
- `health_https: true` checks an HTTPS-only app over TLS on the server's `proxy_https_port`.

## Deploys from a terminal or CI

Kamal's own deploy lock is read with every status check. While a deploy that
Grateful Deploy didn't start holds it, Deploy and Rollback are off and the app
page shows who holds it, with a **Release Kamal lock** button for a lock left
behind by a deploy that died.

Each app repo has `.kamal/hooks/post-deploy` (canonical copy:
`config/kamal_hooks/post-deploy`), which reports a finished deploy to
Grateful Deploy so the history and rollback list include it. It sends the token in
`~/.config/grateful-deploy/hook_token`, which `bin/release` creates; on a machine
without that file the hook does nothing. To replace the token, delete the file
and run `bin/release`.

## Mail

Login codes go through MailerSend once its credentials are complete:

```sh
bin/rails credentials:edit
# mailersend:
#   username: …
#   password: …
#   from: grateful-deploy@<a domain verified in MailerSend>
```

Then run `bin/release`. Until all three are set, production uses letter_opener,
as development does: each email opens in the browser on this machine.

## Development

```sh
bin/setup        # gems, databases, the pre-push CI hook
bin/dev          # dev server on http://127.0.0.1:3101 (production has 3100)
bin/rails test   # unit and integration tests
bin/ci           # everything the pre-push hook runs, including browser tests
```

Browser tests need Chromium and chromedriver from the system packages
(`/usr/bin/chromium`, `/usr/bin/chromedriver`); Selenium never downloads one.

`git push` runs `bin/ci` first and blocks the push if it fails, then marks the
commit green on GitHub with `gh signoff`.

## Safety

- Commands are argument arrays from a fixed allowlist (`KamalCommand::ACTIONS`,
  `ServerProbe::COMMANDS`), run inside the app's repo; nothing from a request reaches them.
- Every line of output is masked by `SecretScrubber` (keys, tokens, passwords,
  emails) before it is saved or shown.
- One deploy per app at a time; deploys stop after 20 minutes and can be canceled.

## License

Grateful Deploy is released under the [O'Saasy License](LICENSE.md): use it,
change it and share it freely, but don't offer it to others as a hosted service.
