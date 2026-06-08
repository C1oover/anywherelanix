# Updating AWL release hashes

Example for `x86_64-linux`:

```bash
version=0.17.0
url="https://github.com/anywherelan/awl/releases/download/v${version}/awl-linux-amd64-v${version}.tar.gz"
nix store prefetch-file --hash-type sha256 "$url"
```

Convert a raw SHA-256 to SRI if needed:

```bash
nix hash convert --hash-algo sha256 --to sri RAW_HASH_HERE
```

Then update the corresponding entry in `pkgs/awl-bin/default.nix` and run:

```bash
nix flake check
```
