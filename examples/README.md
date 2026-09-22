# Per-project images

A project opts in by adding `.claude-sandbox/Dockerfile` to **its own** repo.
The launcher hashes that directory, tags the result
`claude-sandbox/<project>:<base-version>-<hash>`, and rebuilds only when the
contents change.

Keeping it in the project repo means the sandbox definition travels with the
code and gets reviewed like any other change.

Rules for a project image:

- Start `FROM claude-code-base:<version>` or use the `BASE_IMAGE` build arg,
  which the launcher passes automatically.
- End with `USER claude`. Never leave `USER root` as the final instruction.
- Do not add `sudo`, and do not add setuid binaries.
- Do not bake secrets. `ARG` values persist in `docker history`. Use
  `--env-file` at run time instead.
- Point tool caches at `/home/claude/.cache/...` so they land on the
  per-project cache volume and rebuilds start warm.

`make verify` asserts the first four of these against a built project image.

Builds run on the normal bridge with ordinary egress, so `apt-get` works at
build time. It does not work at run time: the agent is non-root with no sudo.
