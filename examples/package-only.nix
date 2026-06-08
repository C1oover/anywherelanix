{ inputs, pkgs, ... }:
{
  nixpkgs.overlays = [ inputs.nixos-anywherelan.overlays.default ];

  environment.systemPackages = [
    pkgs.awl
  ];
}
