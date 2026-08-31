# Print Markdown

Markdown で書いたメモ、議事録、手順書を、読みやすい PDF に整えてから必要な場合だけ印刷する macOS 向け CLI ツールです。Finder のクイックアクションから固定設定で使える補助スクリプトも入っています。

## Features

- Markdown を印刷向けの HTML/CSS で整形して PDF 化
- 見出し、段落、箇条書き、番号付きリスト、引用、コードブロック、表、画像、リンクに対応
- `clean`, `serif`, `compact` のテーマ
- A4, Letter, B5 と縦横指定
- PDF の保存だけ、または印刷まで実行
- macOS の `lp` にプリンタ名や印刷オプションを渡せる
- Finder クイックアクション用スクリプトで設定ファイルを読み込んで実行可能

## Requirements

- macOS
- Swift 5.9 以降
- `lp` コマンド

PDF 生成には macOS 標準の AppKit/Core Text/Quartz を使います。

## Build

```sh
swift build
```

sandbox や権限の都合で SwiftPM のモジュールキャッシュ作成に失敗する場合は、キャッシュをプロジェクト内へ向けます。

```sh
env CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift build
```

## Install

日常的に使う場合は、release ビルドした実行ファイルを `PATH` の通った場所へコピーします。

```sh
swift build -c release
mkdir -p ~/bin
cp .build/release/print-markdown ~/bin/
```

Finder クイックアクションから使う場合は、補助スクリプトもコピーしておくと便利です。

```sh
cp scripts/print-markdown-finder.sh ~/bin/print-markdown-finder.sh
chmod +x ~/bin/print-markdown-finder.sh
```

## Usage

PDF を保存する:

```sh
swift run print-markdown input.md --output output.pdf
```

ファイル名から自動で `input.formatted.pdf` を作る:

```sh
swift run print-markdown input.md --output-dir ~/Desktop
```

印刷する:

```sh
swift run print-markdown input.md --print
```

印刷せずに生成結果だけ確認する:

```sh
swift run print-markdown input.md --output output.pdf --dry-run
```

白黒・片面で印刷する:

```sh
swift run print-markdown input.md \
  --print \
  --color monochrome \
  --sides one-sided
```

プリンタ固有の `lp` オプションを渡す:

```sh
swift run print-markdown input.md \
  --print \
  --print-option ARCMode=CMBW \
  --print-option media=A4
```

## Options

- `--output PATH`: 整形済み PDF の保存先
- `--output-dir DIR`: `DIR/入力ファイル名.formatted.pdf` として保存
- `--print`: 整形済み PDF を `lp` に渡して印刷する
- `--printer NAME`: `lp -d` に渡すプリンタ名
- `--print-option OPTION`: `lp -o OPTION` として渡す印刷オプション。複数指定可
- `--color MODE`: `auto`, `color`, `monochrome`
- `--sides MODE`: `auto`, `one-sided`, `two-sided-long-edge`, `two-sided-short-edge`
- `--paper SIZE`: `A4`, `Letter`, `B5`
- `--orientation MODE`: `portrait`, `landscape`
- `--theme NAME`: `clean`, `serif`, `compact`
- `--font-size POINTS`: 基本文字サイズ
- `--margin POINTS`: ページ余白
- `--title TEXT`: PDF 内 HTML のタイトル
- `--keep-html PATH`: 生成した HTML も保存
- `--dry-run`: PDF を作るだけで印刷しない
- `--help`: ヘルプを表示

`--output` と `--output-dir` は保存先の指定です。印刷は `--print` を指定した場合だけ実行されます。

## Config File

`print-markdown` 本体は設定ファイルを読みません。Finder クイックアクション用の `scripts/print-markdown-finder.sh` が設定ファイルを読み込み、そこに書いたオプションを `print-markdown` に渡します。

設定ファイルは、例えば `~/.config/print-markdown/options` に置きます。

```sh
mkdir -p ~/.config/print-markdown
cp examples/options.conf ~/.config/print-markdown/options
```

設定ファイルには CLI に渡すオプションをそのまま書けます。空行と `#` で始まる行は無視されます。引用符つきの値も使えます。

```sh
--theme clean
--paper A4
--font-size 13
--margin 46
--print
--print-option ARCMode=CMBW
--sides one-sided
```

`--print` を設定ファイルに入れると、Finder クイックアクションからの実行は印刷まで進みます。通常の CLI 操作で意図せず印刷しないよう、設定ファイルの読み込みは補助スクリプト側だけで行います。

修飾キーごとに設定を切り替えたい場合は、次のファイルを作成します。それぞれのファイルには、そのモードで使うオプションをフルセットで書いてください。`options` の内容はマージされません。

```text
~/.config/print-markdown/options          # 修飾キーなし
~/.config/print-markdown/options.option   # Option
~/.config/print-markdown/options.shift    # Shift
~/.config/print-markdown/options.control  # Control
~/.config/print-markdown/options.command  # Command
```

複数の修飾キーが押されている場合は、`option`, `shift`, `control`, `command` の順に最初に見つかった設定ファイルを使います。対応する設定ファイルがない場合は `options` を使います。

## Finder Quick Action

Finder で Markdown ファイルを選び、クイックアクションから固定設定で PDF 化または印刷する場合の一例です。

1. `print-markdown` をインストールします。
2. `~/.config/print-markdown/options` を作成します。
3. `scripts/print-markdown-finder.sh` を `~/bin/print-markdown-finder.sh` などへコピーします。
4. Automator で「クイックアクション」を新規作成します。
5. 「ワークフローが受け取る現在の項目」を「ファイルまたはフォルダ」、「検索対象」を「Finder.app」にします。
6. 「シェルスクリプトを実行」を追加し、「入力の引き渡し方法」を「引数として」にします。
7. スクリプト欄に次を入れます。

```sh
~/bin/print-markdown-finder.sh "$@"
```

Automator では `PATH` が普段のターミナルと違うことがあります。うまく見つからない場合は、`PRINT_MARKDOWN_COMMAND` に `print-markdown` の絶対パスを指定してください。

## Printer Options

プリンタが対応している詳細オプションは macOS のターミナルで確認できます。

```sh
lpoptions -p "Printer Name" -l
```

`--color monochrome` は `print-color-mode=monochrome` と `ColorModel=Gray` を `lp` に渡します。プリンタによっては別のキーが必要なため、その場合は `lpoptions -p "Printer Name" -l` の出力にある白黒指定を `--print-option` で渡してください。

## Notes

- このツールは Markdown を整形して PDF 化し、必要なら印刷するためのものです。
- CommonMark 全体を厳密に実装するものではありません。業務メモや議事録でよく使う Markdown 記法を扱う、依存なしの実用サブセットです。
- 印刷は `--print` を指定した場合だけ実行されます。

## License

MIT License.
