#!/bin/bash

set -euo pipefail
export LC_ALL=C

if [ "$#" -ne 6 ]; then
    echo "Usage: $0 <package> <build-suite> <publication-suite> <component> <expected-architecture> <destination>" >&2
    exit 2
fi

package=$1
build_suite=$2
publication_suite=$3
component=$4
expected_architecture=$5
destination=$6

topdir=$(git rev-parse --show-toplevel)
changelog="$topdir/$package/suite/$build_suite/debian/changelog"
builddir="$topdir/build/$build_suite/$package"
source_checkout="$topdir/build/sources/$package"

for command in dpkg-deb dpkg-parsechangelog git gzip python3 tar; do
    if ! command -v "$command" >/dev/null; then
        echo "Required command is unavailable: $command" >&2
        exit 1
    fi
done

if [ ! -f "$changelog" ]; then
    echo "Changelog does not exist: $changelog" >&2
    exit 1
fi
if [ ! -d "$builddir" ]; then
    echo "Build output directory does not exist: $builddir" >&2
    exit 1
fi
if [ ! -d "$source_checkout/.git" ]; then
    echo "Upstream source checkout does not exist: $source_checkout" >&2
    exit 1
fi

source_name=$(dpkg-parsechangelog -l"$changelog" --show-field Source)
version=$(dpkg-parsechangelog -l"$changelog" --show-field Version)
changes="$builddir/${source_name}_${version}_${expected_architecture}.changes"
upstream_commit=$(git -C "$source_checkout" rev-parse --verify HEAD)

# version.sh is the build system's source of truth for the upstream repository.
# shellcheck disable=SC1090
source "$topdir/$package/version.sh"
: "${git_repo:?version.sh must define git_repo}"
upstream_repository=$git_repo

case "$upstream_repository" in
    https://*) ;;
    *)
        echo "Upstream repository must use HTTPS: $upstream_repository" >&2
        exit 1
        ;;
esac

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must identify the producer repository}"
: "${GITHUB_REF:?GITHUB_REF must identify the producer ref}"
: "${GITHUB_SHA:?GITHUB_SHA must identify the producer commit}"
: "${GITHUB_RUN_ID:?GITHUB_RUN_ID must identify the producer run}"
: "${GITHUB_RUN_ATTEMPT:?GITHUB_RUN_ATTEMPT must identify the run attempt}"
: "${CANDIDATE_WORKFLOW:?CANDIDATE_WORKFLOW must identify the workflow file}"

mkdir -p "$destination"
destination=$(cd "$destination" && pwd -P)
staging=$(mktemp -d "$destination/.candidate.XXXXXX")
temporary_bundle=
trap 'rm -rf "$staging"; if [ -n "$temporary_bundle" ]; then rm -f "$temporary_bundle"; fi' EXIT
mkdir "$staging/payload"

python3 - \
    "$changes" \
    "$staging" \
    "$source_name" \
    "$version" \
    "$upstream_repository" \
    "$upstream_commit" \
    "$build_suite" \
    "$publication_suite" \
    "$component" \
    "$expected_architecture" <<'PY'
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


(
    changes_path_text,
    staging_text,
    expected_source,
    expected_version,
    upstream_repository,
    upstream_commit,
    build_suite,
    publication_suite,
    component,
    expected_architecture,
) = sys.argv[1:]

changes_path = Path(changes_path_text)
builddir = changes_path.parent
staging = Path(staging_text)
payload = staging / "payload"


def fail(message: str) -> None:
    raise SystemExit(f"ERROR: {message}")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_deb822(path: Path) -> dict[str, str]:
    fields: dict[str, str] = {}
    current: str | None = None
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as error:
        fail(f"could not read {path}: {error}")
    for line_number, line in enumerate(lines, 1):
        if line.startswith((" ", "\t")):
            if current is None:
                fail(f"{path}:{line_number}: orphan continuation line")
            fields[current] += ("\n" if fields[current] else "") + line[1:]
            continue
        if not line:
            continue
        if ":" not in line:
            fail(f"{path}:{line_number}: invalid Debian control field")
        current, value = line.split(":", 1)
        if current in fields:
            fail(f"{path}:{line_number}: duplicate field {current}")
        fields[current] = value.lstrip()
    return fields


def checksum_records(fields: dict[str, str], path: Path) -> dict[str, tuple[str, int]]:
    value = fields.get("Checksums-Sha256")
    if value is None:
        fail(f"{path}: missing Checksums-Sha256")
    records: dict[str, tuple[str, int]] = {}
    for record in value.splitlines():
        match = re.fullmatch(
            r"([0-9a-f]{64})\s+([0-9]+)\s+([A-Za-z0-9][A-Za-z0-9+._~-]*)",
            record.strip(),
        )
        if match is None:
            fail(f"{path}: malformed Checksums-Sha256 record")
        digest, size_text, name = match.groups()
        if name == path.name:
            fail(f"{path}: Checksums-Sha256 cannot reference the .changes file itself")
        if name.endswith(".changes"):
            fail(f"{path}: referenced nested .changes file {name}")
        if name in records:
            fail(f"{path}: duplicate Checksums-Sha256 file {name}")
        records[name] = (digest, int(size_text))
    if not records:
        fail(f"{path}: empty Checksums-Sha256")
    return records


if not changes_path.is_file() or changes_path.is_symlink():
    fail(f"expected exactly this regular .changes file: {changes_path}")

changes = read_deb822(changes_path)
for field, expected in (("Source", expected_source), ("Version", expected_version)):
    if changes.get(field) != expected:
        fail(f".changes {field} does not match {expected!r}")
distribution = changes.get("Distribution")
if not distribution:
    fail(".changes lacks Distribution")

