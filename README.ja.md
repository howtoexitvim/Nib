<div align="center">

# Nib

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

![Platform](https://img.shields.io/badge/platform-macOS-111827?logo=apple&logoColor=white)
![Type](https://img.shields.io/badge/type-Markdown%20Editor-2563eb)
![Size](https://img.shields.io/badge/size-1.4MB-059669)

</div>

Nib は macOS 向けのミニマルな Markdown エディタです。サイズは**およそ 1.4MB** —— Typora は 46MB、Electron 製エディタは通常 150-250MB あります。

中身は CodeMirror 6 を包んだネイティブ Swift のシェルです。すぐ開き、邪魔をせず、小さなエディタには珍しい機能をひとつ備えています。ゴーストライティングです。

意味の切れ目 —— 文の終わり、改行、新しいリスト項目 —— で、あなた自身の LLM が灰色の続きを提案します。Tab で採用、Esc で却下。キーを打つたびに出ることはなく、削除中・取り消し中・選択範囲があるときには決して現れません。

```
やかんはもうしばらく火にかけたままで、
                                      ▏窓は白く曇っていた。   ← Tab で採用
```

モデルは内蔵していません。自分のモデルを使い、キーはキーチェーンから出ません。

## Nib を選ぶ理由

- 🪶 **1.4MB**：タイトルバー付きのブラウザではなく、本物のネイティブアプリ。
- ✍️ **ゴーストライティング**：単語の途中ではなく、考えが一区切りついた場所に提案が現れます。
- 🔌 **自分のモデル**：Anthropic と OpenAI のプロトコルに対応 —— Base URL を向けるだけで、セルフホストの vLLM・Ollama・LM Studio も使えます。
- 🔒 **キーはキーチェーンに**：リクエストは Swift から送られるため、キーが JavaScript 側に入ることはありません。
- 📄 **2 つのモード**：ソースとプレビューを `Cmd+/` で切り替え。プレビューでは構造上ゴーストライティングが発火しません。
- 🖼️ **移動しても壊れない画像**：貼り付けた画像はファイルの隣の `<document>.assets/` に保存され、相対リンクで参照されます。フォルダごと移動・同期してもリンクは有効なままです。
- 🗂️ **サイドバー**：ファイルツリー、アウトライン、ファイル横断検索。
- 🆓 **無料・MIT ライセンス**。

<!-- TODO: add screenshots of the editor, ghost text in action, and Settings -->

## インストール

[リリースページ](https://github.com/howtoexitvim/Nib/releases)から zip をダウンロードし（現在のリリースは **v0.1.0**）、展開して `Nib.app` を `/Applications` にドラッグしてください。

このビルドは ad-hoc 署名で、公証は受けていません。そのため一度だけ隔離フラグを解除します:

```bash
xattr -dr com.apple.quarantine /Applications/Nib.app
```

Apple シリコンのみ対応です。

## 補完の設定

設定項目は 4 つです: Provider、Base URL、Model、API key。

公式 API を使う場合は Anthropic か OpenAI を選び、Base URL は既定のままにします。セルフホストの OpenAI 互換サーバーを使う場合は OpenAI を選び、Base URL を自分のエンドポイント（例: `http://127.0.0.1:8000/v1`）に向けてください。認証のないサーバーならキーは空欄で構いません。

リクエストには `chat_template_kwargs: {"enable_thinking": false}` が含まれるため、reasoning parser を使うモデルでも補完が返ってきます。

## ビルド

```bash
make        # web バンドルと build/Nib.app をビルド
make run    # ビルドして起動
make test   # Swift テスト + JS テスト
```

Xcode プロジェクトは不要です —— Swift ツールチェーンと Node があれば足ります。テストは Swift が 81 件、JS が 75 件です。

## プロジェクト

プロジェクトホーム: https://github.com/howtoexitvim/Nib

## License

[MIT](LICENSE)
