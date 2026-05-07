#!/usr/bin/env bash
# ===================================================================================
# Bitrise の tag-triggered ビルド時に、git tag (v 接頭辞除去) と pubspec.yaml の
# version (X.Y.Z 部分) が一致するか検証するスクリプト。
#
# 一致した場合は BUILD_NAME / BUILD_NUMBER を envman に export し、
# 後段の `flutter build` ステップで `--build-name=$BUILD_NAME --build-number=$BUILD_NUMBER`
# として参照することで、ビルド番号は Bitrise の自動採番 ($BITRISE_BUILD_NUMBER) を
# 使い、バージョン名は tag を信頼ソースとする運用ができる。
#
# 使い方 (Bitrise の Script ステップから):
#     bash scripts/check-tag-version.sh
# ===================================================================================
set -euo pipefail

if [ -z "${BITRISE_GIT_TAG:-}" ]; then
  echo "ℹ︎  BITRISE_GIT_TAG が空 → tag トリガーではないのでスキップ"
  exit 0
fi

TAG_VERSION="${BITRISE_GIT_TAG#v}"
PUBSPEC_VERSION=$(grep -E '^version:' pubspec.yaml | sed -E 's/version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/')

echo "git tag       : $BITRISE_GIT_TAG"
echo "tag version   : $TAG_VERSION"
echo "pubspec       : $PUBSPEC_VERSION"

if [ "$TAG_VERSION" != "$PUBSPEC_VERSION" ]; then
  echo "❌ ERROR: pubspec.yaml の version ($PUBSPEC_VERSION) と tag ($TAG_VERSION) が不一致です"
  echo "   pubspec.yaml の version を $TAG_VERSION に更新してから tag を打ち直してください"
  exit 1
fi

# Bitrise の env machine に export (後段ステップで $BUILD_NAME / $BUILD_NUMBER として使える)
envman add --key BUILD_NAME   --value "$TAG_VERSION"
envman add --key BUILD_NUMBER --value "${BITRISE_BUILD_NUMBER:-1}"

echo "✓ Version match. BUILD_NAME=$TAG_VERSION BUILD_NUMBER=${BITRISE_BUILD_NUMBER:-1}"
