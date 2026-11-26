#!/usr/bin/env bash
# Checks every addon script with strict typing warnings turned into errors
# (untyped declarations, unsafe property / method access, unsafe casts and
# call arguments). Run from the project folder:
#   GODOT=/path/to/godot test/strict_check.sh
# project.godot is changed for the run and restored afterwards.
set -u
GODOT="${GODOT:-godot}"
cp project.godot project.godot.strict-backup
trap 'mv -f project.godot.strict-backup project.godot' EXIT
cat >> project.godot <<'CFG'

[debug]

gdscript/warnings/exclude_addons=false
gdscript/warnings/untyped_declaration=2
gdscript/warnings/unsafe_property_access=2
gdscript/warnings/unsafe_method_access=2
gdscript/warnings/unsafe_cast=2
gdscript/warnings/unsafe_call_argument=2
CFG
"$GODOT" --headless --path . --import >/dev/null 2>&1
status=0
for f in $(find addons/godoombuilder -name '*.gd' | sort); do
  # Each problem is a "SCRIPT ERROR: ..." line followed by "at: ... (res://file:line)";
  # keep the ones in this file (problems in scripts it uses show up there).
  out=$("$GODOT" --headless --path . --check-only --script "res://$f" 2>&1 | tr -d '' | awk -v want="res://$f:" '
    /SCRIPT ERROR:/ { msg = $0; sub(/^.*Parse Error: /, "", msg); sub(/ \(Warning treated as error.\)/, "", msg); next }
    /at: / && msg != "" { if (index($0, want)) { loc = $0; sub(/^.*res:\/\//, "", loc); sub(/\).*$/, "", loc); print "  " loc ": " msg } msg = "" }
  ')
  if [ -n "$out" ]; then
    echo "== $f"
    echo "$out"
    status=1
  fi
done
[ $status -eq 0 ] && echo "STRICT: OK" || echo "STRICT: FAILED"
exit $status
