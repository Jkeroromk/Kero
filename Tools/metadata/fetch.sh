#!/usr/bin/env bash
# Fetches the inputs for build_gamedb.py into a scratch folder, then builds Kero/Resources/GameDB.
# Usage: Tools/metadata/fetch.sh [workdir]
set -euo pipefail
WORK="${1:-$(mktemp -d)}"
cd "$WORK"
git clone -q --depth 1 --filter=blob:none --sparse https://github.com/libretro/libretro-database.git
(cd libretro-database && git sparse-checkout set --no-cone '/metadat/no-intro/Nintendo - Game Boy*' '/metadat/no-intro/Nintendo - Nintendo DS.dat')
for repo in Nintendo_-_Game_Boy_Advance Nintendo_-_Game_Boy_Color Nintendo_-_Game_Boy Nintendo_-_Nintendo_DS; do
  git clone -q --depth 1 --filter=blob:none --no-checkout "https://github.com/libretro-thumbnails/$repo.git" "thumbs-$repo"
  (cd "thumbs-$repo" && git ls-tree -r --name-only HEAD | grep '^Named_Boxarts/' > "../boxarts-$repo.txt")
done
cd - >/dev/null
python3 "$(dirname "$0")/build_gamedb.py" "$WORK/libretro-database/metadat/no-intro" "$WORK"
grep -v '^#' "$(dirname "$0")/names-zh.tsv" > "$(dirname "$0")/../../Kero/Resources/GameDB/names-zh.tsv"
grep -v '^#' "$(dirname "$0")/header-titles.tsv" > "$(dirname "$0")/../../Kero/Resources/GameDB/header-titles.tsv"
