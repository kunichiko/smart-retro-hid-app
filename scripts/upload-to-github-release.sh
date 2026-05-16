#!/usr/bin/env bash
# ===================================================================================
# Bitrise の tag-triggered ビルドで生成した成果物を GitHub Releases に
# 添付するスクリプト。
#
# 使い方:
#     bash scripts/upload-to-github-release.sh <file-path>
#
# 必要な環境変数:
#   - BITRISE_GIT_TAG     : Bitrise が tag-triggered build で自動設定 (例: v1.0.4)
#   - GH_RELEASE_TOKEN    : GitHub Personal Access Token
#                           - 必須 scope: contents: write (Fine-grained PAT 推奨)
#                           - Bitrise の Secrets に登録しておく
#
# 非 tag ビルドでは何もせず正常終了するので、PR / develop push の workflow に
# 入れたままでも安全。
# ===================================================================================
set -euo pipefail

if [ -z "${BITRISE_GIT_TAG:-}" ]; then
  echo "ℹ︎  BITRISE_GIT_TAG が空 → tag トリガーではないので GitHub Release アップロードをスキップ"
  exit 0
fi

if [ -z "${GH_RELEASE_TOKEN:-}" ]; then
  echo "❌ ERROR: GH_RELEASE_TOKEN が未設定です"
  echo "   Bitrise の Secrets に contents: write 権限の PAT を GH_RELEASE_TOKEN として登録してください"
  exit 1
fi

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <file-path>"
  exit 1
fi

FILE="$1"
if [ ! -f "$FILE" ]; then
  echo "❌ ERROR: file not found: $FILE"
  exit 1
fi

# gh CLI が GH_TOKEN を読みに来るので環境変数で渡す
export GH_TOKEN="$GH_RELEASE_TOKEN"

echo "Uploading $FILE to release $BITRISE_GIT_TAG ..."
gh release upload "$BITRISE_GIT_TAG" "$FILE" --clobber
echo "✓ Uploaded"
