#!/usr/bin/env bash
# Merge a Ruff release into Muff and open a pull request for it.
#
# `.github/workflows/muff-sync-upstream.yml` runs this script every day; that file explains the
# overall process. The script can also run locally, from a clean checkout of Muff's `main` whose
# `origin` is `jsh9/muff`, with `gh` authenticated.
#
# Environment variables (all optional):
#
#   RUFF_VERSION  The Ruff release to merge, for example `0.17.7`. Defaults to Ruff's latest release.
#   DRY_RUN       If `true`, merge locally but do not push or open a pull request.
#   MUFF_REPO     The repository to open the pull request in. Defaults to `jsh9/muff`. This must be
#                 given explicitly, because `gh` would otherwise default to the parent repository
#                 of the fork, `astral-sh/ruff`.
#   RUFF_URL      The Git URL to fetch Ruff's release tag from. Defaults to Ruff's GitHub repository.
#                 Only useful for testing this script against a local repository.

set -euo pipefail

# Arrays that may be empty are expanded as `${array[@]+"${array[@]}"}`, because older versions of
# Bash (such as the one that ships with macOS) treat an empty array as unset under `set -u`.

ruff_repo="astral-sh/ruff"
muff_repo="${MUFF_REPO:-jsh9/muff}"
dry_run="${DRY_RUN:-false}"

muff_version="$(python3 -c 'import tomllib; print(tomllib.load(open("pyproject.toml", "rb"))["project"]["version"])')"

version="${RUFF_VERSION:-}"
if [[ -z "${version}" ]]; then
  version="$(gh release view --repo "${ruff_repo}" --json tagName --jq .tagName)"
fi
if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "::error::'${version}' is not a Ruff release version of the form X.Y.Z."
  exit 1
fi

# `sort -V` also orders fork-only versions such as `0.17.6.1` after `0.17.6` and before `0.17.7`.
newest="$(printf '%s\n%s\n' "${muff_version}" "${version}" | sort -V | tail -n 1)"
if [[ "${version}" == "${muff_version}" || "${newest}" != "${version}" ]]; then
  echo "Muff ${muff_version} already includes Ruff ${version}. Nothing to do."
  exit 0
fi
echo "Merging Ruff ${version} into Muff ${muff_version}."

branch="muff-sync/ruff-${version}"
if git ls-remote --exit-code --heads origin "${branch}" > /dev/null; then
  echo "Branch ${branch} already exists, so there already is a pull request for Ruff ${version}."
  echo "To start over, close that pull request and delete the branch."
  exit 0
fi

# Ruff's tags are fetched outside `refs/tags/`, because Muff has its own tags with the same names.
git fetch --quiet --no-tags "${RUFF_URL:-https://github.com/${ruff_repo}.git}" \
  "+refs/tags/${version}:refs/ruff-tags/${version}"
ruff_commit="$(git rev-parse "refs/ruff-tags/${version}^{commit}")"

git switch --quiet --create "${branch}"

# A failing merge is fine here: the conflicts are handled below. A merge that fails for any other
# reason leaves no `MERGE_HEAD`.
git merge --no-ff --no-commit "${ruff_commit}" || true
if ! git rev-parse --quiet --verify MERGE_HEAD > /dev/null; then
  echo "::error::Could not start merging Ruff ${version} (${ruff_commit})."
  exit 1
fi

