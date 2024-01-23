#!/bin/bash

cfs_apps=("$@") # This will create an array from the arguments

# Name of the remote to add
remote_name="nasa"
remote_url="https://github.com/nasa/cFS.git"

# Store the current directory as the root directory
export ROOT_DIR=$(pwd)

# Check if the remote already exists
if git remote | grep -qx "$remote_name"; then
    echo "Remote '$remote_name' already exists. Skipping addition."
else
    # Add the remote since it doesn't exist
    git remote add "$remote_name" "$remote_url"
    echo "Remote '$remote_name' added."
fi

# update parent module
git fetch nasa
git merge nasa/main
git rebase nasa/main

# update submodules
git submodule update --init --recursive

for app in "${cfs_apps[@]}"; do
    cd "${app}"
    git fetch
    git checkout main
    git pull
    cd "$ROOT_DIR"
done

# Check if there are any changes
if [ -n "$(git status --porcelain)" ]; then
    # Add all changes
    git add .

    # Commit the changes
    git commit -m "Updating submodule references"

    # Push the changes
    git push
fi
