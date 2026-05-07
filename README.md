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

### リリース手順

```sh
# 1. develop に最新 commit が積まれている前提
# 2. GitHub UI で develop → main の PR を作成

# 3. PR を "Create a merge commit" で merge
#    (Squash / Rebase は無効化済み。Merge commit のみ)

# 4. ローカルを同期
git checkout main && git pull              # merge commit を取り込む
git checkout develop                       # reset は不要 (祖先関係維持)
```

### コントリビュータ向け

外部からの PR は `develop` を base にしてください (リリース直前の hotfix のみ
`main` を base にして直接 PR でも OK)。

## 関連リポジトリ

- [MimicX-protocol](https://github.com/kunichiko/MimicX-protocol) - MIDI通信プロトコルライブラリ
- [MimicX-firmware](https://github.com/kunichiko/MimicX-firmware) - マイコンファームウェア
- [MimicX-hardware](https://github.com/kunichiko/MimicX-hardware) - 基板設計データ
