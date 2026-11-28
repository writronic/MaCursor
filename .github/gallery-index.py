import argparse
import hashlib
import json
import pathlib
import plistlib
import re
import sys

SAFE_NAME = re.compile(r"^[A-Za-z0-9._-]+$")


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("themes")
    parser.add_argument("pictures")
    parser.add_argument("--file-prefix", default="")
    parser.add_argument("--picture-prefix", default="")
    args = parser.parse_args()

    folder = pathlib.Path(args.themes)
    pictures = pathlib.Path(args.pictures)
    entries = []
    for path in sorted(folder.glob("*.cursor")):
        identifier = path.stem
        picture = pictures / f"{identifier}.png"
        if not SAFE_NAME.match(path.name):
            sys.exit(f"unsafe file name: {path.name}")
        if not picture.is_file():
            sys.exit(f"missing picture: {picture}")
        with path.open("rb") as handle:
            theme = plistlib.load(handle)
        entries.append({
            "identifier": identifier,
            "name": theme.get("ThemeName") or identifier,
            "creator": theme.get("Creator") or "",
            "file": args.file_prefix + path.name,
            "picture": args.picture_prefix + picture.name,
            "sha256": sha256(path),
            "size": path.stat().st_size,
            "pictureSha256": sha256(picture),
        })

    entries.sort(key=lambda entry: (entry["name"].casefold(), entry["identifier"]))
    json.dump({"themes": entries}, sys.stdout, ensure_ascii=False, indent=2, sort_keys=True)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
