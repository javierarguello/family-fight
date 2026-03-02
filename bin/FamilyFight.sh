#!/bin/sh
echo -ne '\033c\033]0;Family Fight\a'
base_path="$(dirname "$(realpath "$0")")"
"$base_path/FamilyFight.arm64" "$@"
