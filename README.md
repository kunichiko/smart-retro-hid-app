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

## 関連リポジトリ

- [MimicX-protocol](https://github.com/kunichiko/MimicX-protocol) - MIDI通信プロトコルライブラリ
- [MimicX-firmware](https://github.com/kunichiko/MimicX-firmware) - マイコンファームウェア
- [MimicX-hardware](https://github.com/kunichiko/MimicX-hardware) - 基板設計データ
