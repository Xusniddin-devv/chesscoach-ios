"""Builds Packages/ChessCore/Sources/ChessCore/Resources/lessons.json from the web app's
lesson data (src/lib/openings.ts, endgames.ts, checkmates.ts of xq-chesscoach).

Usage: python3 -I scripts/gen-lessons.py <dir with the three .ts files> > lessons.json
The TS files are plain object literals with double-quoted strings, so a small regex
reader is enough; ChessCore's LessonsTests check every FEN and move afterwards.
"""
import json
import re
import sys

src = sys.argv[1]
FIELD = re.compile(r'(\w+):\s*"((?:[^"\\]|\\.)*)"')


def objects(text, array_name):
    """Top-level objects of `export const <array_name> = [ ... ];`."""
    body = text[text.index(array_name):]
    body = body[body.index("= [") + 3:]
    depth, start, out = 0, None, []
    for i, ch in enumerate(body):
        if ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                out.append(body[start:i + 1])
        elif ch == "]" and depth == 0:
            break
    return out


def fields(obj):
    # Fields of the object itself, before any nested array.
    head = obj.split("line:")[0]
    return {k: v for k, v in FIELD.findall(head)}


def read(name):
    with open(f"{src}/{name}", encoding="utf-8") as f:
        return f.read()


START = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
lessons = []

for obj in objects(read("openings.ts"), "REPERTOIRES"):
    f = fields(obj)
    line = obj[obj.index("line:"):]
    steps = [{"san": s, "note": n} for s, n in re.findall(r'\{\s*san:\s*"([^"]*)",\s*note:\s*"([^"]*)"\s*\}', line)]
    lessons.append({"id": f"opening-{f['id']}", "track": "openings", "title": f["name"],
                    "summary": f["description"], "startFen": START, "userColor": f["userColor"],
                    "goal": "line", "steps": steps})

for obj in objects(read("endgames.ts"), "ENDGAME_DRILLS"):
    f = fields(obj)
    lessons.append({"id": f"endgame-{f['id']}", "track": "endgames", "title": f["name"],
                    "summary": f["tip"], "startFen": f["fen"], "userColor": f["userColor"],
                    "goal": f["goal"], "steps": []})

for obj in objects(read("checkmates.ts"), "CHECKMATES"):
    f = fields(obj)
    lessons.append({"id": f"mate-{f['id']}", "track": "checkmates", "title": f["name"],
                    "summary": f["description"], "startFen": f["fen"], "userColor": "w",
                    "goal": "mate", "steps": [{"uci": f["solution"], "note": f["description"]}]})

json.dump(lessons, sys.stdout, ensure_ascii=False, indent=1)
sys.stdout.write("\n")
print(f"{len(lessons)} lessons", file=sys.stderr)
