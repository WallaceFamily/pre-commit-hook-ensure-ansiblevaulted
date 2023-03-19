#!/usr/bin/env bash
# -*- coding: utf-8 -*-

#
# (c) 2023, Andrew Sichevoi https://thekondor.net
#

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SUT_DIR="$(dirname "${SELF_DIR}")"

# shellcheck source=tests/common_test-repo.sh.inc
source "${SELF_DIR}/common_test-repo.sh.inc"

create_test_repo

if ! git init .; then
  echo "git repo initialization failed"
  exit 1
fi

if [ -z "${USE_SYSTEM_ANSIBLE}" ]; then
  if ! virtualenv venv; then
    echo "failed: establish virtualenv"
    exit 1
  fi
  # shellcheck disable=SC1091
  source venv/bin/activate

  if ! pip install ansible-vault; then
    echo "failed: install ansible-vault"
    exit 1
  fi
fi

cp -r "${SELF_DIR}"/payload/core-smoke.test-repo.d/. .
cp -r "${SELF_DIR}"/payload/core-smoke.cfg.d/. .
ls -la .

### This will also add `.vault-password` which in normal case doesn't belong to a git repo
git add .
git commit -m "initial commit"

"${SUT_DIR}"/hook.sh

git_staged_output=$(mktemp)
git diff --name-only --cached | tee "${git_staged_output}" | while read -r staged; do
  # shellcheck disable=SC2016
  if ! head -n 1 "${staged}" | grep '\$ANSIBLE_VAULT' >/dev/null 2>&1; then
    echo "❌❗️ Malformed vault"
    exit 1
  fi
done

echo "--- ❇️ CASE: normal/errorless flow"
echo "🔸diff{"
echo \
  "dirA1/dirA2/repo.another-secret.vault
dirA1/repo.new-secret.vault
repo.secret.vault" | diff -u "${git_staged_output}" -
DIFF_RC=$?
rm -f "${git_staged_output}"
echo "}diff🔸"

if [ ! 0 -eq ${DIFF_RC} ]; then
  echo "❌ FAILED"
  exit 1
else
  echo "✅ PASSED"
fi

### NOTE: depends on the previous repo status
echo "--- ❇️ CASE: track ignored with warning"
if ! yq e -i '.track-git-ignored = ".with-warning"' .ensure-ansiblevaulted.yml; then
  echo "failed: update config"
  exit 1
fi

touch "foo.not-ignored-secret"

if ! "${SUT_DIR}"/hook.sh | grep -q "foo.not-ignored-secret is not declared in .gitignore"; then
  echo "❌ FAILED"
  exit 1
else
  echo "✅ PASSED"
fi

### NOTE: depends on the previous repo status
echo "--- ❇️ CASE: track ignored with error"
if ! yq e -i '.track-git-ignored = ".with-error"' .ensure-ansiblevaulted.yml; then
  echo "failed: update config"
  exit 1
fi

output="$("${SUT_DIR}"/hook.sh)"
hook_rc=$?
if [ 0 -ne $hook_rc ] &&
  echo "${output}" | grep -q "foo.not-ignored-secret is not declared in .gitignore" &&
  echo "${output}" | grep -q "this is critical"; then
  echo "✅ PASSED"
else
  echo "❌ FAILED"
  echo "output: ${output}"
fi
