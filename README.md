# scripts

A collection of lightweight shell utilities for me.

---

## Requirements

Ensure you have the following installed:

- [GitHub CLI (`gh`)](https://cli.github.com/)
- [fzf](https://github.com/junegunn/fzf)

### Setup & Authentication for /github

Authenticate with the GitHub CLI:

```bash
gh auth login
```

If you plan to delete repositories, grant the deletion scope:

```bash
gh auth refresh -h github.com -s delete_repo
```
