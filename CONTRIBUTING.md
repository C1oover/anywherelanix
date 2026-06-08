# Contributing

This repository packages and wires AWL into NixOS. Keep changes boring and easy
to review.

## Expectations

- Run `nix fmt` before committing.
- Run `nix flake check` when Nix is available.
- Keep package changes separate from module behavior changes.
- Keep examples small and copy-pasteable.
- Do not add secrets, generated AWL runtime state, or host-specific peer IDs.

## Updating AWL

See `docs/update-release.md`.

## Module design

The module should expose host policy, not replace AWL's own peer management.
NixOS firewall rules are the right place to restrict services exposed over the
AWL interface.
