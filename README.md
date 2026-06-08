# nixos-anywherelan

Reusable Nix package and NixOS module for running the headless
[Anywherelan](https://github.com/anywherelan/awl) (`awl`) daemon.

This repository is intentionally separate from a host configuration. It is meant
for reuse across projects and for possible upstreaming into nixpkgs later.

## What this provides

- `packages.${system}.awl` / `packages.${system}.awl-bin`
- `overlays.default`
- `nixosModules.awl` / `nixosModules.default`
- a headless `services.awl` NixOS module
- examples for mutable state, secret-backed config, inline config, and package-only use

AWL upstream describes the project as a peer-to-peer mesh VPN for connecting your
own devices at the IP level. It uses libp2p discovery/NAT traversal, TLS 1.3
transport, a TUN interface, `.awl` names, and optional SOCKS5 proxying.

## Package model

This repository currently packages the upstream prebuilt Linux `awl` release
archives. That is deliberate: it avoids vendoring AWL's full Go/Flutter/mobile
build machinery into this repo while still giving NixOS a reproducible, hashed
package.

A future nixpkgs PR should prefer a source build if it is practical. Until then,
`awl-bin` is honest about being a binary-native-code package via
`meta.sourceProvenance`.

Default flake outputs are exposed for:

- `x86_64-linux`
- `aarch64-linux`
- `i686-linux`
- `armv7l-linux`

The package expression also includes upstream hashes for `mips-linux` and
`mipsel-linux` so downstream users can `callPackage` it with an appropriate
nixpkgs/system setup.

## Quick integration into another flake

Add the repository as an input:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-anywherelan.url = "github:YOUR_GITHUB_USER/nixos-anywherelan";
  };

  outputs = { self, nixpkgs, nixos-anywherelan, ... }:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./configuration.nix
          nixos-anywherelan.nixosModules.awl
          {
            services.awl.enable = true;
          }
        ];
      };
    };
}
```

For local development before you push it anywhere:

```nix
nixos-anywherelan.url = "path:/absolute/path/to/nixos-anywherelan";
```

Then update your lock file:

```bash
nix flake lock --update-input nixos-anywherelan
```

## Minimal NixOS service

```nix
{
  services.awl.enable = true;
}
```

AWL will create and mutate its runtime state under:

```text
/var/lib/anywherelan
```

Useful first commands on the host:

```bash
systemctl status awl
awl cli me status
awl cli me id
awl cli peers status
```

## Strict firewall example

Expose only selected services over the AWL overlay:

```nix
{
  services.awl = {
    enable = true;
    interfaceName = "awl0";

    firewall.allowedTCPPorts = [ 22 ];
    firewall.allowedUDPPorts = [ ];
  };
}
```

Trusting the whole overlay interface is available but intentionally not the
default:

```nix
{
  services.awl = {
    enable = true;
    firewall.trustInterface = true;
  };
}
```

The strict version is the one you probably want. No need to throw the door open
just because the mesh brought flowers.

## Secret-backed `config_awl.json`

Use this if you want to preserve an AWL identity key or carry a known
`config_awl.json` with agenix, sops-nix, or another secret manager.

```nix
{
  services.awl = {
    enable = true;
    configFile = config.age.secrets.awl-config.path;

    # false seeds only if /var/lib/anywherelan/config_awl.json is missing.
    # true overwrites it on every service start.
    replaceConfig = false;
  };
}
```

The module copies the file into `dataDir`; it does not symlink it. AWL rewrites
`config_awl.json` at runtime, and symlinking a read-only secret would be a tiny
operational bear trap.

## Inline non-secret config

```nix
{
  services.awl = {
    enable = true;

    settings = {
      loggerLevel = "info";
      httpListenAddress = "127.0.0.1:8639";
      p2pNode.name = "nix-host";
      vpn = {
        interfaceName = "awl0";
        ipNet = "10.66.0.1/24";
      };
    };
  };
}
```

Do **not** put `p2pNode.identity`, HTTP basic-auth passwords, SOCKS5 passwords,
or anything secret in `services.awl.settings`. Inline settings are rendered into
the Nix store.

## Install only the `awl` package

No daemon, just the CLI/binary:

```nix
{ inputs, pkgs, ... }:
{
  nixpkgs.overlays = [ inputs.nixos-anywherelan.overlays.default ];
  environment.systemPackages = [ pkgs.awl ];
}
```

Or directly from the flake package output:

```bash
nix run github:YOUR_GITHUB_USER/nixos-anywherelan#awl -- --help
```

## Main module options

- `services.awl.enable`
- `services.awl.package`
- `services.awl.dataDir`
- `services.awl.configFile`
- `services.awl.settings`
- `services.awl.replaceConfig`
- `services.awl.interfaceName`
- `services.awl.firewall.allowedTCPPorts`
- `services.awl.firewall.allowedUDPPorts`
- `services.awl.firewall.trustInterface`
- `services.awl.hardening.enable`
- `services.awl.extraServiceConfig`

## Development

```bash
nix flake check
nix fmt
```

The module evaluation check builds a small NixOS closure with `services.awl`
enabled, which catches common option and systemd mistakes.

## Repository policy

- Keep AWL mutable runtime state out of `/nix/store`.
- Prefer interface-specific firewall rules over trusting the full overlay.
- Keep the package and module independent: users should be able to install only
  the package, only import the module, or override the package.
- Do not invent an ACL/policy plane in this module. AWL handles peer identity and
  discovery; NixOS firewalling handles host policy.
