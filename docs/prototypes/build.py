"""Build the prototypes in src/ into standalone HTML pages next to this file.

Each src/<name>.src.html is the body of an Amp view: it expects Amp's colour tokens
and ui-* classes. The build inlines its fonts and includes, then puts
src/standalone-head.html (a small stand-in for that kit) in front, so the page opens
in any browser with no server.

    python3 docs/prototypes/build.py                    # build every prototype
    python3 docs/prototypes/build.py 05-animations      # build one
    python3 docs/prototypes/build.py --amp-views out/   # also write the bare Amp view pages

In a source file, {{FONT_NAME}} becomes src/fonts/name.woff2 as base64 and
{{INCLUDE:file}} becomes the text of src/file.
"""
import argparse
import base64
import pathlib
import re

HERE = pathlib.Path(__file__).resolve().parent
SRC = HERE / "src"


def body(name: str) -> str:
    text = (SRC / f"{name}.src.html").read_text()
    text = re.sub(r"[ \t]*\{\{INCLUDE:([\w.-]+)\}\}\n", lambda m: (SRC / m.group(1)).read_text(), text)
    text = re.sub(
        r"\{\{FONT_(\w+)\}\}",
        lambda m: base64.b64encode((SRC / "fonts" / f"{m.group(1).lower()}.woff2").read_bytes()).decode(),
        text,
    )
    if "{{" in text:
        raise SystemExit(f"{name}: unresolved placeholder")
    return text


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("names", nargs="*", help="prototypes to build; default is all of them")
    parser.add_argument("--amp-views", type=pathlib.Path, help="directory for the bare Amp view pages")
    args = parser.parse_args()
    names = args.names or sorted(p.name.removesuffix(".src.html") for p in SRC.glob("*.src.html"))
    head = (SRC / "standalone-head.html").read_text()
    for name in names:
        text = body(name)
        label = "Feed the Goose prototype: " + name.split("-", 1)[1].replace("-", " ")
        (HERE / f"{name}.html").write_text(head.replace("{{TITLE}}", label) + text)
        if args.amp_views:
            args.amp_views.mkdir(parents=True, exist_ok=True)
            (args.amp_views / f"{name}.html").write_text(text)
        print(f"{name}.html  {len(text.encode()) // 1024} KB")


if __name__ == "__main__":
    main()
