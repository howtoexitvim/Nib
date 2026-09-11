<div align="center">

# Nib

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

![Platform](https://img.shields.io/badge/platform-macOS-111827?logo=apple&logoColor=white)
![Type](https://img.shields.io/badge/type-Markdown%20Editor-2563eb)
![Size](https://img.shields.io/badge/size-1.4MB-059669)

</div>

Nib は macOS 向けのミニマルな Markdown エディタです。ネイティブな Swift のシェルが 1 つの WKWebView を包み、その中で CodeMirror 6 が動いています。

**ghost writing** を備えています。文末、改行、新しいリスト項目といった意味的な区切りで、自分で設定した LLM が続きをグレーで提案します。Tab で受け入れ、Esc で無視。プロバイダーは自分で設定するもので、内蔵のモデルはありません。

API キーは Keychain に保存され、リクエストは Swift 側から送られるため、キーが JavaScript のコンテキストに入ることはありません。

## インストール

[releases ページ](https://github.com/howtoexitvim/Nib/releases)から zip をダウンロードし、展開して `Nib.app` を `/Applications` にドラッグしてください。ビルドは ad-hoc 署名で notarize されていないため、一度だけ quarantine フラグを外す必要があります。

```bash
xattr -dr com.apple.quarantine /Applications/Nib.app
```

Apple シリコン（arm64）のみ対応です。最新リリースは **v0.1.0**。

ソースからビルドすることもできます。必要なのは Swift ツールチェインと Node だけです。

## ビルド

```bash
make        # web バンドルと build/Nib.app をビルド
make run    # ビルドして起動
make test   # Swift テスト + JS テスト
make clean
```

Xcode プロジェクトはありません。`swift build` がバイナリを生成し、Makefile が `.app` を手作業で組み立てるので、すべてコマンドラインで再現できます。

成果物は約 **1.4MB** です（Typora は 46MB、Electron アプリは通常 150-250MB）。

## 2 つのモード

ソースモードは CodeMirror、プレビューモードは読み取り専用のレンダリングです。**ソースだけが真実であり、プレビューはその投影です。** `Cmd+/` で切り替えます。ショートカットは window にバインドされているため、どちらのモードでも効きます。

プレビューは編集不可で入力も処理しないため、プレビューモードでは ghost text が発火する**コードパスそのものが存在しません**。`if` で止めているのではなく、構造上そうなっています。

## Ghost writing

- **意味的な区切り**でのみ発火します（文末、節の終わり、改行、新しいリスト項目）。キーを打つたびではありません。全角の句読点も対象です。
- 削除・取り消し・やり直し・マルチカーソル・選択範囲があるときは発火しません。
- 500ms のデバウンス、前後それぞれ 4000 文字のコンテキスト（fill-in-the-middle）、`(prefix, suffix)` をキーにキャッシュします。
- Tab で受け入れ、Esc で無視。そのまま打ち続けた内容が提案と一致していれば、提案は保持されて先へ進みます。

## 補完サービスの設定

設定には 4 つの項目があります。Provider、Base URL、Model、API キーです。

公式 API を使う場合は Anthropic か OpenAI を選び、Base URL はデフォルトのままにします。

セルフホストの OpenAI 互換サーバー（vLLM、Ollama、LM Studio）を使う場合は **OpenAI** を選び、Base URL を自分のエンドポイントに向けます（例: `http://127.0.0.1:8000/v1`）。サーバーに認証がなければキーは空のままで構いません。認証がある場合はキーが必須で、なければ `Unauthorized` が返ります。

**reasoning 対応モデルについての注意。** vLLM を `--reasoning-parser` 付きで動かすと、思考の連鎖が `reasoning` フィールドに入り、`content` は `null` で返ってきます。短い補完のトークン予算がすべて思考に使われてしまい、ghost text には何も届きません。そのためリクエストボディには常に `chat_template_kwargs: {"enable_thinking": false}` を含めています。公式の OpenAI API は未知のトップレベルフィールドを無視するので、そちらでは無害です。

対応するプロトコルは **Anthropic** と **OpenAI** の 2 つだけです。後者は vLLM、Ollama、LM Studio が公開しているインターフェースそのものなので、ローカルモデルのために追加のコードは要りません。base URL をそちらへ向けるだけです。

## 設計メモ

**1 ウィンドウ、1 WebView。** `WKWebView` はそれぞれ独立した content process（30-60MB）です。ファイルごとにウィンドウを開く方式では、数百ファイルのノート庫に耐えられません。そのためファイルの切り替えは中身の差し替えで行います。

**ファイル切り替えでは transaction を dispatch せず `EditorState` を作り直します。** transaction は undo history を保持するため、A から B へ切り替えたあとに `Cmd+Z` を押すと A のテキストが B に入り込み、次の保存で B が壊れます。代償としてファイルをまたぐ undo はありません。

**ファイルツリーは遅延読み込みです。** 実際のノートディレクトリ（6,165 フォルダ / 1,599 個の `.md`）を完全に再帰走査すると実測 0.81 秒で、ウィンドウを開く経路に置くと目に見える引っかかりになります。1 階層だけ読むなら 2ms です。

**貼り付けた画像は `<ドキュメント名>.assets/` に書き込まれ**（Typora の慣習）、相対パスでリンクされます。フォルダごと移動・同期・共有してもリンクは解決したままです。種類はクリップボードの申告ではなく**バイト列**から判別します。両者は一致しないことが少なくなく、拡張子が実際の内容と合っていなければ何も表示されないからです。macOS のスクリーンショットは TIFF で届くので PNG に変換します。

プレビュー内の画像は `nib-asset://` 経由で、Swift がバイト列を読みます。そうしなければ相対パスは bundle を基準に解決されてしまい、しかもページの読み取り権限は bundle の `web/` にしか及びません。`<base>` タグは選択肢になりません。`./editor.css` と `./editor.js` まで書き換えてしまい、アプリがそもそも開かなくなります。リクエストはドキュメント自身のディレクトリ内に限定しています。リンクはページの内容であり、ページの内容は信用できないからです。

## テスト

```
swift test           81 件
cd web && npm test   75 件
```

Swift 側はレスポンスのクリーンアップ、エンドポイントの組み立て、ファイルの可視性と並び順、`.assets` パスの導出、リネーム／新規作成時の名前検証、画像の型判別と名前衝突、`nib-asset://` のパストラバーサル拒否、外観設定のラウンドトリップ、ファイル横断検索をカバーします。

JS 側は ghost text のトリガールール（全角句読点や誤発火の防止を含む）、文字数カウント（CJK は文字単位、コードは除外）、画像パスの書き換え、書式整形の文字列変換、アウトライン解析をカバーします。

`wordcount.js`、`format.js`、`outline.js`、`preview.js` は CodeMirror に依存しないので、テストは実装そのものを import します。`ghost.js` は CM の拡張なのでそれができず、代わりにルールが一致しているかを確認するテストを 1 本置き、ドキュメントと実装の乖離を防いでいます。

## プロジェクト

プロジェクトホーム: https://github.com/howtoexitvim/Nib

## License

[MIT](LICENSE)
