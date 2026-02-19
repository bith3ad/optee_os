SHELL = bash

# It can happen that a makefile calls us, which contains an 'export' directive
# or the '.EXPORT_ALL_VARIABLES:' special target. In this case, all the make
# variables are added to the environment for each line of the recipes, so that
# any sub-makefile can use them.
# We have observed this can cause issues such as 'Argument list too long'
# errors as the shell runs out of memory.
# Since this Makefile won't call any sub-makefiles, and since the commands do
# not expect to implicitely obtain any make variable from the environment, we
# can safely cancel this export mechanism. Unfortunately, it can't be done
# globally, only by name. Let's unexport MAKEFILE_LIST which is by far the
# biggest one due to our way of tracking dependencies and compile flags
# (we include many *.cmd and *.d files).
unexport MAKEFILE_LIST

# Automatically delete corrupt targets (file updated but recipe exits with a
# nonzero status). Useful since a few recipes use shell redirection.
.DELETE_ON_ERROR:

include mk/macros.mk
include mk/checkconf.mk

.PHONY: all
all:

.PHONY: mem_usage
mem_usage:

# log and load eventual tee config file
# path is absolute or relative to current source root directory.
ifdef CFG_OPTEE_CONFIG
$(info Loading OPTEE configuration file $(CFG_OPTEE_CONFIG))
include $(CFG_OPTEE_CONFIG)
endif

# If $(PLATFORM) is defined and contains a hyphen, parse it as
# $(PLATFORM)-$(PLATFORM_FLAVOR) for convenience
ifneq (,$(findstring -,$(PLATFORM)))
ops := $(join PLATFORM PLATFORM_FLAVOR,$(addprefix =,$(subst -, ,$(PLATFORM))))
$(foreach op,$(ops),$(eval override $(op)))
endif

# Make these default for now
ARCH            ?= arm
PLATFORM        ?= vexpress
# Default value for PLATFORM_FLAVOR is set in plat-$(PLATFORM)/conf.mk
ifeq ($O,)
O               := out
out-dir         := $(O)/$(ARCH)-plat-$(PLATFORM)
else
out-dir         := $(O)
endif

arch_$(ARCH)	:= y

ifneq ($V,1)
q := @
cmd-echo := true
cmd-echo-silent := echo
else
q :=
cmd-echo := echo
cmd-echo-silent := true
endif

ifneq ($(filter 4.%,$(MAKE_VERSION)),)  # make-4
ifneq ($(filter %s ,$(firstword x$(MAKEFLAGS))),)
cmd-echo-silent := true
endif
else                                    # make-3.8x
ifneq ($(findstring s, $(MAKEFLAGS)),)
cmd-echo-silent := true
endif
endif

SCRIPTS_DIR := scripts

# ---------------------------------------------------------------------------
# Kconfig integration
# ---------------------------------------------------------------------------
KCONFIG_KCONFIG    := $(CURDIR)/Kconfig
KCONFIG_CONFIG     := $(abspath $(out-dir))/.config
KCONFIG_AUTOCONFIG := $(abspath $(out-dir))/include/config/auto.conf
KCONFIG_AUTOHEADER := $(abspath $(out-dir))/include/generated/autoconf.h

# Compute the defconfig path immediately (`:=`) so that the conf.mk default
# for PLATFORM_FLAVOR (e.g. "qemu_virt") is not picked up when the user only
# specifies PLATFORM=vexpress.  At this point PLATFORM_FLAVOR is only set if
# the user passed it explicitly (directly or via "PLATFORM=foo-bar" parsing).
_defconfig-plat    := $(PLATFORM)$(if $(PLATFORM_FLAVOR),-$(PLATFORM_FLAVOR),)
KCONFIG_DEFCONFIG  ?= core/arch/$(ARCH)/configs/$(_defconfig-plat)_defconfig

# Make fragment derived from .config: one "CFG_FOO ?= n" line per disabled
# symbol.  Including it injects the symbols into $(.VARIABLES) so that
# cfg-vars-by-prefix / cfg-make-define can emit the correct
# "/* CFG_FOO is not set */" entries in conf.h, matching the plain-Make
# behaviour where mk/config.mk had an explicit "CFG_FOO ?= n" default.
KCONFIG_NOTSET_MK  := $(abspath $(out-dir))/include/config/not-set.mk

