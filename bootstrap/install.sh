#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  bash install.sh --tag <release-tag> [--repo <owner/repo>]

Example:
  curl -fsSL https://raw.githubusercontent.com/mikenitso/pivpn/v0.1.0/bootstrap/install.sh | bash -s -- --tag v0.1.0
USAGE
}

TAG=""
REPO="mikenitso/pivpn"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      TAG="${2:-}"
      shift 2
      ;;
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$TAG" ]]; then
  echo "--tag is required" >&2
  usage
  exit 1
fi

if [[ "$TAG" == "main" || "$TAG" == "master" ]]; then
  echo "Refusing non-release tag: $TAG" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required" >&2
  exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
  SHACMD="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
  SHACMD="shasum -a 256"
else
  echo "sha256 tool is required" >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

archive_url="https://github.com/${REPO}/archive/refs/tags/${TAG}.tar.gz"
checksums_url="https://raw.githubusercontent.com/${REPO}/${TAG}/SHASUMS256.txt"
archive_file="$tmpdir/repo.tar.gz"
checksums_file="$tmpdir/SHASUMS256.txt"

echo "Downloading release archive: $archive_url"
curl -fsSL "$archive_url" -o "$archive_file"

echo "Downloading checksums: $checksums_url"
curl -fsSL "$checksums_url" -o "$checksums_file"

expected="$(awk '$2=="repo.tar.gz" {print $1}' "$checksums_file" | head -n 1)"
if [[ -z "$expected" ]]; then
  echo "SHASUMS256.txt must contain: <sha256>  repo.tar.gz" >&2
  exit 1
fi

actual="$(eval "$SHACMD '$archive_file'" | awk '{print $1}')"
if [[ "$expected" != "$actual" ]]; then
  echo "Checksum mismatch for release archive" >&2
  exit 1
fi

echo "Checksum verified."

tar -xzf "$archive_file" -C "$tmpdir"
repo_dir="$tmpdir/$(basename "$REPO")-${TAG#v}"
if [[ ! -d "$repo_dir" ]]; then
  repo_dir="$(find "$tmpdir" -maxdepth 1 -type d -name "$(basename "$REPO")-*" | head -n 1)"
fi

if [[ -z "$repo_dir" || ! -x "$repo_dir/scripts/provision.sh" ]]; then
  echo "Provision script not found in extracted archive" >&2
  exit 1
fi

cd "$repo_dir"
if [[ "${EUID}" -ne 0 ]]; then
  exec sudo ./scripts/provision.sh install
else
  exec ./scripts/provision.sh install
fi
