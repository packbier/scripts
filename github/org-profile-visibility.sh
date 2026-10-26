#!/bin/bash

action=$(
  printf 'Show organizations on profile\nHide organizations from profile\n' \
    | fzf --prompt="Choose an action > "
)
[ -n "$action" ] || exit 0

username=$(gh api user --jq '.login') || exit 1
public_orgs=$(gh api "users/$username/orgs" --paginate --jq '.[].login') || exit 1

if [ "$action" = "Hide organizations from profile" ]; then
  orgs="$public_orgs"
  prompt="Tab to select orgs to HIDE > "
  empty_message="No public organization memberships to hide."
else
  memberships=$(gh api user/memberships/orgs --paginate \
    --jq '.[] | select(.state == "active") | .organization.login') || exit 1

  orgs=$(
    while IFS= read -r org; do
      [ -n "$org" ] || continue
      if ! printf '%s\n' "$public_orgs" | grep -Fqx -- "$org"; then
        printf '%s\n' "$org"
      fi
    done <<< "$memberships"
  )
  prompt="Tab to select orgs to SHOW > "
  empty_message="No private organization memberships to show."
fi

if [ -z "$orgs" ]; then
  echo "$empty_message"
  exit 0
fi

selected_orgs=$(printf '%s\n' "$orgs" | fzf -m --prompt="$prompt")
[ -n "$selected_orgs" ] || exit 0

while IFS= read -r org; do
  [ -n "$org" ] || continue

  if [ "$action" = "Hide organizations from profile" ]; then
    if gh api --method DELETE --silent "/orgs/$org/public_members/$username"; then
      echo "Hid $org from your profile."
    fi
  else
    if gh api --method PUT --silent "/orgs/$org/public_members/$username"; then
      echo "Showing $org on your profile."
    fi
  fi
done <<< "$selected_orgs"
