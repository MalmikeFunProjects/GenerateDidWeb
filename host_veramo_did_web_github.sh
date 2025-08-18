#!/usr/bin/env bash
set -euo pipefail

# Script to fetch a did:web DID document from a Veramo server and commit it to a GitHub repo.

# Load environment variables from .env file if it exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a            # export all sourced vars
  . "$SCRIPT_DIR/.env"
  set +a
fi

# ------------ Config (override via env or flags) ------------
SERVER_URL="${SERVER_URL:-http://localhost:3332}"      # your Veramo server base
BRANCH="${BRANCH:-gh-pages}"                           # git branch to commit to
GIT_REMOTE="${GIT_REMOTE:-origin}"
COMMIT_MSG="${COMMIT_MSG:-chore(did): update did:web document}"
DRY_RUN="${DRY_RUN:-false}"                            # set to "true" to test without git push

# ------------ Usage function ------------
usage() {
  echo "Usage: $0 <did:web:...> [--server URL] [--branch BRANCH] [--dry-run]"
  echo "Example:"
  echo "  $0 'did:web:MalmikeFunProjects.github.io:GenerateDidWeb:device-4' --server http://localhost:3332"
}

# ------------ Args ------------
if [[ $# -lt 1 ]]; then usage; exit 1; fi
DID="$1"; shift || true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --server)  SERVER_URL="$2"; shift 2;;
    --branch)  BRANCH="$2";    shift 2;;
    --commit)  COMMIT_MSG="$2";shift 2;;
    --dry-run) DRY_RUN="true"; shift 1;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

# ------------ Parse DID ------------
# DID form: did:web:<host>:<project>:<path...>
if [[ "${DID}" != did:web:* ]]; then
  echo "Error: not a did:web DID: ${DID}" >&2; exit 1
fi

