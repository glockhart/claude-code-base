# Verification

Three suites. Run all three after any change to the image, the proxy or the
launcher.

```bash
claude-sandbox doctor   # host setup: docker, images, networks, volumes, firewall
make smoke              # image-only: secrets, privilege, baked config, the guard
make verify             # security assertions: egress, DNS, capabilities
```

## What each check is really proving

**No secrets in the image.** Image environment, build history and the config
directory are all inspected. The config directory must be empty in the image:
the only credential in the system is created at run time, by you, in the auth
volume.

**Egress is blocked.** Three separate claims, and the third is the one that
matters:

1. An allowlisted host is reachable. Proves the proxy is configured.
2. An off-allowlist host returns 403. Proves the allowlist is applied.
3. A connection that bypasses the proxy entirely fails. **Proves the absence of
   a route**, not merely that Squid said no. A tool that ignores the proxy
   environment variables, and plenty do, still cannot phone home.

**DNS is sinkholed.** An internal network does not remove DNS on its own. If
arbitrary names resolve, a low-bandwidth exfiltration channel is open.

**Privilege posture.** Effective capabilities must be all zero and
`NoNewPrivs` must be 1, under both identity profiles.

**Preflight fails closed.** Started on an unrestricted network, the container
must refuse to run. This catches the realistic misconfiguration: a project
compose file adds a service and Docker quietly attaches a second network,
giving silent full egress.

**The two modes both behave.** A normal run prompts; `--yolo` skips. This proves
the policy did not accidentally disable bypass mode.

**Project settings still apply.** A deny rule in a repo's own settings takes
effect, proving managed rules did not displace project rules.

## Manual checks

These need a human and a signed-in session.

**Auth survives.** Sign in once, exit, start a fresh container, confirm
`/status` reports a signed-in account. The account state file matters as much as
the credential: without `CLAUDE_CONFIG_DIR` pointing into the volume it lands
outside and every run re-triggers onboarding.

**File ownership.** Create a file in the workspace from inside, check ownership
on the host.

- macOS: container reports 1000, host reports 501:20. Divergence is correct,
  Docker Desktop virtualises it.
- Debian: both report your uid. Convergence is correct, the remap worked.
- Seeing `root` on the host from a Debian run is the canonical failure and means
  profile B did not engage.

**Editor lockfiles stay private.** Run two projects at once and confirm each
container's `ide` folder holds only its own lockfile.

**Both platforms.** Run everything on the Mac and on the Debian box before
relying on it.
