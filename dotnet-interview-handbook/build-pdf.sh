#!/usr/bin/env bash
#
# build-pdf.sh
#
# Concatenates README.md + all chapter Markdown files (in order) into
# build/combined.md and converts it into a professionally formatted PDF
# (build/handbook.pdf) using pandoc + wkhtmltopdf.
#
# Run it any time you add, rename, or update chapters:
#     ./build-pdf.sh
#
# Requirements: pandoc and wkhtmltopdf on PATH.
# Debian/Ubuntu: apt-get install -y pandoc wkhtmltopdf
#
# Exit codes: 0 = success, 1 = tool missing, 2 = build failed.

set -euo pipefail

cd "$(dirname "$0")"

BOOK_TITLE="The Complete .NET Interview Handbook"
BUILD_DIR="build"
COMBINED="$BUILD_DIR/combined.md"
HTML_TMP="${TMPDIR:-/tmp}/handbook-$(date +%s).html"
PDF="$BUILD_DIR/handbook.pdf"

die() { echo "ERROR: $*" >&2; exit 1; }

# ---- 1. Check toolchain -----------------------------------------------------
command -v pandoc >/dev/null 2>&1 || die "pandoc not found. Install it: apt-get install -y pandoc"
command -v wkhtmltopdf >/dev/null 2>&1 || die "wkhtmltopdf not found. Install it: apt-get install -y wkhtmltopdf"

# ---- 2. Sanity-check chapter files -----------------------------------------
CHAPTERS=(chapters/*.md)
if [[ ${#CHAPTERS[@]} -lt 1 ]]; then
    die "No Markdown chapter files found under chapters/"
fi
echo "Found ${#CHAPTERS[@]} chapter file(s)."

# ---- 3. Concatenate README + chapters into build/combined.md ----------------
mkdir -p "$BUILD_DIR"
{
    cat README.md
    echo
    for chapter in "${CHAPTERS[@]}"; do
        echo
        cat "$chapter"
        echo
    done
} > "$COMBINED"

echo "Wrote $COMBINED ($(wc -l < "$COMBINED") lines)."

# ---- 4. Markdown -> standalone HTML -----------------------------------------
# Wrap pdf-style.css in <style> and inline via --include-in-header so
# pandoc's default narrow body (max-width: 36em) is overridden for
# full-page-width content.
HEADER_TMP="${TMPDIR:-/tmp}/handbook-header-$(date +%s).html"
{
    echo "<style>"
    cat pdf-style.css
    echo "</style>"
} > "$HEADER_TMP"

pandoc "$COMBINED" \
    -f markdown \
    -t html5 \
    -s \
    --metadata title="$BOOK_TITLE" \
    --include-in-header="$HEADER_TMP" \
    -o "$HTML_TMP"
rm -f "$HEADER_TMP"
echo "Converted Markdown to HTML."

# ---- 5. HTML -> PDF ----------------------------------------------------------
wkhtmltopdf \
    --enable-local-file-access \
    --margin-top 18mm \
    --margin-bottom 18mm \
    --margin-left 16mm \
    --margin-right 16mm \
    "$HTML_TMP" \
    "$PDF" >/dev/null 2>&1

rm -f "$HTML_TMP"

echo "Done. PDF written to $PDF"
