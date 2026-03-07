#!/usr/bin/env bash

# Helper script to get all the git submodule update stuff done, after cloning, updating your main repo.
# For convenience it also contains similar git lfs update logic.

set -x

git submodule update --init --recursive --recommend-shallow

set -e

# Ensure we're inside a git repository
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Check if repository uses Git LFS
if ! git grep -q "filter=lfs" -- '**/.gitattributes' 2>/dev/null; then
    exit 0
fi

echo "Git LFS required by repository."

# Install git-lfs if not present
if ! command -v git-lfs >/dev/null 2>&1; then
    echo "git-lfs not found. Installing..."

    case "$(uname -s)" in
        Linux)
            sudo apt-get update -qq
            sudo apt-get install -y git-lfs
            ;;
        Darwin)
            if ! command -v brew >/dev/null 2>&1; then
                echo "Homebrew not found. Please install Homebrew first."
                exit 1
            fi
            brew install git-lfs
            ;;
        *)
            echo "Unsupported OS."
            exit 1
            ;;
    esac
fi

# Initialize LFS
git lfs install

git lfs pull
