#!/bin/bash

action=$(
  printf 'Leave organizations\nDelete organizations\n' \
    | fzf --prompt="Choose an action > "
)
[ -n "$action" ] || exit 0

username=$(gh api user --jq '.login') || exit 1

if [ "$action" = "Delete organizations" ]; then
  orgs=$(gh api user/memberships/orgs --paginate \
    --jq '.[] | select(.state == "active" and .role == "admin") | .organization.login') || exit 1
  prompt="Tab to select orgs to DELETE > "
  empty_message="No organizations where you are an owner."
else
  orgs=$(gh api user/memberships/orgs --paginate \
    --jq '.[] | select(.state == "active") | .organization.login') || exit 1
  prompt="Tab to select orgs to LEAVE > "
  empty_message="No active organization memberships."
fi

if [ -z "$orgs" ]; then
  echo "$empty_message"
  exit 0
fi

selected_orgs=$(printf '%s\n' "$orgs" | fzf -m --prompt="$prompt")
[ -n "$selected_orgs" ] || exit 0

printf '\nSelected organizations:\n%s\n\n' "$selected_orgs"

if [ "$action" = "Delete organizations" ]; then
  echo "WARNING: Deleting an organization also deletes its repositories and other data."
  read -r -p "Type DELETE to confirm: " confirmation
  [ "$confirmation" = "DELETE" ] || { echo "Cancelled."; exit 0; }

  while IFS= read -r org; do
    [ -n "$org" ] || continue
    if gh api --method DELETE "/orgs/$org"; then
      echo "Deleted $org"
    fi
  done <<< "$selected_orgs"
else
  read -r -p "Type LEAVE to confirm: " confirmation
  [ "$confirmation" = "LEAVE" ] || { echo "Cancelled."; exit 0; }

  while IFS= read -r org; do
    [ -n "$org" ] || continue
    if gh api --method DELETE "/orgs/$org/memberships/$username"; then
      echo "Left $org"
    fi
  done <<< "$selected_orgs"
fi
