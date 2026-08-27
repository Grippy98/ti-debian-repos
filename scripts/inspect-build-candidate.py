#!/usr/bin/env python3

"""Safely inspect a transferred candidate before granting it provenance."""

from __future__ import annotations

import hashlib
import json
import os
import re
import sys
import tarfile
from pathlib import Path, PurePosixPath
from typing import Any


MAX_BUNDLE_BYTES = 2 * 1024 * 1024 * 1024
MAX_EXPANDED_BYTES = 2 * 1024 * 1024 * 1024
MAX_MANIFEST_BYTES = 1024 * 1024
MAX_MEMBERS = 256


class CandidateError(ValueError):
    pass


def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise CandidateError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_name(name: str) -> bool:
    path = PurePosixPath(name)
    return (
        bool(name)
        and not path.is_absolute()
        and name == str(path)
        and all(part not in {"", ".", ".."} for part in path.parts)
    )


def string(value: Any, pattern: str, context: str) -> str:
    if not isinstance(value, str) or re.fullmatch(pattern, value) is None:
        raise CandidateError(f"invalid {context}")
    return value


def inspect(bundle: Path) -> dict[str, str]:
    if not bundle.is_file() or bundle.is_symlink():
        raise CandidateError("candidate is not one regular file")
    if bundle.stat().st_size < 1 or bundle.stat().st_size > MAX_BUNDLE_BYTES:
        raise CandidateError("candidate bundle exceeds the size limit")

    seen: set[str] = set()
    expanded = 0
    manifest_member: tarfile.TarInfo | None = None
    with tarfile.open(bundle, mode="r:gz") as archive:
        members = archive.getmembers()
        if len(members) > MAX_MEMBERS:
            raise CandidateError("candidate contains too many members")
        for member in members:
            if not safe_name(member.name) or member.name in seen:
                raise CandidateError(f"unsafe or duplicate candidate member: {member.name!r}")
            seen.add(member.name)
            if member.isdir():
                if member.name != "payload":
                    raise CandidateError(f"unexpected candidate directory: {member.name}")
                continue
            if not member.isreg():
                raise CandidateError(f"non-regular candidate member: {member.name}")
            if member.name not in {"manifest.json", "SHA256SUMS"} and re.fullmatch(
                r"payload/[A-Za-z0-9][A-Za-z0-9+._~-]*", member.name
            ) is None:
                raise CandidateError(f"unexpected candidate member: {member.name}")
            expanded += member.size
            if expanded > MAX_EXPANDED_BYTES:
                raise CandidateError("candidate expands beyond the size limit")
            if member.name == "manifest.json":
                manifest_member = member

        if manifest_member is None or not 1 <= manifest_member.size <= MAX_MANIFEST_BYTES:
            raise CandidateError("candidate lacks a bounded manifest.json")
        manifest_stream = archive.extractfile(manifest_member)
        if manifest_stream is None:
            raise CandidateError("candidate manifest could not be read")
        manifest = json.loads(
            manifest_stream.read(MAX_MANIFEST_BYTES + 1),
            object_pairs_hook=reject_duplicate_keys,
        )

    if not isinstance(manifest, dict) or manifest.get("schema") != "ti.debian.candidate/v1":
        raise CandidateError("candidate manifest schema is invalid")
    producer = manifest.get("producer")
    source = manifest.get("source")
    build = manifest.get("build")
    publication = manifest.get("publication")
    if not all(isinstance(value, dict) for value in (producer, source, build, publication)):
        raise CandidateError("candidate manifest sections are invalid")

    expected_producer = {
        "repository": os.environ["GITHUB_REPOSITORY"],
        "workflow": os.environ["CANDIDATE_WORKFLOW"],
        "ref": os.environ["GITHUB_REF"],
        "commit": os.environ["GITHUB_SHA"],
        "run_id": int(os.environ["GITHUB_RUN_ID"]),
        "run_attempt": int(os.environ["GITHUB_RUN_ATTEMPT"]),
    }
    if producer != expected_producer:
        raise CandidateError("candidate producer identity does not match this workflow run")

    source_name = string(source.get("name"), r"[a-z0-9][a-z0-9+.-]+", "source name")
    source_version = string(source.get("version"), r"[^\s/]{1,200}", "source version")
    upstream_repository = string(
        source.get("upstream_repository"), r"https://[^\s]+", "upstream repository"
    )
    upstream_commit = string(
        source.get("upstream_commit"), r"[0-9a-f]{40}", "upstream commit"
    )
    if build.get("suite") != "trixie" or publication != {
        "suites": ["trixie"],
        "component": "main",
    }:
        raise CandidateError("candidate publication target is not trixie/main")
    architectures = build.get("binary_architectures")
    if not isinstance(architectures, list) or "arm64" not in architectures or any(
        architecture not in {"all", "arm64"} for architecture in architectures
    ):
        raise CandidateError("candidate architectures are not ARM64-compatible")

    safe_version = re.sub(r"[^A-Za-z0-9._-]", "_", source_version)
    expected_name = f"candidate-{source_name}_{safe_version}_trixie_arm64.tar.gz"
    if bundle.name != expected_name:
        raise CandidateError("candidate filename does not match its manifest")

    return {
        "path": str(bundle.resolve()),
        "name": bundle.name,
        "sha256": sha256(bundle),
        "source_name": source_name,
        "source_version": source_version,
        "upstream_repository": upstream_repository,
        "upstream_commit": upstream_commit,
    }


def main() -> int:
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <candidate.tar.gz> <github-output>", file=sys.stderr)
        return 2
    try:
        values = inspect(Path(sys.argv[1]))
        with Path(sys.argv[2]).open("a", encoding="utf-8") as output:
            for key, value in values.items():
                output.write(f"{key}={value}\n")
    except (CandidateError, json.JSONDecodeError, OSError, tarfile.TarError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