# The kconfig tools (conf, mconf) use the CONFIG_ environment variable as the
# prefix for generated symbols.  By setting it to "CFG_" the generated
# .config, auto.conf and autoconf.h all use the existing CFG_* naming
# convention, keeping full backward compatibility with the rest of the tree.
export CONFIG_          := CFG_
export KCONFIG_CONFIG
export KCONFIG_AUTOCONFIG
export KCONFIG_AUTOHEADER
export srctree          := $(CURDIR)
export KCONFIG_DEFCONFIG

kconfig-src-dir   := $(CURDIR)/scripts/kconfig
kconfig-build-dir := $(abspath $(out-dir))/scripts/kconfig
kconfig-conf      := $(kconfig-build-dir)/conf
kconfig-mconf     := $(kconfig-build-dir)/mconf
kconfig-nconf     := $(kconfig-build-dir)/nconf

# Targets that can run without a .config
no-dot-config-targets := clean cscope checkpatch checkpatch-staging \
                         checkpatch-working mem_usage

config-build :=
need-config  := 1

ifneq ($(filter $(no-dot-config-targets), $(MAKECMDGOALS)),)
ifeq ($(filter-out $(no-dot-config-targets), $(MAKECMDGOALS)),)
need-config :=
endif
endif

ifneq ($(filter config %config, $(MAKECMDGOALS)),)
config-build := 1
endif

# Build kconfig host tools on demand (used by both config and build targets).
# Build them in $(kconfig-build-dir) so no artifacts land in the source tree.
$(kconfig-conf) $(kconfig-mconf) $(kconfig-nconf): FORCE
	$(q)mkdir -p $(kconfig-build-dir)
	$(q)$(MAKE) -C $(kconfig-build-dir) -f $(kconfig-src-dir)/Makefile \
		$(notdir $@)

ifdef config-build
# ---------------------------------------------------------------------------
# *config targets
# ---------------------------------------------------------------------------
.PHONY: config menuconfig nconfig oldconfig olddefconfig syncconfig \
        allnoconfig allyesconfig alldefconfig randconfig defconfig \
        savedefconfig listnewconfig

# All *config targets run from $(out-dir) so that the CWD-relative paths
# hard-coded in confdata.c land under the output tree, not the source tree:
#   include/config/auto.conf.cmd   (conf_write_dep)
#   include/config/<SYM>           (conf_touch_dep stamp files)
#   .tmpconfig / .tmpconfig.h      (renamed to auto.conf / autoconf.h)
# $(1) = kconfig binary  $(2) = flag(s) + trailing Kconfig file path
define kconfig-run
	$(q)mkdir -p $(out-dir)/include/config
	$(q)cd $(out-dir) && $(1) $(2)
endef

# Targets whose conf --<flag> matches the target name exactly.
oldconfig olddefconfig syncconfig allnoconfig allyesconfig alldefconfig \
randconfig listnewconfig: $(kconfig-conf)
	$(call kconfig-run,$(kconfig-conf),--$@ $(KCONFIG_KCONFIG))

# Interactive front-ends: line-oriented (conf), ncurses (mconf), TUI (nconf).
config: $(kconfig-conf)
	$(call kconfig-run,$(kconfig-conf),$(KCONFIG_KCONFIG))

menuconfig: $(kconfig-mconf)
	$(call kconfig-run,$(kconfig-mconf),$(KCONFIG_KCONFIG))

nconfig: $(kconfig-nconf)
	$(call kconfig-run,$(kconfig-nconf),$(KCONFIG_KCONFIG))

defconfig: $(kconfig-conf)
	$(call kconfig-run,$(kconfig-conf),--defconfig=$(abspath $(KCONFIG_DEFCONFIG)) $(KCONFIG_KCONFIG))

# savedefconfig only writes the defconfig file; confdata.c is not called,
# so no cd or include/config setup is required.
savedefconfig: $(kconfig-conf)
	$(q)mkdir -p $(dir $(KCONFIG_CONFIG))
	$(q)$(kconfig-conf) --savedefconfig=$(abspath $(KCONFIG_DEFCONFIG)) \
		$(KCONFIG_KCONFIG)

