---
name: deploy
description: Deploy the homelab to the Odroid. Use when the user asks to "deploy", "push to the device", "update the odroid", "run setup", or similar.
disable-model-invocation: true
allowed-tools: Bash
---

SSH into the Odroid at `root@192.168.0.114` and deploy the latest changes.

## Steps

1. Pull the latest main branch on the device:
   `ssh root@192.168.0.114 "cd /root/homelab && git pull origin main"`

2. Run the setup/deploy script:
   `ssh root@192.168.0.114 "cd /root/homelab && ./setup.sh"`

Report the output of each step. If `git pull` shows "Already up to date", note it but still run setup.sh unless the user says otherwise.

If the repo path on the device is wrong, try `/home` directories or ask the user.
