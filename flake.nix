# ==================================================================================================
# claude-statusline Development Flake
# ==================================================================================================

{
  description = "Modular, non-blocking Claude Code statusline with pluggable cost providers";

  nixConfig = {
    extra-substituters = [ "https://hakula.cachix.org" ];
    extra-trusted-public-keys = [
      "hakula.cachix.org-1:7zwB3fhMfReHdOjh6DmnaLXgqbPDBcojvN9F+osZw0k="
    ];
  };

  # ------------------------------------------------------------------------------------------------
  # Inputs
  # ------------------------------------------------------------------------------------------------
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    devkit = {
      url = "github:hakulab/devkit/v3";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # ------------------------------------------------------------------------------------------------
  # Outputs
  # ------------------------------------------------------------------------------------------------
  outputs =
    {
      self,
      nixpkgs,
      devkit,
    }:
    let
      inherit (nixpkgs) lib;
      inherit (import ./flake.nix) description;

      runtimeInputs =
        pkgs:
        (with pkgs; [
          bash
          coreutils
          curl
          flock
          git
        ])
        ++ lib.optional (pkgs ? ccusage) pkgs.ccusage;

      mkClaudeStatusline =
        pkgs:
        (devkit.lib.mkLib pkgs).mkNuApplication {
          pname = "claude-statusline";
          version = "0.1.0";
          src = ./src;
          runtimeInputs = runtimeInputs pkgs;
          meta = {
            inherit description;
            homepage = "https://github.com/hakulab/claude-statusline";
            license = lib.licenses.mit;
            platforms = lib.platforms.all;
          };
        };

      platformKey = p: {
        inherit (p) config isStatic;
      };

      packageFor =
        pkgs:
        let
          locked = self.packages.${pkgs.stdenv.hostPlatform.system}.claude-statusline or null;
        in
        if
          locked != null
          && platformKey pkgs.stdenv.buildPlatform == platformKey locked.stdenv.buildPlatform
          && platformKey pkgs.stdenv.hostPlatform == platformKey locked.stdenv.hostPlatform
          && pkgs.stdenv.hostPlatform == pkgs.stdenv.targetPlatform
        then
          locked
        else
          mkClaudeStatusline pkgs;

      homeModuleKey = "${self}/flake.nix#homeModules.default";
    in
    # ----------------------------------------------------------------------------------------------
    # Overlay and Home Manager Module
    # ----------------------------------------------------------------------------------------------
    {
      overlays.default = _: prev: { claude-statusline = packageFor prev; };

      homeModules.default = {
        _class = "homeManager";
        _file = homeModuleKey;
        key = homeModuleKey;
        imports = [
          (import ./nix/home-manager.nix {
            inherit packageFor;
          })
        ];
      };
    }
    // devkit.lib.eachSystem devkit.lib.systems (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        dk = devkit.lib.mkLib pkgs;

        commonInputs = runtimeInputs pkgs;

        claudeStatusline = mkClaudeStatusline pkgs;

        preCommit = dk.preCommit {
          src = ./.;
          hooks = {
            nu-check.enable = true;
            prettier.enable = true;
            shellcheck.enable = true;
            shfmt.enable = true;
          };
        };
      in
      {
        # ------------------------------------------------------------------------------------------
        # Dev Shell
        # ------------------------------------------------------------------------------------------
        devShells.default = pkgs.mkShell {
          name = "claude-statusline-dev";

          packages = [
            dk.nushell
            dk.nu-test
          ]
          ++ commonInputs;

          inputsFrom = [ preCommit ];
        };

        # ------------------------------------------------------------------------------------------
        # Packages
        # ------------------------------------------------------------------------------------------
        packages = {
          default = claudeStatusline;
          claude-statusline = claudeStatusline;
        };

        # ------------------------------------------------------------------------------------------
        # Checks
        # ------------------------------------------------------------------------------------------
        checks = import ./nix/checks.nix {
          inherit
            self
            pkgs
            dk
            claudeStatusline
            commonInputs
            ;
        };

        # ------------------------------------------------------------------------------------------
        # Formatter
        # ------------------------------------------------------------------------------------------
        formatter = pkgs.nixfmt-tree;
      }
    );
}
