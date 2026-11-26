# ==================================================================================================
# claude-statusline Flake Checks
# ==================================================================================================

{
  self,
  pkgs,
  dk,
  claudeStatusline,
  commonInputs,
}:

let
  inherit (pkgs) lib;

  canaryPkgs = pkgs.extend (_: prev: { flock = prev.hello; });
  drvPath = pkg: builtins.unsafeDiscardStringContext pkg.drvPath;
in
{
  # ------------------------------------------------------------------------------------------------
  # Home Manager Module
  # ------------------------------------------------------------------------------------------------
  home-module =
    let
      evalModule =
        settings:
        lib.evalModules {
          class = "homeManager";
          modules = [
            self.homeModules.default
            {
              options = {
                home.packages = lib.mkOption { type = lib.types.anything; };
                xdg.configFile = lib.mkOption {
                  type = lib.types.anything;
                  default = { };
                };
              };
              config = {
                _module.args.pkgs = canaryPkgs;
                programs.claude-statusline = {
                  enable = true;
                  inherit settings;
                };
              };
            }
          ];
        };

      emptyEval = evalModule { };
      configuredEval = evalModule {
        defaults.cache_ttl = "30s";
        models."claude-opus-5-5" = "Opus 5.5";
      };

      emptyInstalled = map drvPath emptyEval.config.home.packages;
      installed = map drvPath configuredEval.config.home.packages;
      configFile = configuredEval.config.xdg.configFile."claude-statusline/config.toml".source;
    in
    assert lib.assertMsg (
      emptyInstalled == [ (drvPath claudeStatusline) ]
    ) "Home Manager module with empty settings reconstructed the locked package";
    assert lib.assertMsg (
      !(emptyEval.config.xdg.configFile ? "claude-statusline/config.toml")
    ) "Home Manager module generated config.toml when settings is empty";
    assert lib.assertMsg (
      installed == [ (drvPath claudeStatusline) ]
    ) "Home Manager module reconstructed the locked package";
    pkgs.writeText "home-module.json" (
      builtins.toJSON {
        packages = installed;
        configFile = drvPath configFile;
      }
    );

  # ------------------------------------------------------------------------------------------------
  # Overlay
  # ------------------------------------------------------------------------------------------------
  overlay =
    let
      overlaid = (canaryPkgs.extend self.overlays.default).claude-statusline;
      staticPkgs = canaryPkgs // {
        stdenv = canaryPkgs.stdenv // {
          hostPlatform = canaryPkgs.stdenv.hostPlatform // {
            isStatic = true;
          };
        };
      };
      fallback =
        if pkgs.stdenv.isLinux then
          (pkgs.pkgsMusl.extend self.overlays.default).claude-statusline
        else
          (self.overlays.default staticPkgs staticPkgs).claude-statusline;
    in
    assert lib.assertMsg (
      drvPath overlaid == drvPath claudeStatusline
    ) "overlay reconstructed the locked package";
    assert lib.assertMsg (
      drvPath fallback != drvPath claudeStatusline
    ) "overlay reused the locked package for an incompatible platform";
    pkgs.emptyFile;

  # ------------------------------------------------------------------------------------------------
  # Package and Tests
  # ------------------------------------------------------------------------------------------------
  package = claudeStatusline;

  tests =
    (dk.nuTests {
      src = ../.;
      runtimeInputs = commonInputs;
    }).overrideAttrs
      (prev: {
        env = (prev.env or { }) // {
          TZDIR = "${pkgs.tzdata}/share/zoneinfo";
        };
      });
}
