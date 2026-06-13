#!/usr/bin/env bash
# Run a deterministic Compass -> Tessera local iteration smoke test.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_NAME="${COMPASS_TESSERA_SMOKE_NAME:-local-tessera-smoke}"
KEEP_WORKSPACE="${COMPASS_KEEP_TESSERA_SMOKE:-0}"
CREATED_WORK_DIR=0
NORMALIZED_PROJECT_NAME="$(
  printf '%s' "${PROJECT_NAME}" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9._-]+/-/g; s/^[._-]+//; s/[._-]+$//'
)"
if [[ -z "${NORMALIZED_PROJECT_NAME}" ]]; then
  NORMALIZED_PROJECT_NAME="compass-tessera-app"
fi

if [[ -n "${COMPASS_TESSERA_SMOKE_DIR:-}" ]]; then
  WORK_DIR="${COMPASS_TESSERA_SMOKE_DIR}"
  mkdir -p "${WORK_DIR}"
else
  WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/compass-tessera-smoke.XXXXXX")"
  CREATED_WORK_DIR=1
fi

PROJECT_DIR="${WORK_DIR}/project"
FIXTURE="${WORK_DIR}/fixture.jsonl"
PROMPT_LOG_DIR="${WORK_DIR}/prompt-logs"
RUN_LOG="${WORK_DIR}/run.log"

cleanup() {
  local exit_code=$?
  if [[ "${KEEP_WORKSPACE}" == "1" || "${exit_code}" -ne 0 || "${CREATED_WORK_DIR}" != "1" ]]; then
    echo "Smoke workspace kept at ${WORK_DIR}"
  else
    rm -rf "${WORK_DIR}"
  fi
}
trap cleanup EXIT

ensure_tessera_cli() {
  if [[ -n "${TESSERA_BIN:-}" ]]; then
    if [[ ! -x "${TESSERA_BIN}" ]]; then
      echo "error: TESSERA_BIN is not executable: ${TESSERA_BIN}" >&2
      exit 1
    fi
    export PATH="$(cd "$(dirname "${TESSERA_BIN}")" && pwd):${PATH}"
    return
  fi

  if command -v tessera >/dev/null 2>&1; then
    return
  fi

  local tessera_root="${TESSERA_ROOT:-${HOME}/git/Tessera}"
  local local_bin="${tessera_root}/target/debug/tessera"
  if [[ ! -x "${local_bin}" ]]; then
    if [[ ! -d "${tessera_root}" ]]; then
      echo "error: tessera not found on PATH and Tessera repo is missing at ${tessera_root}" >&2
      echo "Set TESSERA_BIN=/path/to/tessera or TESSERA_ROOT=/path/to/Tessera." >&2
      exit 1
    fi
    if ! command -v cargo >/dev/null 2>&1; then
      echo "error: cargo is required to build ${local_bin}" >&2
      exit 1
    fi
    echo "Building Tessera CLI from ${tessera_root}"
    (cd "${tessera_root}" && cargo build -p tessera-cli --bin tessera)
  fi

  export PATH="${tessera_root}/target/debug:${PATH}"
}

if [[ -e "${PROJECT_DIR}" ]]; then
  echo "error: smoke project already exists: ${PROJECT_DIR}" >&2
  exit 1
fi

cd "${ROOT}"

ensure_tessera_cli

CLI="$("${ROOT}/scripts/build-cli-local.sh" | tail -n 1)"
if [[ ! -x "${CLI}" ]]; then
  echo "error: compass-cli build did not produce an executable path: ${CLI}" >&2
  exit 1
fi

