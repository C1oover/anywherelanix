# Integration guide

## 1. Add the repo as a flake input

```nix
{
  inputs.nixos-anywherelan.url = "github:YOUR_GITHUB_USER/nixos-anywherelan";
}
```

Use a local path while developing:

```nix
{
  inputs.nixos-anywherelan.url = "path:/home/me/src/nixos-anywherelan";
}
```

## 2. Import the NixOS module

```nix
{
  outputs = { nixpkgs, nixos-anywherelan, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        nixos-anywherelan.nixosModules.awl
      ];
    };
  };
}
```

## 3. Enable the service

```nix
{
  services.awl = {
    enable = true;
    firewall.allowedTCPPorts = [ 22 ];
  };
}
```

## 4. Rebuild

```bash
sudo nixos-rebuild switch --flake .#host
```

## 5. Check AWL

```bash
systemctl status awl
awl cli me status
awl cli me id
```

Exchange peer IDs with other hosts using the normal AWL CLI/web UI flow.
