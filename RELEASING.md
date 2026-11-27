# Releasing

Use the [release skill](https://github.com/hakulab/plugins/blob/main/plugins/hakula-workflow/skills/release/SKILL.md) with the contract below.

## Versioning

- **Before 1.0**: tag `v0.N.0` whenever a user-visible batch lands, and `v0.N.M` for a fix to shipped behavior. A change to the [stability surface](#stability-surface) bumps the minor version and is listed under Breaking changes.
- **After 1.0**: a breaking change to the stability surface bumps the major version, a user-visible addition or change bumps the minor version, and a fix bumps the patch version.

### Stability surface

Within a minor version, stable releases keep these compatible:

- CLI flags (`--config`, `--cache-dir`, `--refresh`, `--sync-refresh`), `NO_COLOR`, and exit codes
- TOML configuration schema (`[defaults]`, `[layout]`, `[theme]`, `[local]`, `[models]`, `[[cost_sources]]`)
- The flake's `packages`, `overlays.default`, and `homeModules.default` outputs, and `programs.claude-statusline` options

## Preparation and verification

Update `version` in `flake.nix` and the release entry in `CHANGELOG.md`, then run:

```bash
nix flake check --all-systems
nix develop -c run-hooks
```

After publication, verify that `nix run github:hakulab/claude-statusline/vX.Y.Z -- --help` starts and prints its usage.