cat >"${FIXTURE}" <<'JSONL'
{"text":"{\"kind\":\"plan_submit\",\"payload\":{\"state\":{\"immediate\":{\"plan\":\"## Outcome\\nUpdate the generated Tessera display function to greet users with a Hello prefix and update its JSON test expectation.\\n\\n## Acceptance checks\\n- src/display-name.tes prefixes the display label with Hello.\\n- tests/display-name.json expects Hello, __PROJECT_NAME__!.\\n- The embedded Tessera run_test tool passes for tests/display-name.json.\\n- tessera verify . --json passes.\",\"verify\":\"tessera verify . --json\",\"verifyTimeoutMs\":60000,\"estimatedDifficulty\":\"low\",\"selectedBecause\":\"This deterministic slice proves Compass can scaffold a Tessera app, inspect it, edit Tessera source and tests, run a focused embedded Tessera check, and finish with the standard Tessera verify command.\",\"source\":\"repository\",\"candidateID\":null},\"queue\":[],\"brief\":{\"summary\":\"Smoke test Compass local Tessera iteration on a generated workspace.\",\"targetUsers\":[\"Compass maintainers\"],\"desiredOutcomes\":[\"Compass drives a Tessera app through a normal headless factory pass without using MLX output.\"],\"constraints\":[\"Keep the change tiny and deterministic.\"],\"acceptanceSignals\":[\"The Tessera test and standard verify command pass after Compass commits the edit.\"]},\"openQuestions\":[]},\"lessonEdits\":[]}}"}
{"text":"{\"kind\":\"develop_continue\",\"tool\":\"tessera\",\"arguments\":{\"action\":\"inspect_project\"},\"reason\":\"Ground the generated Tessera workspace through Compass's embedded engine before editing.\"}"}
{"text":"{\"kind\":\"develop_continue\",\"tool\":\"read_file\",\"arguments\":{\"path\":\"src/display-name.tes\"},\"reason\":\"Need current source line numbers before editing the display function.\"}"}
{"text":"{\"kind\":\"develop_continue\",\"tool\":\"edit_file\",\"arguments\":{\"path\":\"src/display-name.tes\",\"startLine\":2,\"endLine\":2,\"content\":\"(def display ((name Text)) (concat \\\"Hello, \\\" (concat name \\\"!\\\")))\"},\"reason\":\"Prefix display labels with Hello while preserving the existing exclamation mark.\"}"}
{"text":"{\"kind\":\"develop_continue\",\"tool\":\"read_file\",\"arguments\":{\"path\":\"tests/display-name.json\"},\"reason\":\"Need current test line numbers before updating the expectation.\"}"}
{"text":"{\"kind\":\"develop_continue\",\"tool\":\"edit_file\",\"arguments\":{\"path\":\"tests/display-name.json\",\"startLine\":5,\"endLine\":5,\"content\":\"  \\\"expect\\\": \\\"Hello, __PROJECT_NAME__!\\\"\"},\"reason\":\"Align the generated test expectation with the new greeting output.\"}"}
{"text":"{\"kind\":\"develop_continue\",\"tool\":\"tessera\",\"arguments\":{\"action\":\"run_test\",\"test_path\":\"tests/display-name.json\"},\"reason\":\"Run the focused embedded Tessera test before submitting the iteration.\"}"}
{"text":"{\"kind\":\"develop_submit\",\"payload\":{\"status\":\"succeeded\",\"summary\":\"Updated the generated Tessera display function and JSON test to produce Hello-prefixed display labels.\",\"feedback\":\"The embedded Tessera run_test tool passed for tests/display-name.json; Compass can run the standard Tessera verify command and commit the verified host changes.\",\"bypassVerify\":false,\"lessonEdits\":[]}}"}
JSONL
sed "s/__PROJECT_NAME__/${NORMALIZED_PROJECT_NAME}/g" "${FIXTURE}" >"${FIXTURE}.tmp"
mv "${FIXTURE}.tmp" "${FIXTURE}"

echo "Scaffolding Tessera smoke project at ${PROJECT_DIR}"
"${CLI}" scaffold tessera "${PROJECT_DIR}" --name "${PROJECT_NAME}" --format text

echo "Running Compass fixture iteration against the Tessera project"
set +e
"${CLI}" run \
  --repo "${PROJECT_DIR}" \
  --brief "Smoke test local Compass iteration on a generated Tessera app." \
  --mode fixture \
  --fixture "${FIXTURE}" \
  --prompt-log "${PROMPT_LOG_DIR}" \
  --max-iterations 12 \
  --max-develop-attempts 1 \
  --max-verify-repairs 0 \
  --format text | tee "${RUN_LOG}"
run_status="${PIPESTATUS[0]}"
set -e

if [[ "${run_status}" -ne 0 ]]; then
  echo "error: Compass fixture iteration failed; run log: ${RUN_LOG}" >&2
  exit "${run_status}"
fi

grep -Fq '(concat "Hello, "' "${PROJECT_DIR}/src/display-name.tes"
grep -Fq "\"expect\": \"Hello, ${NORMALIZED_PROJECT_NAME}!\"" "${PROJECT_DIR}/tests/display-name.json"

"${CLI}" verify \
  --repo "${PROJECT_DIR}" \
  --command "tessera verify . --json" \
  --format text

if [[ -n "$(git -C "${PROJECT_DIR}" status --short)" ]]; then
  echo "error: smoke project has uncommitted changes after Compass run" >&2
  git -C "${PROJECT_DIR}" status --short >&2
  exit 1
fi

echo "Compass Tessera smoke passed."
echo "Prompt logs: ${PROMPT_LOG_DIR}"
echo "Run log: ${RUN_LOG}"
