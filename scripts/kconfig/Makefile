# SPDX-License-Identifier: GPL-2.0
#
# OP-TEE Kconfig host tools — standalone Makefile (no Kbuild).
#
# Builds the kconfig host tools (conf, mconf, nconf).  All configuration
# front-end targets (defconfig, menuconfig, …) live in the top-level Makefile,
# which invokes the binaries directly.
#
# Invoke from the top-level Makefile as:
#   $(MAKE) -C <out>/scripts/kconfig \
#       -f <srctree>/scripts/kconfig/Makefile \
#       conf|mconf|nconf|clean
#
# SRC is derived from the -f path recorded in $(MAKEFILE_LIST), so no
# external variable needs to be passed by the caller.  All source files are
# referenced via $(SRC)/; generated intermediates (lexer.lex.c, parser.tab.*)
# and the final binaries land in the build directory.

HOSTCC      ?= gcc
HOSTCXX     ?= g++
HOSTCFLAGS  ?= -Wall -Wstrict-prototypes -O2 -fomit-frame-pointer -DKBUILD_NO_NLS

# The directory containing this Makefile is the kconfig source directory.
# $(MAKEFILE_LIST) holds the absolute -f path supplied by the top-level make.
SRC := $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))

# -I. finds generated headers (parser.tab.h) in the build directory.
# -I$(SRC) finds the static headers (lkc.h, expr.h, …) in the source tree.
HOSTCFLAGS  += -I. -I$(SRC)

Q := $(if $(filter 1,$(V)),,@)

# ---------------------------------------------------------------------------
# Generated parser / lexer sources (written into the build directory)
# ---------------------------------------------------------------------------
lexer.lex.c: $(SRC)/lexer.l
	$(Q)flex -o $@ $<

parser.tab.c parser.tab.h: $(SRC)/parser.y
	$(Q)bison --debug -o parser.tab.c --defines=parser.tab.h $<

# ---------------------------------------------------------------------------
# Shared sources (no main — used by conf, mconf, and nconf)
# ---------------------------------------------------------------------------
SHARED_SRCS := \
	$(SRC)/confdata.c \
	$(SRC)/expr.c \
	$(SRC)/menu.c \
	$(SRC)/preprocess.c \
	$(SRC)/symbol.c \
	$(SRC)/util.c \
	lexer.lex.c \
	parser.tab.c

# ---------------------------------------------------------------------------
# conf — the command-line configuration tool
# ---------------------------------------------------------------------------
CONF_SRCS := $(SRC)/conf.c $(SHARED_SRCS)

conf: $(CONF_SRCS) parser.tab.h
	$(Q)$(HOSTCC) $(HOSTCFLAGS) -o $@ $(filter %.c,$^)

# ---------------------------------------------------------------------------
# mconf — ncurses menuconfig front-end
# ---------------------------------------------------------------------------
LXDIALOG_SRCS := \
	$(SRC)/lxdialog/checklist.c \
	$(SRC)/lxdialog/inputbox.c \
	$(SRC)/lxdialog/menubox.c \
	$(SRC)/lxdialog/textbox.c \
	$(SRC)/lxdialog/util.c \
	$(SRC)/lxdialog/yesno.c

MCONF_SRCS := $(SRC)/mconf.c $(SHARED_SRCS) $(LXDIALOG_SRCS)

# mconf-cfg.sh prints shell assignment syntax (cflags="..." libs="...").
# Eval the output so $cflags/$libs are set, then use them directly.
mconf: $(MCONF_SRCS) parser.tab.h
	$(Q)eval $$(sh $(SRC)/mconf-cfg.sh) && \
		$(HOSTCC) $(HOSTCFLAGS) $$cflags \
		-o $@ $(filter %.c,$^) $$libs

# ---------------------------------------------------------------------------
# nconf — ncurses-based TUI
# ---------------------------------------------------------------------------
NCONF_SRCS := $(SRC)/nconf.c $(SRC)/nconf.gui.c $(SHARED_SRCS)

nconf: $(NCONF_SRCS) parser.tab.h
	$(Q)eval $$(sh $(SRC)/nconf-cfg.sh) && \
		$(HOSTCC) $(HOSTCFLAGS) $$cflags \
		-o $@ $(filter %.c,$^) $$libs

# ---------------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------------
.PHONY: clean
clean:
	$(Q)rm -f conf mconf nconf
	$(Q)rm -f lexer.lex.c parser.tab.c parser.tab.h
	$(Q)rm -f *.o lxdialog/*.o
