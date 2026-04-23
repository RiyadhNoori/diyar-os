#!/bin/bash
set -e
echo "[DIYAR] معالجة أيقونات وخلفيات ديار..."
apt-get install -y --no-install-recommends imagemagick 2>/dev/null || true
cd /opt/diyar-branding
bash scripts/build-icons.sh
bash output/install.sh
echo "[DIYAR] الهوية البصرية مثبّتة ✅"
