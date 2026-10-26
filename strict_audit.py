"""Static audit of palatka_ai.lua source.

Parses the built monolith and verifies structural integrity:
  1. Begin() / End() pairs are balanced (every Begin must have a matching End
     -- otherwise the ImGui window stack corrupts and crashes the game).
  2. BeginChild() / EndChild() pairs are balanced.
  3. PushStyleColor() / PopStyleColor() pairs are balanced.
  4. PushStyleVarFloat/Vec2 / PopStyleVar pairs are balanced.
  5. PushItemWidth / PopItemWidth pairs are balanced.

Also extracts:
  - All imgui.* function names used (so we can verify against mimgui 1.8x)
  - All imgui.Col.* enum values used (must match C++ ImGuiCol_ enum)

The audit is intentionally static (regex-based, no Lua execution) so it can
catch bugs that crash the game before any code runs.
"""
import os
import re
import sys
from collections import Counter

ROOT = os.path.dirname(os.path.abspath(__file__))
PALATKA_LUA = os.path.join(ROOT, "palatka_ai.lua")

if not os.path.exists(PALATKA_LUA):
    print(f"ERROR: {PALATKA_LUA} not found. Run `python3 build.py` first.")
    sys.exit(1)

with open(PALATKA_LUA, "rb") as f:
    raw = f.read()
try:
    text = raw.decode("cp1251")
except UnicodeDecodeError as e:
    print(f"ERROR: cannot decode palatka_ai.lua as CP1251: {e}")
    sys.exit(1)

# Strip comments + strings to avoid false positives in pattern matching.
# Lua comment: -- to end of line, or --[[ ... ]] for block comments.
# Lua string: '...' / "..." / [[...]]  (we naively strip line strings)
def strip_lua(text):
    out_lines = []
    in_block = False
    for line in text.split("\n"):
        if in_block:
            if "]]" in line:
                in_block = False
                # cut at ]]
                idx = line.find("]]")
                line = line[idx + 2:]
            else:
                continue
        # Check for block comment start
        if "--[[" in line:
            idx = line.find("--[[")
            before = line[:idx]
            after = line[idx + 4:]
            if "]]" in after:
                idx2 = after.find("]]")
                out_lines.append(before + after[idx2 + 2:])
            else:
                out_lines.append(before)
                in_block = True
            continue
        # Strip line comments
        idx = line.find("--")
        # naive: assume -- not inside string. We just cut at first --
        # but only if not part of a string (we'd need a full lexer).
        # Good enough for our purpose.
        if idx >= 0:
            # Check if -- is inside a string by counting quotes before
            before = line[:idx]
            if before.count('"') % 2 == 0 and before.count("'") % 2 == 0:
                line = before
        out_lines.append(line)
    return "\n".join(out_lines)

clean = strip_lua(text)

issues = []

def count_pattern(pat, text):
    return len(re.findall(pat, text))

def check_balance(open_pat, close_pat, open_name, close_name, text):
    opens = count_pattern(open_pat, text)
    closes = count_pattern(close_pat, text)
    status = "OK" if opens == closes else "IMBALANCE"
    print(f"  {open_name}={opens}  {close_name}={closes}  -> {status}")
    if opens != closes:
        issues.append(f"{open_name}/{close_name} imbalance: {opens} opens vs {closes} closes")
    return opens, closes

