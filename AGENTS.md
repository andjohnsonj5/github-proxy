**Background Commands**: Use `systemd-run` not `nohup`/&

**Scope**: The `systemd-run` guidance and examples below are intended specifically for use by the Codex agent when it needs to launch transient services from automation in this repository. These examples should not be assumed appropriate for other tooling, users, or environments without review.

- **Why**: `nohup somecmd &` starts a process in the background but relies on shell job control and leaves the process unmanaged by the init system. `systemd-run` launches the command as a transient systemd service which gives you better lifecycle, logging, and cleanup tools.
- **Policy**: Do not use `nohup` or `cmd &` to run long-running background commands in this repository's examples and automation. Prefer `systemd-run`.
- **Important flags**: When using `systemd-run` here, avoid `--scope` and avoid `--user` unless you fully understand the implications; prefer a simple system transient service invocation so systemd controls the unit.

Examples

- Run the OpenResty proxy in background (transient service):
  `systemd-run --unit=gh-proxy --slice=system.slice --property=RemainAfterExit=no --description="OpenResty GitHub proxy" /usr/bin/env bash -c 'cd /path/to/project/openresty && exec openresty -p "$PWD" -c nginx.conf -g "daemon off;"'`

- Run a one-off command in background and capture exit status via journalctl logs:
  `systemd-run --unit=my-task --slice=system.slice --description="one-off job" /usr/bin/env bash -c 'your-command --arg'`

Usage Restrictions

- **Do not use with Docker**: Do not use `systemd-run` to start or manage services inside Docker containers or to control container lifecycles. Containers and Docker orchestrators have different init and process models; launching transient systemd units inside containers is unsupported and can lead to unexpected behavior.
- **Do not embed in scripts or checked-in automation**: Avoid placing `systemd-run` calls inside repository scripts, Dockerfiles, CI configs, or other checked-in automation. This guidance is for ephemeral, agent-driven invocations — not for persistent scripts or tooling.
- **Only for Codex transient shell calls**: These examples are intended specifically for the Codex agent when it needs to launch short-lived transient services from an ad-hoc shell invocation. Other tooling, users, or environments should choose appropriate alternatives and review implications before adopting `systemd-run`.

Notes & Best Practices

- Prefer `--unit` to name the transient unit so it is easy to find and manage: `systemctl status my-proxy` / `journalctl -u my-proxy`.
- Avoid `--scope` here: `--scope` attaches processes to the caller's scope and is intended for grouping existing processes; it is not the right primitive for launching a managed systemd transient service from automation in this repo.
- Avoid `--user` here unless you explicitly need a per-user unit: system-level transient services are easier to manage from scripts and CI runners.
- Use `--slice=system.slice` (or appropriate slice) and `--property` options to control resource/accounting behavior when necessary.
- Use `exec` inside the command so the launched process becomes PID 1 of the transient service's process tree (helps signals and logging behave correctly).

Managing transient units

- Check status: `systemctl status <unit>`
- View logs: `journalctl -u <unit>`
- Stop & remove: `systemctl kill --kill-who=main --signal=SIGTERM <unit>` then `systemctl reset-failed <unit>` if necessary.

Security & cleanup

- Be careful when launching processes on behalf of other users or in multi-tenant environments; transient systemd units inherit system privileges unless constrained.
- When running ephemeral units in CI/test runs, ensure you clean them up after tests. Prefer naming units with a predictable prefix and `--property=TimestampMonotonic=` or set timeouts inside the service if available.
