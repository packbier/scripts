# scripts

A collection of lightweight shell utilities for me.

---

## Requirements

Ensure you have the following installed:

- [GitHub CLI (`gh`)](https://cli.github.com/)
- [fzf](https://github.com/junegunn/fzf)
- [`jq`](https://jqlang.github.io/jq/)

### Setup & Authentication for /github

Authenticate with the GitHub CLI:

```bash
gh auth login
```

If you plan to delete repositories, grant the deletion scope:

```bash
gh auth refresh -h github.com -s delete_repo
```

If you plan to delete organizations, grant the organization administration scope:

```bash
gh auth refresh -h github.com -s admin:org
```

---

## Usage

### /github

| Script | Description |
| --- | --- |
| `bulk-private-repos.sh` | Pick public repos with `fzf`, set them to private. |
| `bulk-delete-repos.sh` | Pick repos with `fzf`, delete them. |
| `leave-delete-orgs.sh` | Leave organizations, or delete organizations you own. |
| `org-profile-visibility.sh` | Show or hide organization memberships on your profile. |

### /misc

| Script | Description |
| --- | --- |
| `kill-port.sh [port]` | Show what is listening on a TCP port and kill it (SIGTERM, then SIGKILL). Prompts for the port if omitted. |
| `garbage.sh` | Next New Taipei City trash truck time for an address, with a live ETA when the truck is out on the route. `--full` prints the weekly table, `--address` queries a different address. |

#### Setup for `garbage.sh`

Your address is read from `~/.config/ntpc-trash/address` so it never lands in
this repo:

```bash
mkdir -p ~/.config/ntpc-trash
printf '%s\n' 'YOUR_ADDRESS' > ~/.config/ntpc-trash/address
chmod 600 ~/.config/ntpc-trash/address
```

The route dataset (~27k stops) is cached in `~/.cache/ntpc-trash/routes.json`
and refreshed weekly; `--refresh` forces a re-download. Data comes from the
New Taipei City open data platform (`data.ntpc.gov.tw`).

---

## Making commands available

Your `~/.zshrc` already sources every `~/.config/zsh/*.zsh` file, so drop a module there
instead of editing `.zshrc`:

```bash
mkdir -p ~/.config/zsh
cat > ~/.config/zsh/40-scripts.zsh <<'EOF'
export SCRIPTS="$HOME/Projects/scripts"

# One alias per script, named after the file without .sh.
for script in "$SCRIPTS"/{github,git,misc}/*.sh(N); do
  alias "${script:t:r}"="$script"
  # Tab-complete the script's arguments from its own directory.
  compdef "_files -W ${script:h}" "${script:t:r}"
done
EOF
```

Then `exec zsh` (or open a new terminal). `kill-port 3000` now runs
`~/Projects/scripts/misc/kill-port.sh 3000`.

Notes:

- The `(N)` glob qualifier makes the loop a no-op when a directory is empty.
- Aliases are expanded at parse time, so they only work in interactive shells —
  fine for personal use, but use `$SCRIPTS/...` inside other scripts.
- If you'd rather have real commands (usable from scripts, `xargs`, etc.), replace
  the `alias` line with `export PATH="$SCRIPTS/github:$SCRIPTS/git:$SCRIPTS/misc:$PATH"`
  and drop the `.sh` suffixes from the filenames.
