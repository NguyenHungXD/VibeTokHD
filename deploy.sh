#!/bin/bash
# deploy.sh - Deploy repo lên GitHub
# Usage: ./deploy.sh YOUR_GITHUB_TOKEN YOUR_USERNAME
set -e

TOKEN=$1
USER=$2

if [ -z "$TOKEN" ] || [ -z "$USER" ]; then
  echo "Usage: ./deploy.sh YOUR_GITHUB_TOKEN YOUR_USERNAME"
  exit 1
fi

# Create repo via API
echo "Creating GitHub repo..."
curl -X POST -H "Authorization: token $TOKEN" \
     -H "Accept: application/vnd.github+json" \
     https://api.github.com/user/repos \
     -d "{\"name\":\"VibeTokHD\",\"description\":\"Patched VibeTok - HD Photos\",\"private\":false}"

# Add remote
git remote add origin https://$TOKEN@github.com/$USER/VibeTokHD.git

# Push
git add -A
git commit -m "Initial: VibeTokHD with originPhotoURL patch"
git push -u origin main || git push -u origin master