print("=" * 70)
print(" STATIC AUDIT OF palatka_ai.lua")
print("=" * 70)
print(f"File size: {len(raw)} bytes")
print(f"Lines: {text.count(chr(10)) + 1}")
print(f"Comments stripped: {len(text) - len(clean)} bytes saved")
print()
print("--- Begin / End balance ---")
check_balance(r"\bimgui\.Begin\s*\(", r"\bimgui\.End\s*\(\s*\)", "Begin", "End", clean)
print()
print("--- BeginChild / EndChild balance ---")
check_balance(r"\bimgui\.BeginChild\s*\(", r"\bimgui\.EndChild\s*\(\s*\)", "BeginChild", "EndChild", clean)
print()
print("--- PushStyleColor / PopStyleColor balance ---")
# Count both pcall-wrapped AND direct calls, then verify total balance.
all_push = len(re.findall(r"\bimgui\.PushStyleColor\s*\(", clean))
all_pop = len(re.findall(r"\bimgui\.PopStyleColor\s*\(", clean))
pcall_push = len(re.findall(r"\bpcall\s*\(\s*imgui\.PushStyleColor", clean))
pcall_pop = len(re.findall(r"\bpcall\s*\(\s*imgui\.PopStyleColor", clean))
print(f"  Total imgui.PushStyleColor: {all_push} (pcall-wrapped: {pcall_push}, direct: {all_push - pcall_push})")
print(f"  Total imgui.PopStyleColor: {all_pop} (pcall-wrapped: {pcall_pop}, direct: {all_pop - pcall_pop})")
if all_push != all_pop:
    print(f"  -> IMBALANCE: {all_push} Push vs {all_pop} Pop = delta {all_push - all_pop}")
    issues.append(f"PushStyleColor/PopStyleColor imbalance: {all_push} Push vs {all_pop} Pop")
else:
    print(f"  -> OK: balanced")
# Also check the push_window helper returns the right count.
print()
# Get the push_window function source to verify pop count matches return value.
m = re.search(r"function\s+DSP\.theme\.push_window\(\)([\s\S]*?)\nend", clean)
if m:
    pw_src = m.group(1)
    pw_pushes = len(re.findall(r"\bpush\s*\(", pw_src))
    pw_return = re.search(r"return\s+(\d+)", pw_src)
    if pw_return:
        ret_n = int(pw_return.group(1))
        print(f"  push_window: pushes {pw_pushes} colors, returns {ret_n} (must match)")
        if pw_pushes != ret_n:
            print(f"  -> IMBALANCE in push_window: {pw_pushes} pushes vs {ret_n} returned")
            issues.append(f"push_window returns {ret_n} but only pushes {pw_pushes} colors")
        else:
            print(f"  -> OK")
m2 = re.search(r"function\s+DSP\.theme\.push_overlay\([^)]*\)([\s\S]*?)\nend", clean)
if m2:
    po_src = m2.group(1)
    po_pushes = len(re.findall(r"\bpcall\s*\(\s*imgui\.PushStyleColor", po_src))
    po_return = re.search(r"return\s+(\d+)", po_src)
    if po_return:
        ret_n = int(po_return.group(1))
        print(f"  push_overlay: pushes {po_pushes} colors, returns {ret_n}")
        if po_pushes != ret_n:
            print(f"  -> IMBALANCE in push_overlay: {po_pushes} pushes vs {ret_n} returned")
            issues.append(f"push_overlay returns {ret_n} but only pushes {po_pushes} colors")
        else:
            print(f"  -> OK")
print()
print("--- PushStyleVarFloat/Vec2 / PopStyleVar balance ---")
check_balance(r"\bimgui\.PushStyleVar(?:Float|Vec2)\s*\(", r"\bimgui\.PopStyleVar\s*\(", "PushStyleVar*", "PopStyleVar", clean)
print()
print("--- PushItemWidth / PopItemWidth balance ---")
check_balance(r"\bimgui\.PushItemWidth\s*\(", r"\bimgui\.PopItemWidth\s*\(", "PushItemWidth", "PopItemWidth", clean)
print()
print("--- imgui.Columns(1) resets / Columns(N) opens ---")
opens_cols = count_pattern(r"\bimgui\.Columns\s*\(\s*\d+\s*,", clean)
closes_cols = count_pattern(r"\bimgui\.Columns\s*\(\s*1\s*,", clean)
print(f"  Columns(N, ...) calls: {opens_cols}  (Columns(1,...) resets: {closes_cols})")
print()
print("--- imgui.* function names used ---")
funcs = sorted(set(re.findall(r"\bimgui\.(\w+)\s*\(", clean)))
print(f"  Total unique functions: {len(funcs)}")
for fn in funcs:
    print(f"    imgui.{fn}")
