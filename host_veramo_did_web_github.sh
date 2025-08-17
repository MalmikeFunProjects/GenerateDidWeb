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
REPO_DIR="${REPO_DIR:-$(pwd)}"                         # path to the GenerateDidWeb repo root
BRANCH="${BRANCH:-gh-pages}"                               # git branch to commit to
COMMIT_MSG="${COMMIT_MSG:-chore(did): update did:web document}"
DRY_RUN="${DRY_RUN:-false}"                            # set to "true" to test without git push

# ------------ Usage function ------------
usage() {
  echo "Usage: $0 <did:web:...> [--server URL] [--repo PATH] [--branch BRANCH] [--dry-run]"
  echo "Example:"
  echo "  $0 'did:web:MalmikeFunProjects.github.io:GenerateDidWeb:device-4' --server http://localhost:3332 --repo ~/code/GenerateDidWeb"
}

# ------------ Args ------------
if [[ $# -lt 1 ]]; then usage; exit 1; fi
DID="$1"; shift || true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --server)  SERVER_URL="$2"; shift 2;;
    --repo)    REPO_DIR="$2";  shift 2;;
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
# When there are multiple path segments, $REST will only contain the first remainder token;
# so collect all remaining parts manually:
parts=(${DID//:/ })
# parts[0]=did, [1]=web, [2]=HOST, [3]=PROJECT, [4..]=path segments
if (( ${#parts[@]} < 4 )); then
  echo "Error: DID missing project segment: ${DID}" >&2; exit 1
fi

HOST_ORIG="${parts[2]}"
HOST_LC="$(echo "${HOST_ORIG}" | tr '[:upper:]' '[:lower:]')"
PROJECT="${parts[3]}"
PATH_SEGS=()
for ((i=4; i<${#parts[@]}; i++)); do PATH_SEGS+=("${parts[$i]}"); done

# Build URL path on your Veramo router, e.g. /GenerateDidWeb/device-4/did.json
URL_PATH="${PROJECT}"
if (( ${#PATH_SEGS[@]} > 0 )); then
  URL_PATH="${URL_PATH}/$(IFS='/'; echo "${PATH_SEGS[*]}")"
fi
FETCH_URL="${SERVER_URL}/${URL_PATH}/did.json"

# Local file placement inside the repo:
# "create a folder or folders with the values after the project name"
TARGET_DIR="${REPO_DIR}"
if (( ${#PATH_SEGS[@]} > 0 )); then
  TARGET_DIR="${REPO_DIR}/$(IFS='/'; echo "${PATH_SEGS[*]}")"
fi
TARGET_FILE="${TARGET_DIR}/did.json"

echo "DID:            ${DID}"
echo "Host (orig/lc): ${HOST_ORIG} / ${HOST_LC}"
echo "Project:        ${PROJECT}"
echo "Path segs:      ${PATH_SEGS[*]:-<none>}"
echo "Fetch URL:      ${FETCH_URL}"
echo "Target path:    ${TARGET_FILE}"
echo

# ------------ Fetch ------------
mkdir -p "${TARGET_DIR}"
# -f: fail on HTTP error; -S: show errors; -s: silent progress
curl -fSs -H "Host: ${HOST_ORIG}" -o "${TARGET_FILE}" "${FETCH_URL}"
echo "Fetched -> ${TARGET_FILE}"

# Optional sanity: verify the 'id' inside did.json matches the DID (with lowercase host)
if command -v jq >/dev/null 2>&1; then
  DOC_ID="$(jq -r '.id // empty' < "${TARGET_FILE}" || true)"
  EXPECTED_ID="did:web:${HOST_LC}"
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

if [[ ! -d "${REPO_DIR}/.git" ]]; then
  echo "Error: ${REPO_DIR} is not a git repo" >&2; exit 1
fi

git -C "${REPO_DIR}" checkout -B "${BRANCH}"
git -C "${REPO_DIR}" add "${TARGET_FILE}"
git -C "${REPO_DIR}" commit -m "${COMMIT_MSG}" || true   # allow empty (no changes)
git -C "${REPO_DIR}" push -u origin "${BRANCH}"

echo "✅ Pushed ${TARGET_FILE} to ${BRANCH}"
