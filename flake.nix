{
  description = "Nix package and NixOS module for headless Anywherelan (AWL)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      lib = nixpkgs.lib;

      # Systems for which this flake exposes buildable outputs by default.
      # The package expression itself also contains upstream hashes for mips and
      # mipsel so downstream users can callPackage it with a suitable nixpkgs.
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "i686-linux"
        "armv7l-linux"
      ];

      forAllSystems = lib.genAttrs supportedSystems;

      pkgsFor = system: import nixpkgs {
        inherit system;
      };
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = pkgsFor system;
        in
        {
          awl-bin = pkgs.callPackage ./pkgs/awl-bin { };
          awl = self.packages.${system}.awl-bin;
          default = self.packages.${system}.awl;
        });

      apps = forAllSystems (system: {
        awl = {
          type = "app";
          program = "${self.packages.${system}.awl}/bin/awl";
        };
        default = self.apps.${system}.awl;
      });

      overlays.default = final: _prev: {
        awl-bin = final.callPackage ./pkgs/awl-bin { };
        awl = final.awl-bin;
      };

      nixosModules = {
        awl = import ./modules/services/networking/awl.nix;
        default = self.nixosModules.awl;
      };

      checks = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          moduleEval = lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.awl
              ({ ... }: {
                system.stateVersion = "25.11";
                boot.loader.grub.enable = false;
                fileSystems."/".device = "nodev";

                services.awl = {
                  enable = true;
                  package = self.packages.${system}.awl;
                  firewall.allowedTCPPorts = [ 22 ];
                };
              })
            ];
          };
        in
        {
          awl-bin = self.packages.${system}.awl-bin;
          module-eval = pkgs.runCommand "awl-module-eval" { } ''
            test -n ${lib.escapeShellArg moduleEval.config.systemd.services.awl.serviceConfig.ExecStart}
            touch $out
          '';
        });

      devShells = forAllSystems (system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              nixpkgs-fmt
            ];
          };
        });

      formatter = forAllSystems (system: (pkgsFor system).nixpkgs-fmt);
    };
}
