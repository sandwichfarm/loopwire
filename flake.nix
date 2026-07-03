{
  description = "Loopwire development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { nixpkgs, ... }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forEachSystem = nixpkgs.lib.genAttrs systems;
    in
    {
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