auto_resolved=()
unresolved=()
while IFS= read -r path; do
  case "${path}" in
    .github/workflows/muff-*)
      unresolved+=("${path}")
      ;;
    .github/workflows/*)
      # Ruff's workflows need Astral's paid runners. Muff deletes them, so every change Ruff makes
      # to one of them conflicts with that deletion.
      git rm --quiet -- "${path}"
      auto_resolved+=("\`${path}\`: kept deleted (Ruff workflow)")
      ;;
    pyproject.toml)
      # Ruff bumps `version` in every release, right below the `name` line that Muff changes, so
      # Git sees one conflict. Undo Muff's rename in our side, merge again, and redo the rename.
      # Any other conflict in this file is left for a person to resolve.
      ours="$(mktemp)" base="$(mktemp)" theirs="$(mktemp)"
      git show :2:pyproject.toml | sed 's/^name = "muff"$/name = "ruff"/' > "${ours}"
      git show :1:pyproject.toml > "${base}"
      git show :3:pyproject.toml > "${theirs}"
      if git merge-file "${ours}" "${base}" "${theirs}"; then
        sed 's/^name = "ruff"$/name = "muff"/' "${ours}" > pyproject.toml
        git add pyproject.toml
        auto_resolved+=("\`pyproject.toml\`: merged Ruff's version bump and kept the package name \`muff\`")
      else
        unresolved+=("${path}")
      fi
      rm -f "${ours}" "${base}" "${theirs}"
      ;;
    *)
      unresolved+=("${path}")
      ;;
  esac
done < <(git diff --name-only --diff-filter=U)

# Ruff workflows that the merge adds back, either new ones or ones Ruff changed without a conflict.
removed_workflows=()
while IFS= read -r path; do
  # `--force`, because the merge has staged changes to these files.
  git rm --quiet --force -- "${path}"
  removed_workflows+=("\`${path}\`")
done < <(git ls-files -- .github/workflows | grep -v '^\.github/workflows/muff-' | sort -u || true)

# Check that the merge kept Muff's changes. A clean merge can still drop one, for example if Ruff
# moves the code that Muff changed to another file.
lost=()
expect() {
  local path="$1" text="$2"
  if ! grep -qF -- "${text}" "${path}" 2> /dev/null; then
    lost+=("\`${path}\` no longer contains \`${text}\`")
  fi
}
if [[ ${#unresolved[@]} -eq 0 ]]; then
  expect pyproject.toml 'name = "muff"'
  expect pyproject.toml "version = \"${version}\""
  expect crates/ruff/Cargo.toml 'default-run = "muff"'
  expect crates/ruff/Cargo.toml 'name = "muff"'
  expect crates/ruff/src/args.rs 'name = "muff"'
  expect python/ruff/_find_ruff.py 'ruff_exe = "muff"'
  expect crates/ruff_python_formatter/src/other/parameters.rs 'TwoLevelBlockIndent'
fi

# Unresolved conflicts are committed with their conflict markers, so that the pull request shows
# them and can be fixed on its branch.
if [[ ${#unresolved[@]} -gt 0 ]]; then
  git add -- "${unresolved[@]}"
fi
git commit --quiet --no-verify -m "Merge Ruff ${version}" \
  -m "Merge the Ruff ${version} release (${ruff_commit}) into Muff."

needs_attention=false
if [[ ${#unresolved[@]} -gt 0 || ${#lost[@]} -gt 0 ]]; then
  needs_attention=true
fi

list() {
  if [[ $# -eq 0 ]]; then
    echo "None."
  else
    printf -- '- %s\n' "$@"
  fi
}

body_file="$(mktemp)"
{
  echo "Merges [Ruff ${version}](https://github.com/${ruff_repo}/releases/tag/${version}) (${ruff_commit}) into Muff."
  echo
  if [[ "${needs_attention}" == "true" ]]; then
    echo "## Needs attention"
    echo
    if [[ ${#unresolved[@]} -gt 0 ]]; then
      echo "These files have merge conflicts. They are committed with conflict markers:"
      echo
      for path in "${unresolved[@]}"; do
        echo "- \`${path}\`"
      done
      echo
    fi
    if [[ ${#lost[@]} -gt 0 ]]; then
      echo "The merge may have dropped some of Muff's changes:"
      echo
      list "${lost[@]}"
      echo
    fi
    echo "To fix this, check out this branch, make the fix, and amend the merge commit so that it"
    echo "keeps both of its parents:"
    echo
    echo '```sh'
    echo "git fetch origin ${branch} && git switch ${branch}"
    echo "# ...fix the files..."
    echo "git add <files> && git commit --amend --no-edit"
    echo "git push --force-with-lease origin ${branch}"
    echo '```'
    echo
    echo "Then mark this pull request as ready for review."
    echo
  fi
  echo "## How to merge"
  echo
  echo "Use **Create a merge commit**. Squash and rebase merges drop the link to Ruff's history,"
  echo "so the next sync would conflict on everything Ruff has changed since, and \`[muff] Release\`"
  echo "refuses to release from such a commit."
  echo
  echo "Merging releases Muff ${version}: the push to \`main\` starts \`[muff] Release\`, which"
  echo "publishes to GitHub and PyPI and then updates \`jsh9/muff-pre-commit\`."
  echo
  echo "## Conflicts resolved automatically"
  echo
  list ${auto_resolved[@]+"${auto_resolved[@]}"}
  echo
  echo "## Ruff workflows removed"
  echo
  list ${removed_workflows[@]+"${removed_workflows[@]}"}
} > "${body_file}"

title="Merge Ruff ${version}"
if [[ "${dry_run}" == "true" ]]; then
  echo "Dry run: not pushing ${branch} or opening a pull request. It would be:"
  echo
  echo "# ${title}"
  cat "${body_file}"
  exit 0
fi

git push --quiet origin "${branch}"
draft=()
if [[ "${needs_attention}" == "true" ]]; then
  draft=(--draft)
fi
gh pr create --repo "${muff_repo}" --base main --head "${branch}" \
  --title "${title}" --body-file "${body_file}" ${draft[@]+"${draft[@]}"}
