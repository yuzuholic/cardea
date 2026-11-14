"""open a mermaid diagram in mermaid.live: python3 open.py [file.mmd] [--no-open]

reads the diagram from the file, or stdin when no file is given, prints the mermaid.live
link and opens it in the default browser. --no-open only prints the link.
"""
import base64
import json
import sys
import webbrowser
import zlib


def link(code):
    # the editor's own "pako" format: json state, zlib level 9, url-safe base64 without padding.
    state = json.dumps({"code": code, "mermaid": json.dumps({"theme": "default"}),
                        "updateDiagram": True, "rough": False})
    packed = base64.urlsafe_b64encode(zlib.compress(state.encode(), 9)).decode().rstrip("=")

    restored = zlib.decompress(base64.urlsafe_b64decode(packed + "=" * (-len(packed) % 4)))
    assert json.loads(restored)["code"] == code, "the link does not decode back to the diagram"

    return f"https://mermaid.live/edit#pako:{packed}"


def main(args):
    files = [a for a in args if a != "--no-open"]
    code = open(files[0], encoding="utf-8").read() if files else sys.stdin.read()
    code = code.strip()

    if code.startswith("```"):
        code = code.split("\n", 1)[1].rsplit("```", 1)[0].strip()

    if not code:
        sys.exit("open.py: no diagram given")

    url = link(code)
    print(url)

    if "--no-open" not in args:
        webbrowser.open(url)


if __name__ == "__main__":
    main(sys.argv[1:])
