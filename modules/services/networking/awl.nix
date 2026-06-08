{ config, lib, pkgs, ... }:

let
  cfg = config.services.awl;

  inherit (lib)
    concatStringsSep
    escapeShellArg
    filterAttrs
    hasPrefix
    literalExpression
    makeBinPath
    mapAttrs
    mapAttrsToList
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    optional
    optionalAttrs
    optionalString
    recursiveUpdate
    types;

  jsonFormat = pkgs.formats.json { };

  canonicalConfigHome = "/var/lib";
  canonicalDataDir = "${canonicalConfigHome}/anywherelan";
  usesCanonicalDataDir = cfg.dataDir == canonicalDataDir;

  # AWL v0.17.0 runs `ifconfig lo0 alias 127.0.0.66 up` when started as root.
  # That is a BSD/macOS-style command. Linux already routes 127.0.0.0/8 to
  # loopback, and AWL works without creating a lo0 alias. Swallow only that exact
  # invocation and delegate all other ifconfig calls to net-tools.
  ifconfigShim = pkgs.writeShellScriptBin "ifconfig" ''
    set -eu

    if [ "$#" -eq 4 ] \
      && [ "$1" = "lo0" ] \
      && [ "$2" = "alias" ] \
      && [ "$3" = "127.0.0.66" ] \
      && [ "$4" = "up" ]; then
      exit 0
    fi

    exec ${pkgs.nettools}/bin/ifconfig "$@"
  '';

  filterNull = filterAttrs (_: value: value != null);

  mkKnownPeer = peerId: peer: filterNull {
    inherit peerId;
    name = peer.name;
    alias = peer.alias;
    ipAddr = peer.ipAddr;
    domainName = peer.domainName;
    createdAt = peer.createdAt;
    lastSeen = peer.lastSeen;
    confirmed = peer.confirmed;
    declined = peer.declined;
    weAllowUsingAsExitNode = peer.weAllowUsingAsExitNode;
    allowedUsingAsExitNode = peer.allowedUsingAsExitNode;
  };

  hasDeclarativePeers = cfg.peers != { };

  generatedSettings = recursiveUpdate cfg.settings (optionalAttrs hasDeclarativePeers {
    knownPeers = mapAttrs mkKnownPeer cfg.peers;
    p2pNode.autoAcceptAuthRequests = false;
  });

  hasGeneratedConfig = generatedSettings != { };
  generatedConfig = jsonFormat.generate "config_awl.json" generatedSettings;

  hasConfigFile = cfg.configFile != null;
  hasConfigSource = hasConfigFile || hasGeneratedConfig;

  configTarget = "${cfg.dataDir}/config_awl.json";
  configTargetArg = escapeShellArg configTarget;
  dataDirArg = escapeShellArg cfg.dataDir;

  baseTmp = "${cfg.dataDir}/.config_awl.json.tmp";
  mergedTmp = "${cfg.dataDir}/.config_awl.json.merged.tmp";
  preservedTmp = "${cfg.dataDir}/.config_awl.json.preserved.tmp";

  baseTmpArg = escapeShellArg baseTmp;
  mergedTmpArg = escapeShellArg mergedTmp;
  preservedTmpArg = escapeShellArg preservedTmp;

  configFileArg = escapeShellArg (toString cfg.configFile);
  generatedConfigArg = escapeShellArg (toString generatedConfig);

  environmentAttrs = {
    # This is service-local, not global. AWL appends "anywherelan", yielding
    # /var/lib/anywherelan/config_awl.json for the default dataDir.
    XDG_CONFIG_HOME = canonicalConfigHome;
  } // optionalAttrs (!usesCanonicalDataDir) {
    # Required only for non-default dataDir values because AWL otherwise hardcodes
    # the final directory component to "anywherelan".
    AWL_DATA_DIR = cfg.dataDir;
  } // cfg.environment;

  environment = mapAttrsToList (name: value: "${name}=${toString value}") environmentAttrs;

  envExports = concatStringsSep "\n" (mapAttrsToList
    (name: value: "export ${name}=${escapeShellArg (toString value)}")
    environmentAttrs);

  awlPath = makeBinPath ([ ifconfigShim ] ++ cfg.extraPackages);

  cliWrapper = pkgs.writeShellScriptBin "awl" ''
    ${envExports}
    export PATH=${escapeShellArg awlPath}:$PATH
    exec ${cfg.package}/bin/awl "$@"
  '';

  preStartScript = pkgs.writeShellScript "awl-pre-start" ''
    set -eu

    install -d -m 0700 -o ${escapeShellArg cfg.user} -g ${escapeShellArg cfg.group} ${dataDirArg}

    ${optionalString hasConfigSource ''
      if [ ${if cfg.replaceConfig then "1" else "0"} -eq 1 ] || [ ! -s ${configTargetArg} ]; then
        rm -f ${baseTmpArg} ${mergedTmpArg} ${preservedTmpArg}

        ${optionalString (hasConfigFile && hasGeneratedConfig) ''
          ${pkgs.jq}/bin/jq -S -s '.[0] * .[1]' ${configFileArg} ${generatedConfigArg} > ${baseTmpArg}
        ''}

        ${optionalString (hasConfigFile && !hasGeneratedConfig) ''
          install -m 0600 ${configFileArg} ${baseTmpArg}
        ''}

        ${optionalString (!hasConfigFile && hasGeneratedConfig) ''
          install -m 0600 ${generatedConfigArg} ${baseTmpArg}
        ''}

        ${optionalString cfg.preserveIdentityOnReplace ''
          if [ -s ${configTargetArg} ]; then
            ${pkgs.jq}/bin/jq -S --slurpfile old ${configTargetArg} '
              if ((.p2pNode.identity // "") == "") and (($old[0].p2pNode.identity // "") != "") then
                (.p2pNode //= {})
                | .p2pNode.identity = $old[0].p2pNode.identity
                | .p2pNode.peerId = ($old[0].p2pNode.peerId // .p2pNode.peerId)
              else
                .
              end
            ' ${baseTmpArg} > ${preservedTmpArg}
            mv -f ${preservedTmpArg} ${baseTmpArg}
          fi
        ''}

        install -m 0600 -o ${escapeShellArg cfg.user} -g ${escapeShellArg cfg.group} ${baseTmpArg} ${mergedTmpArg}
        mv -f ${mergedTmpArg} ${configTargetArg}
        rm -f ${baseTmpArg} ${preservedTmpArg}
      fi
    ''}
  '';

  capabilitiesConfig = mkIf (cfg.user != "root" || cfg.hardening.enable) {
    AmbientCapabilities = cfg.capabilities;
    CapabilityBoundingSet = cfg.capabilities;
  };

  hardeningConfig = mkIf cfg.hardening.enable {
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectHome = true;
    ProtectSystem = "strict";
    ReadWritePaths = [ cfg.dataDir ] ++ cfg.hardening.readWritePaths;
    RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK" ];
    LockPersonality = true;
    RestrictRealtime = true;
    SystemCallArchitectures = "native";
  };
in
{
  options.services.awl = {
    enable = mkEnableOption "headless Anywherelan mesh VPN daemon";

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ../../../pkgs/awl-bin { };
      defaultText = literalExpression "pkgs.callPackage ../../../pkgs/awl-bin { }";
      example = literalExpression "inputs.nixos-anywherelan.packages.${pkgs.system}.awl";
      description = ''
        AWL package to run. Use this if you overlay a newer package, switch
        from the binary package to a future source-built package, or pin an
        internal build.
      '';
    };

    dataDir = mkOption {
      type = types.str;
      default = canonicalDataDir;
      description = ''
        Runtime state directory containing AWL's config_awl.json, identity
        material, peer state, and peerstore data. The default uses AWL's normal
        XDG lookup path with XDG_CONFIG_HOME=/var/lib, so the service does not
        need AWL_DATA_DIR. Non-default values require AWL_DATA_DIR because AWL
        otherwise hardcodes the final directory name to anywherelan.
      '';
    };

    user = mkOption {
      type = types.str;
      default = "root";
      description = ''
        User that runs AWL. The default is root because AWL creates and manages
        a TUN interface. Non-root operation requires suitable capabilities and
        should be tested on the target host.
      '';
    };

    group = mkOption {
      type = types.str;
      default = "root";
      description = "Group that runs AWL.";
    };

    createUser = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Create services.awl.user and services.awl.group as system account/group.
        Usually false when running as root.
      '';
    };

    capabilities = mkOption {
      type = types.listOf types.str;
      default = [
        "CAP_NET_ADMIN"
        "CAP_NET_RAW"
        "CAP_NET_BIND_SERVICE"
        "CAP_CHOWN"
      ];
      description = ''
        Linux capabilities retained for AWL when running non-root or when
        systemd hardening is enabled.
      '';
    };

    configFile = mkOption {
      type = types.nullOr (types.either types.path types.str);
      default = null;
      example = literalExpression "config.age.secrets.awl-config.path";
      description = ''
        Optional base config_awl.json source. Use this for agenix, sops-nix, or
        another secret manager when you want to provide AWL identity material
        without writing it into the Nix store. Inline settings and declarative
        peers are merged over this file before AWL starts.
      '';
    };

    settings = mkOption {
      type = jsonFormat.type;
      default = { };
      example = literalExpression ''
        {
          loggerLevel = "info";
          httpListenAddress = "127.0.0.1:8639";
          p2pNode.name = "nix-host";
          vpn = {
            interfaceName = "awl0";
            ipNet = "10.66.0.1/24";
          };
        }
      '';
      description = ''
        Inline AWL configuration rendered to config_awl.json. These values are
        merged over configFile, if configFile is set. Inline settings are useful
        for non-secret daemon defaults. Do not put p2pNode.identity, HTTP
        basic-auth passwords, SOCKS5 passwords, or other secrets here unless you
        intentionally want them in the Nix store.
      '';
    };

    peers = mkOption {
      type = types.attrsOf (types.submodule ({ ... }: {
        options = {
          name = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Peer-provided display name to write into knownPeers.";
          };

          alias = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Local alias for this peer. This becomes the preferred display name.";
          };

          ipAddr = mkOption {
            type = types.nullOr types.str;
            default = null;
            example = "10.66.0.2";
            description = "Static AWL overlay IP address for this peer.";
          };

          domainName = mkOption {
            type = types.nullOr types.str;
            default = null;
            example = "laptop";
            description = "Static .awl hostname without the .awl suffix.";
          };

          createdAt = mkOption {
            type = types.str;
            default = "1970-01-01T00:00:00Z";
            description = "RFC3339 timestamp used for the generated knownPeers entry.";
          };

          lastSeen = mkOption {
            type = types.str;
            default = "1970-01-01T00:00:00Z";
            description = "RFC3339 timestamp used for the generated knownPeers entry.";
          };

          confirmed = mkOption {
            type = types.bool;
            default = true;
            description = "Whether to mark this peer as confirmed in AWL.";
          };

          declined = mkOption {
            type = types.bool;
            default = false;
            description = "Whether to mark this peer as declined in AWL.";
          };

          weAllowUsingAsExitNode = mkOption {
            type = types.bool;
            default = false;
            description = "Whether this host allows the peer to use it as a SOCKS5 exit node.";
          };

          allowedUsingAsExitNode = mkOption {
            type = types.bool;
            default = false;
            description = "Whether the peer allows this host to use it as a SOCKS5 exit node.";
          };
        };
      }));
      default = { };
      example = literalExpression ''
        {
          "12D3KooWexamplePeerId" = {
            alias = "laptop";
            ipAddr = "10.66.0.2";
            domainName = "laptop";
          };
        }
      '';
      description = ''
        Declarative AWL known peers keyed by peer ID. These entries are rendered
        into config_awl.json as knownPeers and p2pNode.autoAcceptAuthRequests is
        forced to false. Use replaceConfig=true when you want NixOS rebuilds and
        service restarts to remove peers not declared here.
      '';
    };

    replaceConfig = mkOption {
      type = types.bool;
      default = true;
      description = ''
        If true, copy/merge configFile, settings, and peers into dataDir on every
        service start. If false, seed config_awl.json only when it does not
        already exist. The default is true so declared peers remain authoritative.
      '';
    };

    preserveIdentityOnReplace = mkOption {
      type = types.bool;
      default = true;
      description = ''
        When replaceConfig is true and an existing config_awl.json contains a
        generated p2pNode.identity, preserve that identity if the replacement
        config does not explicitly provide one. This keeps the local peer ID
        stable without putting the private identity into the Nix store.
      '';
    };

    interfaceName = mkOption {
      type = types.str;
      default = "awl0";
      description = ''
        Expected AWL TUN interface name, used for firewall integration. Keep it
        aligned with your AWL config_awl.json vpn.interfaceName setting.
      '';
    };

    loadTunModule = mkOption {
      type = types.bool;
      default = true;
      description = "Load the Linux tun kernel module at boot.";
    };

    installPackage = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Add a NixOS-aware awl wrapper to environment.systemPackages for CLI
        usage. The wrapper points the CLI at the service config directory and
        includes the service-local ifconfig compatibility shim.
      '';
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = literalExpression ''{ LIBP2P_DEBUG = "1"; }'';
      description = ''
        Extra environment variables for the AWL daemon and installed awl wrapper.
        These variables may override the module's default XDG_CONFIG_HOME or
        AWL_DATA_DIR behavior if you set the same names here.
      '';
    };

    extraPackages = mkOption {
      type = types.listOf types.package;
      default = [ pkgs.iproute2 pkgs.iptables pkgs.coreutils ];
      defaultText = literalExpression "[ pkgs.iproute2 pkgs.iptables pkgs.coreutils ]";
      description = ''
        Packages added to the AWL service PATH. The module also prepends an
        ifconfig compatibility shim for AWL's hardcoded lo0 alias command.
      '';
    };

    limitNOFILE = mkOption {
      type = types.int;
      default = 4000;
      description = "systemd LimitNOFILE for AWL.";
    };

    firewall = {
      trustInterface = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Add services.awl.interfaceName to networking.firewall.trustedInterfaces.
          Convenient, but broad. Strict hosts should prefer allowedTCPPorts and
          allowedUDPPorts.
        '';
      };

      allowedTCPPorts = mkOption {
        type = types.listOf types.port;
        default = [ ];
        example = [ 22 443 ];
        description = "TCP ports allowed on the AWL interface.";
      };

      allowedUDPPorts = mkOption {
        type = types.listOf types.port;
        default = [ ];
        example = [ 53 ];
        description = "UDP ports allowed on the AWL interface.";
      };
    };

    hardening = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Apply conservative systemd hardening. Disabled by default because AWL
          needs network, TUN, DNS, and interface privileges. Enable after basic
          connectivity works.
        '';
      };

      readWritePaths = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Additional writable paths when hardening is enabled.";
      };
    };

    extraServiceConfig = mkOption {
      type = types.attrs;
      default = { };
      example = literalExpression ''{ RestartSec = "10s"; }'';
      description = "Extra systemd serviceConfig merged after module defaults.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = hasPrefix "/" cfg.dataDir;
          message = "services.awl.dataDir must be an absolute path.";
        }
        {
          assertion = !(hasDeclarativePeers && cfg.settings ? knownPeers);
          message = "services.awl: use services.awl.peers or services.awl.settings.knownPeers, not both.";
        }
      ];

      warnings = optional (cfg.settings != { }) ''
        services.awl.settings is written to the Nix store. Do not put AWL
        identity material or passwords there unless that is intentional. For
        secrets, use services.awl.configFile from agenix, sops-nix, or similar.
      '' ++ optional (!usesCanonicalDataDir) ''
        services.awl.dataDir is not /var/lib/anywherelan, so this module must
        set AWL_DATA_DIR for AWL to find that custom path. The default dataDir
        avoids AWL_DATA_DIR by using a service-local XDG_CONFIG_HOME=/var/lib.
      '';

      boot.kernelModules = mkIf cfg.loadTunModule [ "tun" ];
      environment.systemPackages = mkIf cfg.installPackage [ cliWrapper ];

      users.groups = mkIf (cfg.createUser && cfg.group != "root") {
        ${cfg.group} = { };
      };

      users.users = mkIf (cfg.createUser && cfg.user != "root") {
        ${cfg.user} = {
          isSystemUser = true;
          group = cfg.group;
          home = cfg.dataDir;
          createHome = false;
        };
      };

      systemd.tmpfiles.rules = mkIf (!usesCanonicalDataDir) [
        "d ${cfg.dataDir} 0700 ${cfg.user} ${cfg.group} - -"
      ];

      systemd.services.awl = {
        description = "Anywherelan headless mesh VPN daemon";
        documentation = [ "https://github.com/anywherelan/awl" ];
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" "nss-lookup.target" ];
        after = [ "network-online.target" "nss-lookup.target" ];
        path = [ ifconfigShim ] ++ cfg.extraPackages;

        serviceConfig = mkMerge [
          ({
            Type = "simple";
            ExecStartPre = "+${preStartScript}";
            ExecStart = "${cfg.package}/bin/awl";
            WorkingDirectory = cfg.dataDir;
            Environment = environment;
            Restart = "always";
            RestartSec = "5s";
            LimitNOFILE = cfg.limitNOFILE;
            User = cfg.user;
            Group = cfg.group;
            UMask = "0077";
          } // optionalAttrs usesCanonicalDataDir {
            StateDirectory = "anywherelan";
            StateDirectoryMode = "0700";
          })
          capabilitiesConfig
          hardeningConfig
          cfg.extraServiceConfig
        ];
      };
    }

    (mkIf cfg.firewall.trustInterface {
      networking.firewall.trustedInterfaces = [ cfg.interfaceName ];
    })

    (mkIf (!cfg.firewall.trustInterface && (cfg.firewall.allowedTCPPorts != [ ] || cfg.firewall.allowedUDPPorts != [ ])) {
      networking.firewall.interfaces.${cfg.interfaceName} = {
        allowedTCPPorts = cfg.firewall.allowedTCPPorts;
        allowedUDPPorts = cfg.firewall.allowedUDPPorts;
      };
    })
  ]);
}