print()
print("--- imgui.Col.* enum values used ---")
cols = sorted(set(re.findall(r"\bimgui\.Col\.(\w+)", clean)))
print(f"  Total unique Col.*: {len(cols)}")
for c in cols:
    print(f"    imgui.Col.{c}")
print()
print("--- imgui.WindowFlags.* used ---")
wflags = sorted(set(re.findall(r"\bimgui\.WindowFlags\.(\w+)", clean)))
print(f"  Total: {len(wflags)}")
for w in wflags:
    print(f"    imgui.WindowFlags.{w}")
print()
print("--- imgui.StyleVar.* used ---")
svars = sorted(set(re.findall(r"\bimgui\.StyleVar\.(\w+)", clean)))
print(f"  Total: {len(svars)}")
for s in svars:
    print(f"    imgui.StyleVar.{s}")
print()
print("--- imgui.Cond.* used ---")
conds = sorted(set(re.findall(r"\bimgui\.Cond\.(\w+)", clean)))
print(f"  Total: {len(conds)}")
for c in conds:
    print(f"    imgui.Cond.{c}")
print()
print("--- imgui.InputTextFlags.* used ---")
itflags = sorted(set(re.findall(r"\bimgui\.InputTextFlags\.(\w+)", clean)))
print(f"  Total: {len(itflags)}")
for it in itflags:
    print(f"    imgui.InputTextFlags.{it}")
print()
print("--- imgui.SelectableFlags.* used ---")
sflags = sorted(set(re.findall(r"\bimgui\.SelectableFlags\.(\w+)", clean)))
print(f"  Total: {len(sflags)}")
for s in sflags:
    print(f"    imgui.SelectableFlags.{s}")
print()

# Validate Col.* against C++ ImGui 1.8x enum (the canonical list)
VALID_COL_ENUMS = {
    "Text", "TextDisabled", "WindowBg", "ChildBg", "PopupBg", "Border",
    "BorderShadow", "FrameBg", "FrameBgHovered", "FrameBgActive", "TitleBg",
    "TitleBgActive", "TitleBgCollapsed", "MenuBarBg", "ScrollbarBg",
    "ScrollbarGrab", "ScrollbarGrabHovered", "ScrollbarGrabActive",
    "CheckMark", "SliderGrab", "SliderGrabActive", "Button",
    "ButtonHovered", "ButtonActive", "Header", "HeaderHovered",
    "HeaderActive", "Separator", "SeparatorHovered", "SeparatorActive",
    "ResizeGrip", "ResizeGripHovered", "ResizeGripActive", "Tab",
    "TabHovered", "TabActive", "TabUnfocused", "TabUnfocusedActive",
    "PlotLines", "PlotLinesHovered", "PlotHistogram", "PlotHistogramHovered",
    "TableHeaderBg", "TableBorderStrong", "TableBorderLight", "TableRowBg",
    "TableRowBgAlt", "TextSelectedBg", "DragDropTarget", "NavHighlight",
    "NavWindowingHighlight", "NavWindowingDimBg", "ModalWindowDimBg",
}
print("--- imgui.Col.* validation against C++ ImGui 1.8x ---")
for c in cols:
    if c in VALID_COL_ENUMS:
        print(f"  OK    imgui.Col.{c}")
    else:
        print(f"  BAD   imgui.Col.{c}  <- NOT in C++ ImGui enum!")
        issues.append(f"imgui.Col.{c} is not a valid C++ ImGuiCol_ enum value")

