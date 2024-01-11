#!/bin/bash

# Name of the remote to add
remote_name="nasa"
remote_url="https://github.com/nasa/cFS.git"

# Check if the remote already exists
if git remote | grep -qx "$remote_name"; then
    echo "Remote '$remote_name' already exists. Skipping addition."
else
    # Add the remote since it doesn't exist
    git remote add "$remote_name" "$remote_url"
    echo "Remote '$remote_name' added."
fi

git fetch nasa
git merge nasa/main
git rebase nasa/main