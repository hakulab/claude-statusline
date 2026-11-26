# ==================================================================================================
# claude-statusline Home Manager Module
# ==================================================================================================

{
  packageFor,
}:

{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.programs.claude-statusline;
  toml = pkgs.formats.toml { };
in
{
  # ------------------------------------------------------------------------------------------------
  # Module Options
  # ------------------------------------------------------------------------------------------------
  options.programs.claude-statusline = {
    enable = lib.mkEnableOption "claude-statusline";

    package = lib.mkOption {
      type = lib.types.package;
      default = packageFor pkgs;
      defaultText = lib.literalMD "claude-statusline from this flake";
      description = "Package that provides the `claude-statusline` command.";
    };

    settings = lib.mkOption {
      inherit (toml) type;
      default = { };
      description = "Configuration written to `claude-statusline/config.toml` under XDG config.";
    };
  };

  # ------------------------------------------------------------------------------------------------
  # Module Config
  # ------------------------------------------------------------------------------------------------
  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    xdg.configFile."claude-statusline/config.toml" = lib.mkIf (cfg.settings != { }) {
      source = toml.generate "claude-statusline-config.toml" cfg.settings;
    };
  };
}
