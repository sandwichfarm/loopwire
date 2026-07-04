{
  description = "Loopwire development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forEachSystem = nixpkgs.lib.genAttrs systems;
      releaseVersion = "0.1.0";
      releaseHashes = {
        x86_64-linux = nixpkgs.lib.fakeHash;
        aarch64-linux = nixpkgs.lib.fakeHash;
      };
    in
    {
      packages = forEachSystem (system:
        let
          pkgs = import nixpkgs { inherit system; };
          loopwireBin = pkgs.callPackage ./packaging/nix/loopwire-bin.nix {
            version = releaseVersion;
            hashes = releaseHashes;
          };
        in
        {
          default = loopwireBin;
          loopwire-bin = loopwireBin;
        });

      lib = forEachSystem (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          mkLoopwireBinPackage = { version, hashes }:
            pkgs.callPackage ./packaging/nix/loopwire-bin.nix {
              inherit version hashes;
            };
        });

      devShells = forEachSystem (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              cargo
              curl
              nodejs_22
              openssl
              pkg-config
              pnpm
              rustc
              webkitgtk_4_1
            ];

            shellHook = ''
              echo "Loopwire dev shell: run pnpm install && pnpm check"
            '';
          };
        });
    };
}
