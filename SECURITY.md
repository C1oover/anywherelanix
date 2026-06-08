# Security

This repository does not implement AWL cryptography. It packages upstream AWL and
provides a NixOS service module.

For issues in AWL itself, report upstream at:

https://github.com/anywherelan/awl

For issues in this Nix package/module, open an issue in this repository.

Do not put AWL private identity material or passwords in `services.awl.settings`
unless you intentionally accept storing them in `/nix/store`.
