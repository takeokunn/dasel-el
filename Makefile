EMACS ?= emacs
BATCH = $(EMACS) -Q --batch

LOAD_PATH = -L . -L test
SRC = dasel.el dasel-interactive.el dasel-convert.el dasel-format.el dasel-edit.el
CONSULT_SRC = consult-dasel.el
TEST_SRC = $(wildcard test/*-test.el)

PACKAGE_INIT = --eval "(progn (require 'package) (push '(\"melpa\" . \"https://melpa.org/packages/\") package-archives) (package-initialize))"

.PHONY: all compile compile-consult test lint lint-consult package-lint package-lint-consult clean

all: compile

compile:
	$(BATCH) $(LOAD_PATH) \
	  --eval "(setq byte-compile-error-on-warn t)" \
	  $(foreach f,$(SRC),--eval "(byte-compile-file \"$(f)\")")

test:
	$(BATCH) $(LOAD_PATH) \
	  -l test/dasel-test-helpers.el \
	  $(foreach f,$(TEST_SRC),-l $(f)) \
	  -f ert-run-tests-batch-and-exit

lint:
	$(BATCH) $(LOAD_PATH) \
	  $(foreach f,$(SRC),--eval "(checkdoc-file \"$(f)\")")

package-lint:
	$(BATCH) $(LOAD_PATH) \
	  --eval "(progn (require 'package) (push '(\"melpa\" . \"https://melpa.org/packages/\") package-archives) (package-initialize) (package-refresh-contents) (package-install 'package-lint))" \
	  -l package-lint \
	  -f package-lint-batch-and-exit $(SRC)

compile-consult:
	$(BATCH) $(LOAD_PATH) \
	  $(PACKAGE_INIT) \
	  --eval "(setq byte-compile-error-on-warn t)" \
	  $(foreach f,$(CONSULT_SRC),--eval "(byte-compile-file \"$(f)\")")

lint-consult:
	$(BATCH) $(LOAD_PATH) \
	  $(PACKAGE_INIT) \
	  $(foreach f,$(CONSULT_SRC),--eval "(checkdoc-file \"$(f)\")")

package-lint-consult:
	$(BATCH) $(LOAD_PATH) \
	  --eval "(progn (require 'package) (push '(\"melpa\" . \"https://melpa.org/packages/\") package-archives) (package-initialize) (package-refresh-contents) (package-install 'package-lint) (package-install-file (expand-file-name \"dasel.el\")))" \
	  -l package-lint \
	  -f package-lint-batch-and-exit $(CONSULT_SRC)

clean:
	rm -f *.elc test/*.elc
