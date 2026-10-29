#!/usr/bin/env bash
# Fails when any GDScript file produces a warning or error. Usage: tools/lint.sh [godot binary]
# (defaults to $GODOT or "godot"). Run it from the project root before pushing; the web
# workflow runs it on every push.
#
# Godot 4.7 has one level setting per warning (Ignore / Warn / Error). override.cfg is read
# after project.godot, so for this run only every warning the editor shows by default is
# raised to Error, which makes the script fail to compile and the lint script notice it.
# The editor's own settings stay untouched.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${1:-${GODOT:-godot}}"

WARNINGS="unassigned_variable unassigned_variable_op_assign unused_variable unused_local_constant
unused_private_class_variable unused_parameter unused_signal shadowed_variable
shadowed_variable_base_class shadowed_global_identifier unreachable_code unreachable_pattern
standalone_expression standalone_ternary incompatible_ternary unsafe_void_return
static_called_on_instance missing_tool redundant_static_unload redundant_await
assert_always_true assert_always_false integer_division narrowing_conversion
int_as_enum_without_cast int_as_enum_without_match enum_variable_without_default empty_file
deprecated_keyword confusable_identifier confusable_local_declaration confusable_local_usage
confusable_capture_reassignment confusable_temporary_modification inference_on_variant
native_method_override get_node_default_without_onready onready_with_export
property_used_as_function constant_used_as_function function_used_as_property"

cleanup() { rm -f override.cfg; }
trap cleanup EXIT
{
  echo "[debug]"
  echo "gdscript/warnings/enable=true"
  for w in $WARNINGS; do echo "gdscript/warnings/$w=2"; done
} > override.cfg

"$GODOT" --headless --import > /dev/null 2>&1 || true
# The engine prints each warning as "Parse Error: ... (Warning treated as error.)" with file and line.
set +e
OUT=$("$GODOT" --headless -s tools/lint.gd 2>&1)
STATUS=$?
set -e
echo "$OUT" | grep -v -e '^Godot Engine' -e 'GDScript backtrace' -e '^ *\[[0-9]*\] ' -e '^$' || true
# Only a clean run prints the summary line; anything else (including the lint script itself
# failing to compile) is a failure.
if [ "$STATUS" -ne 0 ] || ! grep -q 'scripts clean' <<< "$OUT"; then
  echo "lint: FAILED"
  exit 1
fi
