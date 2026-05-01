# smart-retro-hid-app

スマートフォン（iOS/Android）からUSB-MIDI経由でマイコンを制御し、レトロPCのHIDデバイス（キーボード・マウス・ジョイスティック）を模倣するFlutterアプリ。

## 機能

- ジョイスティックモード: 画面上の仮想ジョイスティックで操作
- キーボードモード: レトロPCのキーボードレイアウトを再現し、タイプ入力が可能
- レトロPC本体からの信号受信（キーボードLED制御など）に対応

## 関連リポジトリ

- [smart-retro-hid-protocol](../smart-retro-hid-protocol) - MIDI通信プロトコルライブラリ
- [smart-retro-hid-firmware](../smart-retro-hid-firmware) - マイコンファームウェア
- [smart-retro-hid-hardware](../smart-retro-hid-hardware) - 基板設計データ