else  # !config-build
# ---------------------------------------------------------------------------
# Normal build targets
# ---------------------------------------------------------------------------

# Kconfig-generated variable assignments must exist before the rest of the
# build system is parsed.  If auto.conf is missing the user forgot to run
# defconfig first; emit a clear error rather than silently falling back to
# the mk/config.mk defaults (which we want to retire).
ifdef need-config
ifeq ($(wildcard $(KCONFIG_AUTOCONFIG)),)
$(error .config not found - run: make PLATFORM=$(PLATFORM) defconfig)
endif
include $(KCONFIG_AUTOCONFIG)
include $(KCONFIG_NOTSET_MK)
endif

# Regenerate auto.conf / autoconf.h whenever .config changes.
# Run from $(out-dir) so that the Kconfig stamp files (include/config/<SYM>)
# and the dep file (include/config/auto.conf.cmd) end up under $(out-dir)
# rather than in the source tree (confdata.c uses a CWD-relative path).
$(KCONFIG_AUTOCONFIG): $(KCONFIG_CONFIG)
	$(q)mkdir -p $(dir $@)
	$(q)cd $(out-dir) && $(kconfig-conf) --syncconfig $(KCONFIG_KCONFIG)

# Regenerate not-set.mk whenever .config changes.  Each "# CFG_FOO is not                                                                                                                        
# set" line in .config becomes a "CFG_FOO ?= n" assignment, making the                                                                                                                           
# disabled symbol visible to cfg-vars-by-prefix so conf.h stays complete.                                                                                                                        
$(KCONFIG_NOTSET_MK): $(KCONFIG_CONFIG)
	$(q)mkdir -p $(dir $@)
	$(q)sed -n 's/^# \($(CONFIG_)[A-Z0-9_]*\) is not set$$/\1 ?= n/p' $< > $@

endif  # !config-build

include core/core.mk

# Platform/arch config is supposed to assign the targets
ta-targets ?= invalid
$(call force,default-user-ta-target,$(firstword $(ta-targets)))

ifeq ($(CFG_WITH_USER_TA),y)
include ldelf/ldelf.mk
define build-ta-target
ta-target := $(1)
include ta/ta.mk
endef
$(foreach t, $(ta-targets), $(eval $(call build-ta-target, $(t))))

# Build user TAs included in this git
ifeq ($(CFG_BUILD_IN_TREE_TA),y)
define build-user-ta
ta-mk-file := $(1)
include ta/mk/build-user-ta.mk
endef
$(foreach t, $(sort $(wildcard ta/*/user_ta.mk)), $(eval $(call build-user-ta,$(t))))
endif
endif

include mk/cleandirs.mk

.PHONY: clean
clean:
	@$(cmd-echo-silent) '  CLEAN   $(out-dir)'
	$(call do-rm-f, $(cleanfiles))
	${q}dirs="$(call cleandirs-for-rmdir)"; if [ "$$dirs" ]; then $(RMDIR) $$dirs; fi
	@if [ "$(out-dir)" != "$(O)" ]; then $(cmd-echo-silent) '  CLEAN   $(O)'; fi
	${q}if [ -d "$(O)" ]; then $(RMDIR) $(O); fi
	${q}rm -f compile_commands.json
	${q}[ ! -d $(kconfig-build-dir) ] || \
		$(MAKE) -C $(kconfig-build-dir) \
		-f $(kconfig-src-dir)/Makefile clean

.PHONY: cscope
cscope:
	@echo '  CSCOPE  .'
	${q}rm -f cscope.*
	${q}find $(PWD) -name "*.[chSs]" | grep -v export-ta_ | \
		grep -v -F _init.ld.S | grep -v -F _unpaged.ld.S > cscope.files
	${q}cscope -b -q -k

.PHONY: checkpatch checkpatch-staging checkpatch-working
checkpatch: checkpatch-staging checkpatch-working

checkpatch-working:
	${q}./scripts/checkpatch.sh

checkpatch-staging:
	${q}./scripts/checkpatch.sh --cached
