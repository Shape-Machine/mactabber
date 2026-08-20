#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
"$repo_dir/scripts/build-app.sh" release
ditto "$repo_dir/dist/MacTabber.app" /Applications/MacTabber.app
open /Applications/MacTabber.app