# Validate WindowFlags against C++ ImGuiWindowFlags_
VALID_WFLAGS = {
    "NoTitleBar", "NoResize", "NoMove", "NoScrollbar", "NoScrollWithMouse",
    "NoCollapse", "AlwaysAutoResize", "NoBackground", "NoSavedSettings",
    "NoMouseInputs", "MenuBar", "HorizontalScrollbar", "NoFocusOnAppearing",
    "NoBringToFrontOnFocus", "AlwaysVerticalScrollbar",
    "AlwaysHorizontalScrollbar", "AlwaysUseWindowPadding",
    "NoNavInputs", "NoNavFocus", "UnsavedDocument", "NoDocking",
    "NavFlattened", "ChildWindow", "Tooltip", "Popup", "MenuBar",
    "Modal",
}
print("--- imgui.WindowFlags.* validation ---")
for w in wflags:
    if w in VALID_WFLAGS:
        print(f"  OK    imgui.WindowFlags.{w}")
    else:
        print(f"  WARN  imgui.WindowFlags.{w}  <- not in standard enum (may be mimgui extension)")

# Look for Begin/End inside if-blocks without matching End outside
# This is the most common cause of game crashes when the window collapses.
print()
print("--- Begin-End control flow audit (high-risk patterns) ---")
# Find patterns like `if imgui.Begin(...) then ... imgui.End() ... end`
# where End() is INSIDE the if (BAD: must be OUTSIDE).
# Count the lines where this happens.
begin_in_if = re.findall(r"if\s+imgui\.Begin\s*\([^)]*\)\s*then[\s\S]*?imgui\.End\s*\(\s*\)[\s\S]*?end", clean)
print(f"  Begin/End inside if-block (BAD - End won't run if collapsed): {len(begin_in_if)} occurrences")
if begin_in_if:
    for i, snippet in enumerate(begin_in_if[:3]):
        first_line = snippet.split("\n", 1)[0]
        print(f"    [{i+1}] {first_line[:80]}")
    issues.append(f"{len(begin_in_if)} Begin/End pairs inside if-blocks (End skipped on window collapse -> ImGui stack corruption -> SIGSEGV)")

# Look for `imgui.Begin` without a clear End on the same nesting level
print()
print("--- if Begin() then ... end  without matching End  (CRASH) ---")
# This regex matches `if imgui.Begin(...) then` followed by some code and `end`
# but NO `imgui.End()` call inside.
broken = []
for m in re.finditer(r"if\s+imgui\.Begin\s*\(([^)]*)\)\s*then", clean):
    start = m.start()
    # Find the matching 'end' (very naive -- count if/then/end)
    depth = 1
    pos = m.end()
    snippet_end = None
    while pos < len(clean):
        if re.match(r"\bif\b", clean[pos:pos+10]) or re.match(r"\bfor\b", clean[pos:pos+10]) or re.match(r"\bwhile\b", clean[pos:pos+10]) or re.match(r"\bfunction\b", clean[pos:pos+10]) or re.match(r"\bdo\b", clean[pos:pos+10]):
            depth += 1
        elif re.match(r"\bend\b", clean[pos:pos+10]):
            depth -= 1
            if depth == 0:
                snippet_end = pos
                break
        pos += 1
    if snippet_end:
        snippet = clean[start:snippet_end]
        if "imgui.End(" not in snippet:
            broken.append((start, snippet[:120]))

if broken:
    print(f"  Found {len(broken)} Begin blocks WITHOUT End() -- CRITICAL")
    for i, (pos, snip) in enumerate(broken[:5]):
        # Find line number
        line = clean[:pos].count("\n") + 1
        print(f"    [{i+1}] line {line}: {snip[:80]!r}")
    issues.append(f"{len(broken)} Begin() blocks missing End() call -- ImGui stack corruption -> GAME CRASH")
else:
    print("  OK: All Begin() blocks have matching End() calls")

print()
print("=" * 70)
if issues:
    print(f" AUDIT FOUND {len(issues)} ISSUES:")
    print("=" * 70)
    for i, issue in enumerate(issues, 1):
        print(f"  [{i}] {issue}")
    sys.exit(1)
else:
    print(" AUDIT PASSED -- no structural issues found")
    print("=" * 70)
sys.exit(0)
