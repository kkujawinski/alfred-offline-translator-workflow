#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Function to show usage
usage() {
  echo "Usage: $0 [--list] [--cleanup] [major.minor]"
  echo
  echo "  --list          List unique major.minor versions from git tags."
  echo "  --cleanup       Remove old tags, keeping only the latest patch for each major.minor version."
  echo "  major.minor     Create and push a new patch tag for the given major.minor version."
  exit 1
}

# Check for --list argument
if [ "$1" == "--list" ]; then
  git tag | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sed -E 's/v([0-9]+\.[0-9]+)\.[0-9]+/\1/' | sort -u
  exit 0
fi

# Check for --remove-old argument
if [ "$1" == "--cleanup" ]; then
  # Get unique major.minor versions from git tags that match the vX.Y.Z format
  UNIQUE_MAJOR_MINOR=$(git tag | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sed -E 's/v([0-9]+\.[0-9]+)\.[0-9]+/\1/' | sort -u)

  if [ -z "$UNIQUE_MAJOR_MINOR" ]; then
    echo "No tags in vX.Y.Z format found to process."
    exit 0
  fi

  for major_minor in $UNIQUE_MAJOR_MINOR; do
    major_minor_escaped=$(echo "$major_minor" | sed 's/\./\\./')
    # Get the latest patch number for the given major.minor version
    latest_patch=$(git tag --list "v${major_minor}.*" | sed -E "s/^v${major_minor_escaped}\.//" | sort -n | tail -n 1)

    if [ -z "$latest_patch" ]; then
      # This should not happen if major_minor came from existing tags, but as a safeguard:
      echo "Could not find latest patch for ${major_minor}. Skipping."
      continue
    fi

    latest_tag="v${major_minor}.${latest_patch}"

    # Get all tags for this major.minor version
    all_tags=$(git tag --list "v${major_minor}.*")

    # Identify tags to remove (all except the latest one)
    # Use || true to prevent exit when grep finds no matches (only one tag exists)
    tags_to_remove=$(echo "$all_tags" | grep -v "^${latest_tag}$" || true)

    if [ -n "$tags_to_remove" ]; then
      echo "For version ${major_minor}, latest is ${latest_tag}. Removing old tags:"
      echo "$tags_to_remove"

      # Remove local tags
      echo "$tags_to_remove" | xargs git tag -d

      # Remove remote tags
      echo "$tags_to_remove" | xargs git push origin --delete

      echo "Removed old tags for ${major_minor}."
    else
      echo "For version ${major_minor}, only one tag (${latest_tag}) exists or no old tags found. Nothing to remove."
    fi
  done
  exit 0
fi

# Check for major.minor argument
if [ -z "$1" ]; then
  usage
fi

VERSION_PREFIX="$1"
if ! [[ "$VERSION_PREFIX" =~ ^[0-9]+\.[0-9]+$ ]]; then
  echo "Error: Invalid major.minor format."
  usage
fi

# Escape dot in version prefix for sed
VERSION_PREFIX_ESCAPED=$(echo "$VERSION_PREFIX" | sed 's/\./\\./')

# Get the latest patch number for the given major.minor version
LATEST_PATCH=$(git tag --list "v${VERSION_PREFIX}.*" | sed -E "s/v${VERSION_PREFIX_ESCAPED}\.//" | sort -n | tail -n 1)

if [ -z "$LATEST_PATCH" ]; then
  NEW_PATCH=0
else
  NEW_PATCH=$((LATEST_PATCH + 1))
fi

NEW_TAG="v${VERSION_PREFIX}.${NEW_PATCH}"

echo "Creating and pushing new tag: $NEW_TAG"

# Create the new tag
git tag "$NEW_TAG"

# Push the new tag to the remote repository
git push origin "$NEW_TAG"

echo "Tag $NEW_TAG created and pushed successfully."
