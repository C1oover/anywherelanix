{ inputs, ... }:
{
  imports = [ inputs.nixos-anywherelan.nixosModules.awl ];

  services.awl = {
    enable = true;
    dataDir = "/var/lib/anywherelan";

    interfaceName = "awl0";
    firewall.allowedTCPPorts = [ 22 ];
  };
}
