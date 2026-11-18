#!/usr/bin/env python3
"""Manage release versions; routine changes increment only the patch component."""
import argparse
import json
import os
from pathlib import Path
import re
import sys
import tempfile

VERSION_FILE = Path(__file__).resolve().parent.parent / "Version.json"
MAX_BUILD = 999_999_999_999_999_999


def validate(version, build):
    if not isinstance(version, str) or not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", version):
        raise ValueError("version must be major.minor.patch without leading zeros")
    if type(build) is not int or not 1 <= build <= MAX_BUILD:
        raise ValueError("build must be a positive integer of at most 18 digits")
    return {"version": version, "build": build}


def read_version(path=VERSION_FILE):
    data = json.loads(path.read_text())
    if not isinstance(data, dict) or set(data) != {"version", "build"}:
        raise ValueError("Version.json must contain exactly version and build")
    return validate(data["version"], data["build"])


def resolve(data, environment):
    version = environment.get("SUPERCLEANER_VERSION", data["version"])
    if version != data["version"]:
        raise ValueError(f"SUPERCLEANER_VERSION must match the resolved release version {data['version']}")
    raw_build = str(environment.get("SUPERCLEANER_BUILD_NUMBER", data["build"]))
    if not re.fullmatch(r"[1-9][0-9]{0,17}", raw_build):
        raise ValueError("invalid SUPERCLEANER_BUILD_NUMBER")
    return validate(version, int(raw_build))


def increment(data, part="patch"):
    if part != "patch":
        raise ValueError("routine changes may only increment patch; explicit releases use next-build --version")
    components = [int(value) for value in data["version"].split(".")]
    components[2] += 1
    return validate(".".join(map(str, components)), data["build"] + 1)


def prepare_build(data, environment, requested_version=None):
    next_version = increment(data)
    if requested_version is not None:
        next_version = validate(requested_version, next_version["build"])
        if tuple(map(int, requested_version.split("."))) <= tuple(map(int, data["version"].split("."))):
            raise ValueError("explicit release version must exceed the previous checked-in version")
    resolved = resolve(next_version, environment)
    if resolved["build"] <= data["build"]:
        raise ValueError("SUPERCLEANER_BUILD_NUMBER must exceed the previous checked-in build")
    return resolved


def save(data, path=VERSION_FILE):
    # Keep the previous source intact if writing or validation fails.
    data = validate(data["version"], data["build"])
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(data, stream, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        temporary.chmod(0o644)
        temporary.replace(path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("show", help="show the checked-in version")
    commands.add_parser("resolve", help="print version and build, including validated CI overrides")
    next_build = commands.add_parser("next-build", help="advance and save version/build for one build invocation; print the resolved values")
    next_build.add_argument("--version", help="explicit release version; must exceed the checked-in version")
    bump = commands.add_parser("bump", help="manually increment patch and build; normal builds already advance automatically")
    bump.add_argument("part", nargs="?", default="patch", choices=("patch",))
    args = parser.parse_args()
    data = read_version()
    if args.command in ("resolve", "next-build"):
        data = prepare_build(data, os.environ, args.version) if args.command == "next-build" else resolve(data, os.environ)
        if args.command == "next-build":
            save(data)
        print(data["version"])
        print(data["build"])
    else:
        if args.command == "bump":
            data = increment(data, args.part)
            save(data)
        print(f'{data["version"]} ({data["build"]})')


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"Version error: {error}", file=sys.stderr)
        sys.exit(1)