changes_architectures = set(changes.get("Architecture", "").split())
if expected_architecture not in changes_architectures:
    fail(f".changes does not contain architecture {expected_architecture}")
if not changes_architectures.issubset({"source", "all", expected_architecture}):
    fail(".changes contains an unexpected architecture")

records = checksum_records(changes, changes_path)
suffix_counts = {
    "buildinfo": 0,
    "dsc": 0,
    "orig": 0,
    "debian": 0,
    "deb": 0,
}

payload_sources: list[Path] = [changes_path]
for name, (expected_digest, expected_size) in records.items():
    path = builddir / name
    if not path.is_file() or path.is_symlink():
        fail(f"Checksums-Sha256 file is missing or not regular: {name}")
    if path.stat().st_size != expected_size:
        fail(f"Checksums-Sha256 size mismatch: {name}")
    if sha256(path) != expected_digest:
        fail(f"Checksums-Sha256 digest mismatch: {name}")
    payload_sources.append(path)

    if name.endswith(".buildinfo"):
        suffix_counts["buildinfo"] += 1
    if name.endswith(".dsc"):
        suffix_counts["dsc"] += 1
    if ".orig.tar." in name:
        suffix_counts["orig"] += 1
    if ".debian.tar." in name:
        suffix_counts["debian"] += 1
    if name.endswith(".deb"):
        suffix_counts["deb"] += 1

if suffix_counts["buildinfo"] != 1 or suffix_counts["dsc"] != 1:
    fail("candidate must contain exactly one .buildinfo and one .dsc")
if suffix_counts["orig"] != 1 or suffix_counts["debian"] != 1:
    fail("candidate must contain one orig tarball and one Debian tarball")
if suffix_counts["deb"] < 1:
    fail("candidate must contain at least one binary package")

binary_architectures: set[str] = set()
for path in payload_sources:
    if not path.name.endswith((".deb", ".ddeb", ".udeb")):
        continue
    try:
        architecture = subprocess.check_output(
            ["dpkg-deb", "--field", str(path), "Architecture"],
            text=True,
        ).strip()
    except (OSError, subprocess.CalledProcessError) as error:
        fail(f"could not read binary architecture from {path.name}: {error}")
    if architecture not in {"all", expected_architecture}:
        fail(f"binary {path.name} has unexpected architecture {architecture}")
    binary_architectures.add(architecture)
if expected_architecture not in binary_architectures:
    fail(f"candidate contains no {expected_architecture} binary")

manifest_files: list[dict[str, object]] = []
for source_path in sorted(payload_sources, key=lambda item: item.name):
    target = payload / source_path.name
    shutil.copyfile(source_path, target)
    os.chmod(target, 0o644)
    os.utime(target, (0, 0))
    manifest_files.append(
        {
            "path": f"payload/{target.name}",
            "size": target.stat().st_size,
            "sha256": sha256(target),
        }
    )

manifest = {
    "schema": "ti.debian.candidate/v1",
    "producer": {
        "repository": os.environ["GITHUB_REPOSITORY"],
        "workflow": os.environ["CANDIDATE_WORKFLOW"],
        "ref": os.environ["GITHUB_REF"],
        "commit": os.environ["GITHUB_SHA"],
        "run_id": int(os.environ["GITHUB_RUN_ID"]),
        "run_attempt": int(os.environ["GITHUB_RUN_ATTEMPT"]),
    },
    "source": {
        "name": expected_source,
        "version": expected_version,
        "upstream_repository": upstream_repository,
        "upstream_commit": upstream_commit,
    },
    "build": {
        "suite": build_suite,
        "binary_architectures": sorted(binary_architectures),
        "changes_distribution": distribution,
    },
    "publication": {
        "suites": [publication_suite],
        "component": component,
    },
    "files": manifest_files,
}

if not re.fullmatch(r"[0-9a-f]{40}", manifest["producer"]["commit"]):
    fail("GITHUB_SHA is not a full Git commit")
if not re.fullmatch(r"[0-9a-f]{40}", upstream_commit):
    fail("upstream source HEAD is not a full Git commit")
if manifest["producer"]["run_id"] < 1 or manifest["producer"]["run_attempt"] < 1:
    fail("GitHub run identifiers must be positive integers")

manifest_path = staging / "manifest.json"
manifest_path.write_text(
    json.dumps(manifest, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
os.chmod(manifest_path, 0o644)
os.utime(manifest_path, (0, 0))

checksum_paths = [manifest_path, *sorted(payload.iterdir(), key=lambda item: item.name)]
with (staging / "SHA256SUMS").open("w", encoding="ascii", newline="\n") as stream:
    for path in checksum_paths:
        relative = path.relative_to(staging)
        stream.write(f"{sha256(path)}  {relative.as_posix()}\n")
os.chmod(staging / "SHA256SUMS", 0o644)
os.utime(staging / "SHA256SUMS", (0, 0))
PY

safe_version=$(printf '%s' "$version" | tr -c 'A-Za-z0-9._-' '_')
bundle_name="candidate-${source_name}_${safe_version}_${publication_suite}_${expected_architecture}.tar.gz"
bundle="$destination/$bundle_name"
if [ -e "$bundle" ]; then
    echo "Refusing to overwrite existing candidate: $bundle" >&2
    exit 1
fi
temporary_bundle=$(mktemp "$destination/.candidate-bundle.XXXXXX")

(
    cd "$staging"
    tar \
        --format=gnu \
        --sort=name \
        --mtime='@0' \
        --owner=0 \
        --group=0 \
        --numeric-owner \
        --mode='u+rwX,go+rX,go-w' \
        -cf - \
        manifest.json SHA256SUMS payload |
        gzip -n -9 >"$temporary_bundle"
)
mv "$temporary_bundle" "$bundle"
temporary_bundle=

printf '%s\n' "$bundle"
