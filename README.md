# MimicX-app

**製品名: Mimic X**

スマートフォン（iOS/Android）からUSB-MIDI経由でマイコンを制御し、レトロPCのHIDデバイス（キーボード・マウス・ジョイスティック）を模倣するFlutterアプリ。

「Mimic X」コントローラーアプリ。様々なレトロデバイスに変身可能。

## 機能

- ジョイスティックモード: 画面上の仮想ジョイスティックで操作
  - ATARI 2 ボタン互換
  - メガドライブ 6 ボタンファイティングパッド互換
- キーボードモード: レトロPCのキーボードレイアウトを再現し、タイプ入力が可能
- レトロPC本体からの信号受信（キーボードLED制御など）に対応

## 開発環境

Flutter SDK のバージョンは [`.fvmrc`](./.fvmrc) で固定 (現在 3.38.5)。
[FVM](https://fvm.app/) を使ってバージョンを揃えるのが推奨。

```sh
# 初回 clone 後
brew install fvm           # 未インストールなら
fvm install                # .fvmrc に書かれたバージョンを取得
fvm flutter pub get
fvm flutter run
```

VS Code / Android Studio から開く場合は Flutter SDK の path を `.fvm/flutter_sdk`
に向けるか、シェルで `fvm flutter ...` を使う。

## 開発フロー (git-flow ベース)

ブランチ運用は [A successful Git branching model (Vincent Driessen)](https://nvie.com/posts/a-successful-git-branching-model/)
に倣った構成。

- **`main`**: リリース版。直接 push は禁止、PR 経由のみ。merge commit
  (`--no-ff`) で develop からのリリースを取り込む。タグ打ちもこのブランチに対して。
- **`develop`**: 開発統合ブランチ。日常の開発 commit はここに積む。`main` の
  祖先関係を維持するので force push / reset は行わない (= 他人が `develop` を
  base にした PR を立てても破綻しない)。
- **feature ブランチ** (任意): 大きな変更や複数 commit に渡る作業は
  `feature/<name>` を切って `develop` への PR を立てる。

### コントリビュータ向け

外部からの PR は `develop` を base にしてください (リリース直前の hotfix のみ
`main` を base にして直接 PR でも OK)。

## リリース手順

タグを起点に Bitrise が自動でビルド・署名し、成果物 (Android APK / macOS ZIP) を
ローカルにダウンロードしたら、`gh release create` で GitHub Releases に登録する流れ。
iOS は Bitrise から App Store Connect 経由で TestFlight 配信。

### 1. develop → main を merge

```sh
# develop に積まれた変更で release できる状態になったら
# GitHub UI で develop → main の PR を作成 → "Create a merge commit" で merge
# (Squash / Rebase は無効化済み。Merge commit のみ)

git checkout main && git pull             # merge commit を取り込む
git checkout develop                      # reset 不要 (祖先関係維持)
```

### 2. main で `pubspec.yaml` の version を更新

```yaml
version: 1.2.3+1   # X.Y.Z 部分が tag と一致する必要あり
```

`+N` (build 番号) は CI で `BITRISE_BUILD_NUMBER` に上書きされるので何でもよい
(慣習で `+1` のまま放置)。

```sh
git add pubspec.yaml
git commit -m "v1.2.3 リリース"
git push
```

### 3. tag を打って push

```sh
git tag -a v1.2.3 -m "Release v1.2.3" && git push origin v1.2.3
```

Bitrise が tag push を検知 → `scripts/check-tag-version.sh` で pubspec と
tag の整合性を検証 → flutter build → 署名 → アーティファクト出力。
**version が不一致だと CI が即 fail する** ので、その場合は pubspec を直して
tag を打ち直す (`git tag -d v1.2.3 && git push origin :v1.2.3` で削除してから
再 tag)。

### 4. アーティファクトをダウンロードして GitHub Releases に登録

Bitrise の build 詳細ページから APK / ZIP をダウンロードし、ローカルから
`gh` CLI で release 化:

```sh
gh release create v1.2.3 \
  --title "v1.2.3" \
  --notes "..." \
  ~/Downloads/mimicx_X.Y.Z/MimicX_android-universal-X.Y.Z-bitrise-signed.apk \
  ~/Downloads/mimicx_X.Y.Z/MimicX_macos-X.Y.Z.zip
```

iOS は Bitrise の "Deploy to App Store Connect" / "Deliver" 系ステップが
自動で TestFlight にアップロードする (release notes には別途案内を記載)。

## 関連リポジトリ

- [MimicX-protocol](https://github.com/kunichiko/MimicX-protocol) - MIDI通信プロトコルライブラリ
- [MimicX-firmware](https://github.com/kunichiko/MimicX-firmware) - マイコンファームウェア
- [MimicX-hardware](https://github.com/kunichiko/MimicX-hardware) - 基板設計データ
