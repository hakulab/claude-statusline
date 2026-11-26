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
      eval = lib.evalModules {
        class = "homeManager";
        modules = [
          self.homeModules.default
          {
            options = {
              home.packages = lib.mkOption { type = lib.types.anything; };
              xdg.configFile = lib.mkOption { type = lib.types.anything; };
            };
            config = {
              _module.args.pkgs = canaryPkgs;
              programs.claude-statusline = {
                enable = true;
                settings = {
                  defaults.cache_ttl = "30s";
                  models."claude-opus-5-5" = "Opus 5.5";
                };
              };
            };
          }
        ];
      };
      installed = map drvPath eval.config.home.packages;
      configFile = eval.config.xdg.configFile."claude-statusline/config.toml".source;
    in
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

  tests = dk.nuTests {
    src = ../.;
    runtimeInputs = commonInputs;
  };
}
