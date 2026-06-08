{ inputs, ... }:
{
  imports = [ inputs.nixos-anywherelan.nixosModules.awl ];

  services.awl = {
    enable = true;

    # Written to the Nix store. Keep it non-secret.
    settings = {
      loggerLevel = "info";
      httpListenAddress = "127.0.0.1:8639";
      p2pNode.name = "nix-host";
      vpn = {
        interfaceName = "awl0";
        ipNet = "10.66.0.1/24";
      };
      socks5 = {
        listenerEnabled = false;
        proxyingEnabled = false;
      };
    };

    replaceConfig = false;
    firewall.allowedTCPPorts = [ 22 443 ];
  };
}
