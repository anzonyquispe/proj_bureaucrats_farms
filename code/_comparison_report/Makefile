# Build the comparison report PDF.
#
# Usage:
#   make           -- runs pdflatex twice (resolves \ref and TOC)
#   make once      -- single pdflatex pass
#   make open      -- macOS: open the PDF
#   make clean     -- remove .aux/.log/.out
#   make distclean -- also remove the PDF

TEX := comparison_report.tex
PDF := comparison_report.pdf

.PHONY: all once open clean distclean

all: $(PDF)

$(PDF): $(TEX)
	pdflatex -interaction=nonstopmode $(TEX)
	pdflatex -interaction=nonstopmode $(TEX)

once:
	pdflatex -interaction=nonstopmode $(TEX)

open: $(PDF)
	open $(PDF)

clean:
	rm -f *.aux *.log *.out *.toc

distclean: clean
	rm -f $(PDF)
