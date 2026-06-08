{ lib
, stdenvNoCC
, fetchurl
}:

let
  version = "0.17.0";

  # Upstream headless Linux release archives are named:
  # awl-linux-${awlArch}-v${version}.tar.gz
  sources = {
    x86_64-linux = {
      awlArch = "amd64";
      hash = "sha256-tnHqxZ0OfiG2lOW2J/N40udMnN+B5vk9X/9KuIjb8g8=";
    };
    aarch64-linux = {
      awlArch = "arm64";
      hash = "sha256-IWrnu1FE6rjK8T36pdQ755Mc/rzWMer97J5Yz49zymc=";
    };
    i686-linux = {
      awlArch = "386";
      hash = "sha256-cda1NnTa6JoAAIKyX/bE3wRhG7PEgGuGDr5ymH5+Auw=";
    };
    armv7l-linux = {
      awlArch = "arm";
      hash = "sha256-JUH/CMgKx0DgnSkfpvo2QGPZOkg5fh01T6jtm6VNV/0=";
    };
    mips-linux = {
      awlArch = "mips";
      hash = "sha256-G+yk3bQNuhtbBRVa+Ca0z5A816s9j+U8qQ5jmVIULf4=";
    };
    mipsel-linux = {
      awlArch = "mipsle";
      hash = "sha256-MfUsJQdKybkOwuHGSAmZijYY33DX178GUPsxgQZl/fo=";
    };
  };

  source = sources.${stdenvNoCC.hostPlatform.system} or (throw "awl-bin: unsupported system ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "awl-bin";
  inherit version;

  src = fetchurl {
    url = "https://github.com/anywherelan/awl/releases/download/v${finalAttrs.version}/awl-linux-${source.awlArch}-v${finalAttrs.version}.tar.gz";
    inherit (source) hash;
  };

  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 awl "$out/bin/awl"

    runHook postInstall
  '';

  passthru = {
    upstreamVersion = finalAttrs.version;
    supportedSystems = builtins.attrNames sources;
  };

  meta = with lib; {
    description = "Headless Anywherelan peer-to-peer mesh VPN daemon";
    longDescription = ''
      Anywherelan (AWL) is a peer-to-peer mesh VPN and SOCKS5 proxy for
      connecting personal devices without a centralized control plane. This
      package installs the upstream prebuilt headless awl daemon.
    '';
    homepage = "https://github.com/anywherelan/awl";
    changelog = "https://github.com/anywherelan/awl/releases/tag/v${finalAttrs.version}";
    license = licenses.mpl20;
    mainProgram = "awl";
    platforms = builtins.attrNames sources;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
})
