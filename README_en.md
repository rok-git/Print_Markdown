# Print Markdown

A macOS CLI tool that formats Markdown notes, meeting minutes, and procedure documents into readable PDFs, and prints them only when requested. It also includes a helper script for using fixed settings from a Finder Quick Action.

## Features

- Formats Markdown into print-friendly PDF output
- Supports headings, paragraphs, bullet lists, numbered lists, blockquotes, code blocks, tables, images, and links
- Images inside Markdown table cells are not currently supported
- `clean`, `serif`, and `compact` themes
- A4, Letter, and B5 paper sizes with portrait or landscape orientation
- `n/m` page numbers on multi-page PDFs
- Save PDFs only, or send them to a printer
- Pass printer names and printer-specific options to macOS `lp`
- Use a config file through the Finder Quick Action helper script

## Requirements

- macOS
- Swift 5.9 or later
- `lp` command

PDF generation uses macOS AppKit, Core Text, and Quartz.

## Build

```sh
swift build
```

If SwiftPM cannot create its module cache because of sandboxing or permissions, point the cache into the project directory.

```sh
env CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift build
```

## Install

For daily use, build the release executable and copy it somewhere in your `PATH`.

```sh
swift build -c release
mkdir -p ~/bin
cp .build/release/print-markdown ~/bin/
```

If you want to use it from a Finder Quick Action, copy the helper script as well.

```sh
cp scripts/print-markdown-finder.sh ~/bin/print-markdown-finder.sh
chmod +x ~/bin/print-markdown-finder.sh
```

## Usage

Save a PDF:

```sh
swift run print-markdown input.md --output output.pdf
```

Create `input.formatted.pdf` automatically from the input filename:

```sh
swift run print-markdown input.md --output-dir ~/Desktop
```

Print a Markdown file:

```sh
swift run print-markdown input.md --print
```

Create the PDF without printing it:

```sh
swift run print-markdown input.md --output output.pdf --dry-run
```

Print in monochrome, one-sided mode:

```sh
swift run print-markdown input.md \
  --print \
  --color monochrome \
  --sides one-sided
```

Pass printer-specific `lp` options:

```sh
swift run print-markdown input.md \
  --print \
  --print-option ARCMode=CMBW \
  --print-option media=A4
```

## Options

- `--output PATH`: Save the formatted PDF at `PATH`
- `--output-dir DIR`: Save as `DIR/input.formatted.pdf`
- `--print`: Send the formatted PDF to `lp`
- `--printer NAME`: Printer name passed to `lp -d`
- `--print-option OPTION`: Printer option passed as `lp -o OPTION`; repeatable
- `--color MODE`: `auto`, `color`, `monochrome`
- `--sides MODE`: `auto`, `one-sided`, `two-sided-long-edge`, `two-sided-short-edge`
- `--paper SIZE`: `A4`, `Letter`, `B5`
- `--orientation MODE`: `portrait`, `landscape`
- `--theme NAME`: `clean`, `serif`, `compact`
- `--font-size POINTS`: Base font size
- `--margin POINTS`: Page margin
- `--no-page-numbers`: Omit page numbers from multi-page PDFs
- `--title TEXT`: Title used in generated HTML metadata
- `--keep-html PATH`: Also save the generated HTML
- `--dry-run`: Create the PDF without printing it
- `--help`: Show help

`--output` and `--output-dir` only choose where to save the PDF. Printing happens only when `--print` is specified.

## Config File

The `print-markdown` command itself does not read config files. The Finder Quick Action helper script, `scripts/print-markdown-finder.sh`, reads a config file and passes the configured options to `print-markdown`.

For example, place a config file at `~/.config/print-markdown/options`.

```sh
mkdir -p ~/.config/print-markdown
cp examples/options.conf ~/.config/print-markdown/options
```

The config file can contain the same options you would pass to the CLI. Empty lines and lines starting with `#` are ignored. Quoted values are supported.

```sh
--theme clean
--paper A4
--font-size 13
--margin 46
--print
--print-option ARCMode=CMBW
--sides one-sided
```

If `--print` is included in the config file, running the Finder Quick Action will print the generated PDF. To avoid accidental printing during ordinary CLI use, config files are read only by the helper script.

To switch settings based on modifier keys, create the following files. Each file should contain the full set of options for that mode. The contents of `options` are not merged.

```text
~/.config/print-markdown/options          # No modifier key
~/.config/print-markdown/options.option   # Option
~/.config/print-markdown/options.shift    # Shift
~/.config/print-markdown/options.control  # Control
~/.config/print-markdown/options.command  # Command
```

When multiple modifier keys are pressed, the helper uses the first matching config file in this order: `option`, `shift`, `control`, `command`. If no matching modifier config exists, it falls back to `options`.

## Finder Quick Action

Here is one way to convert or print selected Markdown files from Finder with fixed settings.

1. Install `print-markdown`.
2. Create `~/.config/print-markdown/options`.
3. Copy `scripts/print-markdown-finder.sh` to a location such as `~/bin/print-markdown-finder.sh`.
4. Open Automator and create a new Quick Action.
5. Set "Workflow receives current" to "files or folders" and "in" to "Finder.app".
6. Add "Run Shell Script" and set "Pass input" to "as arguments".
7. Enter the following script.

```sh
~/bin/print-markdown-finder.sh "$@"
```

Automator may use a different `PATH` from your normal terminal. If the command cannot be found, set `PRINT_MARKDOWN_COMMAND` to the absolute path of `print-markdown`.

## Printer Options

You can inspect printer-specific options from the macOS terminal.

```sh
lpoptions -p "Printer Name" -l
```

`--color monochrome` passes `print-color-mode=monochrome` and `ColorModel=Gray` to `lp`. Some printers use different option keys. If needed, use `lpoptions -p "Printer Name" -l` and pass the appropriate monochrome option with `--print-option`.

## Notes

- This tool formats Markdown into PDFs and optionally prints them.
- It is not a strict implementation of the entire CommonMark spec. It is a dependency-free practical subset for common business notes and meeting minutes.
- If image syntax such as `![alt](path)` appears inside a table cell, it is not currently rendered as an image in the table. Put images outside tables as standalone Markdown images.
- Printing happens only when `--print` is specified.

## License

MIT License.
