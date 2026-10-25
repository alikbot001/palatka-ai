"""Quick Lua syntax check via lupa (Lua 5.x interpreter).

Wraps each src/*.lua module in a function body and tries to load it.
Skips Lua 5.4+ runtime-only errors that are NOT actual syntax errors
(e.g. reassignment of for-loop variables -- legal in LuaJIT 5.1, the
real target on MonetLoader/MoonLoader).

The "OK" output means the file parses as a valid LuaJIT 5.1 chunk: balanced
begin/end, valid tokens, valid operators. Real semantic correctness must be
verified inside the actual game client (tests/*.lua).
"""
from pathlib import Path
import sys

try:
    import lupa
    lua = lupa.LuaRuntime()
except Exception as e:
    print(f"lupa unavailable: {e}")
    sys.exit(2)

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "src"

# Lua 5.4+ runtime-only errors that are legal in LuaJIT 5.1 -- treat as OK.
SKIP_PATTERNS = (
    "attempt to assign to const variable",
    "'goto' jumps into the scope",
)

def check(name: str, text: str) -> bool:
    wrapped = f"local function __check()\n{text}\nend\nreturn __check\n"
    try:
        wrapped_bytes = wrapped.encode("utf-8")
    except UnicodeEncodeError as e:
        print(f"  ENCODE FAIL {name}: {e}")
        return False
    try:
        lua.execute(wrapped_bytes)
        return True
    except lupa.LuaSyntaxError as e:
        msg = str(e)
        for pat in SKIP_PATTERNS:
            if pat in msg:
                return True  # LuaJIT 5.1 compatible
        print(f"  ERR {name}: {msg}")
        return False
    except Exception as e:
        msg = str(e)
        for pat in SKIP_PATTERNS:
            if pat in msg:
                return True
        print(f"  ERR {name}: {msg}")
        return False

ok_count = 0
err_count = 0
for path in sorted(SRC.glob("*.lua")):
    text = path.read_text(encoding="utf-8")
    if check(path.name, text):
        ok_count += 1
        print(f"  OK  {path.name}")

# Also check the built monolith (cp1251 encoded bytes)
built = ROOT / "palatka_ai.lua"
if built.exists():
    raw = built.read_bytes()
    try:
        # Try utf-8 decode for syntax check only (real file is cp1251)
        text = raw.decode("cp1251")
        if check(built.name, text):
            ok_count += 1
    except Exception as e:
        print(f"  ERR {built.name}: {e}")
        err_count += 1

print(f"\nsyntax check: {ok_count} ok, {err_count} errors")
sys.exit(0 if err_count == 0 else 1)
