#!/bin/bash

gh repo list --limit 200 --json name -q '.[].name' \
  | fzf -m --prompt="Tab to select repos to DELETE > " \
  | while read -r repo; do
      gh repo delete "$repo" --yes
      echo "Deleted $repo"
    done
