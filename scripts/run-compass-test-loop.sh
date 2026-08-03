#!/usr/bin/env bash
# Build Compass CLI, prepare the candidate repo, and run one headless MLX factory pass.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="${ROOT}/.build/debug/compass-cli"
TEST_REPO="${COMPASS_TEST_REPO:-${HOME}/tmp/compass-test}"
BRIEF="${COMPASS_TEST_BRIEF:-${TEST_REPO}/factory-brief.md}"
MAX_ITERATIONS="${COMPASS_MAX_ITERATIONS:-10}"
MAX_DEVELOP_ATTEMPTS="${COMPASS_MAX_DEVELOP_ATTEMPTS:-3}"
MAX_VERIFY_REPAIRS="${COMPASS_MAX_VERIFY_REPAIRS:-1}"
RUN_ID="${COMPASS_RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
PROMPT_LOG_DIR="${TEST_REPO}/.compass/prompt-logs/${RUN_ID}"
RUN_LOG="${TEST_REPO}/.compass/runs/${RUN_ID}.jsonl"

if [[ ! -d "${TEST_REPO}" ]]; then
  echo "error: candidate repo not found: ${TEST_REPO}" >&2
  exit 1
fi

if [[ ! -f "${BRIEF}" ]]; then
  echo "error: brief not found: ${BRIEF}" >&2
  exit 1
fi

cd "${ROOT}"

"${ROOT}/scripts/build-cli-local.sh" >/dev/null

"${CLI}" doctor --repo "${TEST_REPO}" --format text

if [[ "${COMPASS_PREPARE_VM_DEPS:-1}" == "1" ]]; then
  "${CLI}" verify \
    --repo "${TEST_REPO}" \
    --command "cargo fetch --locked 2>/dev/null || cargo fetch" \
    --format text
fi

mkdir -p "${PROMPT_LOG_DIR}" "$(dirname "${RUN_LOG}")"

set +e
"${CLI}" run \
  --repo "${TEST_REPO}" \
  --brief "${BRIEF}" \
  --mode mlx \
  --prompt-log "${PROMPT_LOG_DIR}" \
  --max-iterations "${MAX_ITERATIONS}" \
  --max-develop-attempts "${MAX_DEVELOP_ATTEMPTS}" \
  --max-verify-repairs "${MAX_VERIFY_REPAIRS}" \
  --format json | tee "${RUN_LOG}"
status="${PIPESTATUS[0]}"
set -e

echo "Run log: ${RUN_LOG}"
echo "Prompt log: ${PROMPT_LOG_DIR}"
exit "${status}"
