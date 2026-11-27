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

  # Replacing flock ensures a rebuilt package has a different drvPath than the locked one.
  canaryPkgs = pkgs.extend (_: prev: { flock = prev.hello; });
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
        local.provider = "none";
        models."acme/reasoning-v2" = "Reasoning v2";
      };

      configFile = configuredEval.config.xdg.configFile."claude-statusline/config.toml".source;
    in
    assert lib.assertMsg (
      !(emptyEval.config.xdg.configFile ? "claude-statusline/config.toml")
    ) "Home Manager module generated config.toml when settings is empty";
    assert lib.assertMsg (
      map (pkg: pkg.drvPath) configuredEval.config.home.packages == [ claudeStatusline.drvPath ]
    ) "Home Manager module reconstructed the locked package";
    pkgs.runCommand "home-module-check" { } ''
      rendered=$(
        printf '%s' '{"model":{"id":"acme/reasoning-v2"}}' \
          | ${lib.getExe claudeStatusline} \
            --config ${configFile} \
            --cache-dir "$TMPDIR"
      )
      case "$rendered" in
        *"Reasoning v2"*) touch "$out" ;;
        *)
          printf 'unexpected statusline output: %s\n' "$rendered" >&2
          exit 1
          ;;
      esac
    '';

  # ------------------------------------------------------------------------------------------------
  # Overlay
  # ------------------------------------------------------------------------------------------------
  overlay =
    let
      overlaid = (canaryPkgs.extend self.overlays.default).claude-statusline;
      fallback =
        if pkgs.stdenv.isLinux then
          (pkgs.pkgsMusl.extend self.overlays.default).claude-statusline
        else
          let
            staticPlatform = canaryPkgs.stdenv.hostPlatform // {
              isStatic = true;
            };
            staticPkgs = canaryPkgs // {
              stdenv = canaryPkgs.stdenv // {
                hostPlatform = staticPlatform;
                targetPlatform = staticPlatform;
              };
            };
          in
          (self.overlays.default staticPkgs staticPkgs).claude-statusline;
    in
    assert lib.assertMsg (
      overlaid.drvPath == claudeStatusline.drvPath
    ) "overlay reconstructed the locked package";
    assert lib.assertMsg (
      fallback.drvPath != claudeStatusline.drvPath
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
