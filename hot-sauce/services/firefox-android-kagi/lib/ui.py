"""Locate widgets in Firefox for Android over adb, by id or text rather than by
hardcoded pixel coordinates.

Coordinates shift with screen size, font scale, and every Fenix release, so a
script built on them silently mistaps instead of failing. Everything here
resolves a selector against a live uiautomator dump and exits non-zero when the
element is absent, which turns a layout change into a loud error.

Subcommands:
  find  --id ID | --text TEXT [--row-of-text T] [--nth N]   -> "x y"
  text  --id ID                                             -> field contents
  wait  --id ID | --text TEXT [--timeout S]                 -> "x y"
  dump                                                      -> redacted tree
"""
import argparse
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

# A Kagi session token is ~87 chars of token-ish text. Anything that long gets
# masked so debugging output can be pasted around without leaking the session.
TOKENISH = re.compile(r"[A-Za-z0-9_.\-]{24,}")


def dump_xml():
    subprocess.run(["adb", "shell", "uiautomator", "dump", "/sdcard/ui.xml"],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    out = subprocess.run(["adb", "shell", "cat", "/sdcard/ui.xml"],
                         check=True, capture_output=True, text=True).stdout
    start = out.find("<?xml")
    if start == -1:
        raise SystemExit("uiautomator returned no XML; is the screen on and unlocked?")
    return ET.fromstring(out[start:])


def centre(node):
    nums = [int(n) for n in re.findall(r"-?\d+", node.get("bounds", "0,0,0,0"))]
    return (nums[0] + nums[2]) // 2, (nums[1] + nums[3]) // 2


def matches(node, args):
    if args.id and not node.get("resource-id", "").endswith("/" + args.id):
        return False
    if args.text and node.get("text", "") != args.text:
        return False
    if args.contains and args.contains not in (node.get("text", "") + node.get("content-desc", "")):
        return False
    return True


def select(root, args):
    hits = [n for n in root.iter("node") if matches(n, args)]

    # Disambiguate repeated ids (e.g. the overflow button on every engine row) by
    # pinning to the row that carries a given label.
    if args.row_of_text:
        anchors = [n for n in root.iter("node") if n.get("text", "") == args.row_of_text]
        if not anchors:
            raise SystemExit(f"no row labelled {args.row_of_text!r}")
        _, anchor_y = centre(anchors[0])
        hits = [n for n in hits if abs(centre(n)[1] - anchor_y) <= 40]

    if len(hits) <= args.nth:
        raise SystemExit(
            f"no match for {args.id or args.text or args.contains!r} (nth={args.nth})")
    return hits[args.nth]


def redact(s):
    return TOKENISH.sub(lambda m: f"<REDACTED:{len(m.group(0))}>", s)


parser = argparse.ArgumentParser()
sub = parser.add_subparsers(dest="cmd", required=True)
for name in ("find", "text", "wait"):
    p = sub.add_parser(name)
    p.add_argument("--id")
    p.add_argument("--text")
    p.add_argument("--contains")
    p.add_argument("--row-of-text")
    p.add_argument("--nth", type=int, default=0)
    p.add_argument("--timeout", type=float, default=10.0)
sub.add_parser("dump")
args = parser.parse_args()

if args.cmd == "dump":
    for n in dump_xml().iter("node"):
        label = n.get("text") or n.get("content-desc") or n.get("resource-id")
        if not label:
            continue
        x, y = centre(n)
        print(redact(f"{x:5},{y:5}  {n.get('resource-id', '').split('/')[-1]:30} "
                     f"{n.get('text', '')!r} {n.get('content-desc', '')!r}"))
    sys.exit(0)

if not (args.id or args.text or args.contains):
    raise SystemExit("need --id, --text or --contains")

deadline = time.time() + (args.timeout if args.cmd == "wait" else 0)
while True:
    try:
        node = select(dump_xml(), args)
        break
    except SystemExit:
        if time.time() >= deadline:
            raise
        time.sleep(0.5)

if args.cmd == "text":
    print(node.get("text", ""))
else:
    print("%d %d" % centre(node))