IFS=':' read -r _did _web HOST PROJECT REST <<<"${DID}"
parts=(${DID//:/ })
if (( ${#parts[@]} < 4 )); then
  echo "Error: DID missing project segment: ${DID}" >&2; exit 1
fi

HOST_ORIG="${parts[2]}"
HOST_LC="$(echo "${HOST_ORIG}" | tr '[:upper:]' '[:lower:]')"
PROJECT="${parts[3]}"
PATH_SEGS=()
for ((i=4; i<${#parts[@]}; i++)); do PATH_SEGS+=("${parts[$i]}"); done

# Host must be *.github.io
if [[ "${HOST_LC}" != *.github.io ]]; then
  echo "❌ Host '${HOST_ORIG}' is not a github.io host. Exiting."
  exit 1
fi

# Build URL path on your Veramo router, e.g. /GenerateDidWeb/device-4/did.json
URL_PATH="${PROJECT}"
if (( ${#PATH_SEGS[@]} > 0 )); then
  URL_PATH="${URL_PATH}/$(IFS='/'; echo "${PATH_SEGS[*]}")"
fi
FETCH_URL="${SERVER_URL}/${URL_PATH}/did.json"

# ------------ NEW: Trim PATH_SEGS that already exist in $PWD ------------
# We remove leading PATH_SEGS that match the current directory, then its parent, etc.
# Example: if PWD ends with ".../device-4" and PATH_SEGS=("device-4"), we end up with an empty target dir (".")
trimmed_segs=("${PATH_SEGS[@]}")
cwd="$PWD"
while (( ${#trimmed_segs[@]} > 0 )); do
  lastdir="$(basename "$cwd")"
  if [[ "$lastdir" == "${trimmed_segs[0]}" ]]; then
    # drop the matched head segment and move upward one directory
    trimmed_segs=("${trimmed_segs[@]:1}")
    cwd="$(dirname "$cwd")"
  else
    break
  fi
done

# Local file placement:
# "create a folder or folders with the values after the project name", minus what PWD already has
if (( ${#trimmed_segs[@]} > 0 )); then
  TARGET_DIR="$(IFS='/'; echo "${trimmed_segs[*]}")"
else
  TARGET_DIR="."   # nothing to create; we're already inside the last segment(s)
fi
TARGET_FILE="${TARGET_DIR}/did.json"

echo "DID:            ${DID}"
echo "Host (orig/lc): ${HOST_ORIG} / ${HOST_LC}"
echo "Project:        ${PROJECT}"
echo "Path segs:      ${PATH_SEGS[*]:-<none>}"
echo "Trimmed segs:   ${trimmed_segs[*]:-<none>}"
echo "Fetch URL:      ${FETCH_URL}"
echo "Target path:    ${TARGET_FILE}"
echo

# ------------ Fetch ------------
mkdir -p "${TARGET_DIR}"

tmp="$(mktemp)"
curl -fsS -H "Host: ${HOST_ORIG}" -o "$tmp" "${FETCH_URL}"

if command -v jq >/dev/null 2>&1; then
  if jq -S . < "$tmp" > "${TARGET_FILE}.tmp"; then
    mv "${TARGET_FILE}.tmp" "${TARGET_FILE}"
  else
    echo "Warning: invalid JSON; saving raw" >&2
    mv "$tmp" "${TARGET_FILE}"
    exit 0
  fi
elif command -v python3 >/dev/null 2>&1; then
  if python3 -m json.tool < "$tmp" > "${TARGET_FILE}.tmp"; then
    mv "${TARGET_FILE}.tmp" "${TARGET_FILE}"
  else
    echo "Warning: invalid JSON; saving raw" >&2
    mv "$tmp" "${TARGET_FILE}"
  fi
else
  echo "Formatter not found (install jq or python3). Saving raw." >&2
  mv "$tmp" "${TARGET_FILE}"
fi

rm -f "$tmp"
echo "Saved formatted JSON -> ${TARGET_FILE}"

# Optional sanity: verify the 'id' inside did.json matches the DID (with lowercase host)
if command -v jq >/dev/null 2>&1; then
  DOC_ID="$(jq -r '.id // empty' < "${TARGET_FILE}" || true)"
  EXPECTED_ID="did:web:${HOST}"
  if (( ${#PATH_SEGS[@]} > 0 )); then
    EXPECTED_ID="${EXPECTED_ID}:${PROJECT}:$(IFS=':'; echo "${PATH_SEGS[*]}")"
  else
    EXPECTED_ID="${EXPECTED_ID}:${PROJECT}"
  fi
  if [[ -n "${DOC_ID}" && "${DOC_ID}" != "${EXPECTED_ID}" ]]; then
    echo "Warning: DID doc id != expected"
    echo "  doc id:     ${DOC_ID}"
    echo "  expected:   ${EXPECTED_ID}"
  fi
else
  echo "Tip: install 'jq' to validate the DID doc id."
fi

# ------------ Git add/commit/push ------------
if [[ "${DRY_RUN}" == "true" ]]; then
  echo "[dry-run] Skipping git commit/push."
  exit 0
fi

# Ensure remote exists
if ! git remote get-url "${GIT_REMOTE}" >/dev/null 2>&1; then
  echo "❌ Remote '${GIT_REMOTE}' not found. Exiting."
  exit 1
fi

REMOTE_URL="$(git remote get-url "${GIT_REMOTE}")"
echo "Git remote URL: ${REMOTE_URL}"

# Expected GitHub username is the subdomain part (before .github.io)
EXPECTED_USER="${HOST_LC%%.github.io}"

# Parse GitHub remote URL → GH_USER / GH_REPO
GH_USER=""
GH_REPO=""

# SSH form: git@github.com:User/Repo.git
if [[ "${REMOTE_URL}" =~ ^git@github\.com:([^/]+)/([^/]+)(\.git)?$ ]]; then
  GH_USER="${BASH_REMATCH[1]}"
  GH_REPO="${BASH_REMATCH[2]}"
# HTTPS form: https://github.com/User/Repo(.git)
elif [[ "${REMOTE_URL}" =~ ^https://github\.com/([^/]+)/([^/]+)(\.git)?$ ]]; then
  GH_USER="${BASH_REMATCH[1]}"
  GH_REPO="${BASH_REMATCH[2]}"
else
  echo "❌ Remote '${GIT_REMOTE}' is not a GitHub SSH/HTTPS URL. Exiting."
  exit 1
fi

# Normalize cases for comparison (GitHub usernames are case-insensitive)
if [[ "${GH_USER,,}" != "${EXPECTED_USER,,}" ]]; then
  echo "❌ GitHub username mismatch."
  echo "    From host: ${EXPECTED_USER}"
  echo "    From remote: ${GH_USER}"
  exit 1
fi

# Strip any trailing .git from repo (already handled in regex, but double-safe)
GH_REPO="${GH_REPO%.git}"

# Project must equal repo name (case-insensitive compare is usually fine)
if [[ "${GH_REPO,,}" != "${PROJECT,,}" ]]; then
  echo "❌ Repo name mismatch."
  echo "    Project (from DID): ${PROJECT}"
  echo "    Repo (from remote): ${GH_REPO}"
  exit 1
fi

echo "✅ Checks passed (host *.github.io, username '${GH_USER}', repo '${GH_REPO}')."

# Safe to commit/push
git checkout -B "${BRANCH}"
git add "${TARGET_FILE}"
git commit -m "${COMMIT_MSG}" || true   # allow empty commits
# git push -u "${GIT_REMOTE}" "${BRANCH}"
echo "✅ Pushed ${TARGET_FILE} to ${BRANCH}"
