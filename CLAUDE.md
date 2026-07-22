# CLAUDE.md

Agent guidance for this repo lives in [AGENT.md](./AGENT.md) — read that
first. It covers role conventions, what's intentionally out of scope
(secrets, remote hosts, a CLI wrapper), and the tag-propagation gotcha in
`site.yml`/`uninstall.yml`.

Claude Code-specific notes:

- This repo manages the user's real, personal devices. Treat
  `ansible-playbook site.yml`/`uninstall.yml` runs the same way you'd
  treat any action with real side effects on a machine — confirm before
  running them unprompted, especially `uninstall.yml`.
- Prefer `--check --diff` to show what a change would do before running
  it for real.
