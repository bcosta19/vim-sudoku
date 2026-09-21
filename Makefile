# vim-sudoku — dev tasks.
#
# The qmltestrunner/qmllint found first in PATH may be the Qt5 build, whose
# test runner exits silently. Point at the Qt6 tools explicitly; override with
# `make test QMLTESTRUNNER=...` if yours live somewhere else.
QT6_BIN ?= /usr/lib/qt6/bin
QMLTESTRUNNER ?= $(QT6_BIN)/qmltestrunner
QMLLINT ?= $(QT6_BIN)/qmllint

PLUGIN_ID ?= bcosta19.vim-sudoku
PLUGINS_DIR ?= $(HOME)/.config/omarchy/plugins
QML_FILES := SudokuPanel.qml shell.qml qml/SudokuWindow.qml tests/tst_game.qml

.PHONY: run test lint validate install uninstall clean

run:
	./vim-sudoku

test:
	QT_QPA_PLATFORM=offscreen $(QMLTESTRUNNER) -input tests -o -,txt

lint:
	@for f in $(QML_FILES); do echo "qmllint $$f"; $(QMLLINT) "$$f" || exit 1; done

validate:
	omarchy plugin validate .

# Development install: symlink the working copy into the shell's plugin
# directory and let the shell pick it up. Enable it with:
#   omarchy plugin enable $(PLUGIN_ID)
install:
	mkdir -p $(PLUGINS_DIR)
	ln -sfn "$(CURDIR)" "$(PLUGINS_DIR)/$(PLUGIN_ID)"
	omarchy-shell shell rescanPlugins || true
	@echo "Linked $(PLUGINS_DIR)/$(PLUGIN_ID) -> $(CURDIR)"
	@echo "Enable it with: omarchy plugin enable $(PLUGIN_ID)"

uninstall:
	-omarchy plugin disable $(PLUGIN_ID)
	rm -f "$(PLUGINS_DIR)/$(PLUGIN_ID)"
	omarchy-shell shell rescanPlugins || true

clean:
	rm -rf .qmlcache
