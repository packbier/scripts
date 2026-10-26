#!/bin/bash

gh repo list --visibility public --limit 200 --json name -q '.[].name' \
  | fzf -m --prompt="Tab to select repos to make private > " \
  | while read -r repo; do
      gh repo edit "$repo" --visibility private
      echo "set $repo to private."
    done
