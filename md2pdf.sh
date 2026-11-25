#!/usr/bin/env bash
# md2pdf.sh — Markdown → PDF, optionally 2 copies per A4 sheet
set -euo pipefail

TMP_PDF=""
cleanup() {
  [[ -n "${TMP_PDF}" && -f "${TMP_PDF}" ]] && rm -f -- "${TMP_PDF}"
  return 0
}
trap cleanup EXIT

INPUT=""
OUTPUT=""
FONT_SIZE="9pt"
MAIN_FONT="DejaVu Sans"
MONO_FONT="DejaVu Sans Mono"
MARGIN="6mm"
COPIES=1
COLUMNS=1
LINESTRETCH="1.05"
LANDSCAPE=0

usage() {
  cat <<'EOF'
Usage: md2pdf.sh INPUT.md [options]

  -o, --output FILE   output PDF (default: INPUT with .pdf, same dir)
  --copies N          1 or 2 copies per A4 sheet (default 1)
  --landscape         logical page is landscape:
                        copies=1 → A4 landscape (297 x 210)
                        copies=2 → A5 landscape (210 x 148.5) per copy,
                                   two stacked on A4 portrait,
                                   sheet cut horizontally
                      without this flag:
                        copies=1 → A4 portrait
                        copies=2 → A5 portrait per copy, side by side
                                   on A4 landscape, sheet cut vertically
  --columns N         1 or 2 text columns inside each copy (default 1)
  --font-size SIZE    LaTeX font size, e.g. 9pt, 8pt (default 9pt)
  --main-font NAME    main text font (default "DejaVu Sans")
  --mono-font NAME    monospace font (default "DejaVu Sans Mono")
  --margin DIM        page margin, e.g. 6mm (default 6mm)
  --line-stretch X    line spacing multiplier (default 1.05)
  -h, --help          show this help

Requires: pandoc, xelatex (texlive-xetex), pdfinfo (poppler-utils);
          pdfjam (texlive-extra-utils) for --copies 2
EOF
}

if [[ $# -gt 0 && "$1" != -* ]]; then
  INPUT="$1"; shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output)     OUTPUT="$2";       shift 2;;
    --font-size)     FONT_SIZE="$2";    shift 2;;
    --main-font)     MAIN_FONT="$2";    shift 2;;
    --mono-font)     MONO_FONT="$2";    shift 2;;
    --margin)        MARGIN="$2";       shift 2;;
    --copies)        COPIES="$2";       shift 2;;
    --columns)       COLUMNS="$2";      shift 2;;
    --line-stretch)  LINESTRETCH="$2";  shift 2;;
    --landscape)     LANDSCAPE=1;       shift;;
    -h|--help)       usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1;;
  esac
done

[[ -n "$INPUT" ]] || { usage >&2; exit 1; }
[[ -f "$INPUT" ]] || { echo "Error: file not found: $INPUT" >&2; exit 1; }
[[ -z "$OUTPUT" ]] && OUTPUT="${INPUT%.*}.pdf"
[[ "$OUTPUT" == *.pdf ]] || OUTPUT="${OUTPUT}.pdf"

# Logical page geometry
if [[ "$COPIES" == "1" ]]; then
  if [[ "$LANDSCAPE" == "1" ]]; then
    PAPER="paperwidth=297mm,paperheight=210mm"     # A4 landscape
  else
    PAPER="paperwidth=210mm,paperheight=297mm"     # A4 portrait
  fi
elif [[ "$COPIES" == "2" ]]; then
  if [[ "$LANDSCAPE" == "1" ]]; then
    PAPER="paperwidth=210mm,paperheight=148.5mm"   # A5 landscape
  else
    PAPER="paperwidth=148.5mm,paperheight=210mm"   # A5 portrait
  fi
else
  echo "Error: --copies must be 1 or 2" >&2; exit 1
fi

case "$FONT_SIZE" in
  10pt|11pt|12pt) DOC_CLASS="article";;
  *)              DOC_CLASS="extarticle";;
esac

PANDOC_OPTS=(
  "$INPUT"
  --pdf-engine=xelatex
  -V "geometry:${PAPER},margin=${MARGIN}"
  -V "fontsize=${FONT_SIZE}"
  -V "documentclass=${DOC_CLASS}"
  -V "mainfont=${MAIN_FONT}"
  -V "monofont=${MONO_FONT}"
  -V "linestretch=${LINESTRETCH}"
)
[[ "$COLUMNS" == "2" ]] && PANDOC_OPTS+=(-V classoption=twocolumn)

if [[ "$COPIES" == "1" ]]; then
  pandoc "${PANDOC_OPTS[@]}" -o "$OUTPUT"
else
  command -v pdfjam >/dev/null 2>&1 || {
    echo "Error: pdfjam not found. Install: sudo apt install texlive-extra-utils" >&2
    exit 1
  }

  TMP_PDF="$(mktemp --suffix=.pdf)"
  pandoc "${PANDOC_OPTS[@]}" -o "$TMP_PDF"

  if command -v pdfinfo >/dev/null 2>&1; then
    echo "--- pandoc produced ---"
    pdfinfo "$TMP_PDF" | grep -E '^(Pages|Page size|Page rot):'
    SRC_PAGES="$(pdfinfo "$TMP_PDF" | awk '/^Pages:/{print $2}')"
    if [[ "$SRC_PAGES" != "1" ]]; then
      echo "Warning: pandoc made $SRC_PAGES logical pages, expected 1." >&2
      echo "         Check YAML frontmatter (title/author/date) or overflow." >&2
    fi
  fi

  if [[ "$LANDSCAPE" == "1" ]]; then
    # A5 landscape per copy, stacked vertically on A4 portrait
    pdfjam --nup 1x2 --paper a4paper \
           --outfile "$OUTPUT" "$TMP_PDF" "$TMP_PDF"
  else
    # A5 portrait per copy, side by side on A4 landscape
    pdfjam --nup 2x1 --landscape --paper a4paper \
           --outfile "$OUTPUT" "$TMP_PDF" "$TMP_PDF"
  fi

  if command -v pdfinfo >/dev/null 2>&1; then
    echo "--- pdfjam produced ---"
    pdfinfo "$OUTPUT" | grep -E '^(Pages|Page size|Page rot):'
  fi
fi

echo "Wrote $OUTPUT"