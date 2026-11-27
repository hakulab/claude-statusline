# AGENTS.md: claude-statusline

`claude-statusline` is a modular, non-blocking Nushell status line renderer for Claude Code with stale-while-revalidate caching and pluggable local and remote cost providers.

## Read before you edit

| When the change touches | Read                                                                      |
| ----------------------- | ------------------------------------------------------------------------- |
| CI or a workflow        | [devkit's CI guide](https://github.com/hakulab/devkit/blob/v3/docs/ci.md) |
| A release               | [RELEASING.md](RELEASING.md)                                              |

## Code

Wrap code and comments at 100 columns, counting the indent.

Keep the entry point at `src/claude-statusline.nu` so `dk.mkNuApplication` installs `bin/claude-statusline`. Keep imports unidirectional (`src/claude-statusline.nu` → domain modules → shared helpers).

## Verification

In each new checkout or worktree, run `nix develop -c true` once to install the pre-commit hooks and link their config, and never bypass them with `--no-verify` or `PREK_ALLOW_NO_CONFIG`.

```bash
nix flake check --all-systems
nix develop -c run-hooks
```
