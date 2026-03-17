# mise-volta-compat

Migrate [Volta](https://volta.sh) tool pins in `package.json` to [mise](https://mise.jdx.dev) `.mise.toml` format.

## Install

Add to your global mise config (`~/.config/mise/config.toml`):

```toml
[settings]
auto_install = true
experimental = true  # required for hooks

[tools]
jq = "latest"
"github:BD-Builder-Designs/mise-volta-compat" = "latest"

[hooks]
enter = "mise-volta-compat check"
```

Then run:

```bash
mise install
```

## Usage

### Automatic detection

When you `cd` into a project with Volta config but no `.mise.toml`, you'll see:

```
⚡ This project uses Volta config. Run 'mise-volta-compat migrate' to convert to .mise.toml
```

### Migrate a project

```bash
mise-volta-compat migrate
```

This will:
1. Read `volta` pins from `package.json`
2. Create `.mise.toml` with equivalent `[tools]` entries

The volta config in `package.json` is left intact so other developers using Volta are unaffected.

Review the changes, then commit:

```bash
git add .mise.toml && git commit -m 'chore: add mise config from volta pins'
```

### Batch migration

````bash
for repo in repos/*/; do
  (
    cd "$repo"
    mise-volta-compat migrate
    if [[ -f .mise.toml ]]; then
      git checkout -b chore/migrate-volta-to-mise
      git add .mise.toml
      git commit -m "chore: add mise config from volta pins"
      git push origin HEAD
    fi
  )
done
````

## Supported Volta keys

| Volta key | mise tool |
|-----------|-----------|
| `node`    | `node`    |
| `npm`     | `npm`     |
| `yarn`    | `yarn`    |
| `pnpm`    | `pnpm`    |

Unrecognized keys are written as-is with a warning.

## Requirements

- `jq` (installed automatically when using the mise config above)
- `bash`

## Limitations

- The `enter` hook requires `experimental = true` in mise settings (hooks are an experimental mise feature)
- Volta's `extends` feature is not followed
- After migration, use `mise use node@22` instead of `volta pin`

## License

MIT
