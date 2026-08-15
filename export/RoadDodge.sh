#!/bin/sh
echo -ne '\033c\033]0;Road Dodge\a'
base_path="$(dirname "$(realpath "$0")")"
"$base_path/RoadDodge.x86_64" "$@"
