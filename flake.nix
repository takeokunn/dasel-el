{
  description = "dasel-el - Emacs interface to dasel";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      eachSystem = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = eachSystem (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.emacs
            pkgs.dasel
          ];

          shellHook = ''
            echo "dasel-el development shell"
            echo "  emacs: $(emacs --version | head -1)"
            echo "  dasel: $(dasel --version)"
            echo ""
            echo "Commands:"
            echo "  make compile       Byte-compile all source files"
            echo "  make test          Run ERT tests"
            echo "  make lint          Run checkdoc"
            echo "  make package-lint  Run package-lint"
            echo "  nix flake check    Run all checks"
            echo ""
            echo "Try interactively (sample files in example/):"
            echo ""
            echo "  # Interactive query - open a file and query with selectors"
            echo "  emacs -Q -L . --eval \"(progn (require 'dasel-interactive) (find-file \\\"example/sample.json\\\"))\""
            echo "  emacs -Q -L . --eval \"(progn (require 'dasel-interactive) (find-file \\\"example/sample.toml\\\"))\""
            echo "  emacs -Q -L . --eval \"(progn (require 'dasel-interactive) (find-file \\\"example/sample.yaml\\\"))\""
            echo "  emacs -Q -L . --eval \"(progn (require 'dasel-interactive) (find-file \\\"example/sample.xml\\\"))\""
            echo "  #   Then: M-x dasel-interactive"
            echo "  #     Selector: name              => \"dasel-el\""
            echo "  #     Selector: author.name       => \"takeokunn\""
            echo "  #     Selector: users.[0].email   => \"alice@example.com\""
            echo "  #     Selector: server.ports.[*]  => [8080, 8443, 9090]"
            echo ""
            echo "  # Format - pretty-print compact JSON"
            echo "  emacs -Q -L . --eval \"(progn (require 'dasel-format) (find-file \\\"example/compact.json\\\"))\""
            echo "  #   Then: M-x dasel-format-buffer"
            echo ""
            echo "  # Convert - transform between formats"
            echo "  emacs -Q -L . --eval \"(progn (require 'dasel-convert) (find-file \\\"example/sample.json\\\"))\""
            echo "  #   Then: M-x dasel-convert  => Convert to: yaml / toml / xml"
            echo "  emacs -Q -L . --eval \"(progn (require 'dasel-convert) (find-file \\\"example/sample.yaml\\\"))\""
            echo "  #   Then: M-x dasel-convert-yaml-to-json"
            echo "  emacs -Q -L . --eval \"(progn (require 'dasel-convert) (find-file \\\"example/sample.toml\\\"))\""
            echo "  #   Then: M-x dasel-convert-toml-to-json"
            echo "  emacs -Q -L . --eval \"(progn (require 'dasel-convert) (find-file \\\"example/sample.xml\\\"))\""
            echo "  #   Then: M-x dasel-convert-xml-to-json"
            echo ""
            echo "  # Edit - modify values in-place (works with any format)"
            echo "  emacs -Q -L . --eval \"(progn (require 'dasel-edit) (find-file \\\"example/sample.json\\\"))\""
            echo "  emacs -Q -L . --eval \"(progn (require 'dasel-edit) (find-file \\\"example/sample.toml\\\"))\""
            echo "  emacs -Q -L . --eval \"(progn (require 'dasel-edit) (find-file \\\"example/sample.yaml\\\"))\""
            echo "  emacs -Q -L . --eval \"(progn (require 'dasel-edit) (find-file \\\"example/sample.xml\\\"))\""
            echo "  #   Then: M-x dasel-edit-put"
            echo "  #     Selector: author.name  | Type: string | Value: new-author"
            echo "  #     Selector: server.port  | Type: int    | Value: 3000"
            echo "  #     Selector: server.debug | Type: bool   | Value: false"
            echo "  #     Selector: users.[0].name | Type: string | Value: Alicia"
          '';
        };
      });

      checks = eachSystem (pkgs:
        let
          emacs = pkgs.emacs;
          emacsWithConsult = pkgs.emacsPackages.emacsWithPackages (epkgs: [ epkgs.consult ]);
          src = pkgs.lib.cleanSource ./.;
        in
        {
          compile = pkgs.stdenvNoCC.mkDerivation {
            name = "dasel-el-compile";
            inherit src;
            nativeBuildInputs = [ emacs ];
            env.EMACS = pkgs.lib.getExe emacs;
            buildPhase = ''
              make compile
            '';
            installPhase = ''
              touch $out
            '';
          };

          compile-consult = pkgs.stdenvNoCC.mkDerivation {
            name = "dasel-el-compile-consult";
            inherit src;
            nativeBuildInputs = [ emacsWithConsult ];
            env.EMACS = pkgs.lib.getExe emacsWithConsult;
            buildPhase = ''
              make compile-consult
            '';
            installPhase = ''
              touch $out
            '';
          };

          test = pkgs.stdenvNoCC.mkDerivation {
            name = "dasel-el-test";
            inherit src;
            nativeBuildInputs = [ emacs ];
            env.EMACS = pkgs.lib.getExe emacs;
            buildPhase = ''
              make test
            '';
            installPhase = ''
              touch $out
            '';
          };
        });
    };
}
