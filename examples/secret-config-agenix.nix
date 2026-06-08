{ config, inputs, ... }:
{
  imports = [
    inputs.agenix.nixosModules.default
    inputs.nixos-anywherelan.nixosModules.awl
  ];

  age.secrets.awl-config = {
    file = ../secrets/awl-config.age;
    owner = "root";
    group = "root";
    mode = "0400";
  };

  services.awl = {
    enable = true;
    configFile = config.age.secrets.awl-config.path;

    # Seed once, then allow AWL to mutate peer state through the CLI/UI.
    replaceConfig = false;

    interfaceName = "awl0";
    firewall.allowedTCPPorts = [ 22 ];
  };
}
