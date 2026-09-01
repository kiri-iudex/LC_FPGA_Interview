# Flag to indicate wether we are in debug mode or not
DEBUG ?= 1
# Default max simulation time
SIMTIME ?= 200us

# vhd compiler
GHDL = ghdl
# Wave simulator

WAVE = gtkwave


# Source code directory
SRC = src
# Test bench directory
TB = tb
# Simulation file directory
SIMU = simu
# Directory containing all build files
BUILD = build

# Set error exit code according to the DEBUG flag
# Set maximum tolerance assertion level (errors will be triggered for this error type & above)
ifeq ($(DEBUG), 1)
	ERROREXIT = 0
	ASSERTLVL = error
else
	ERROREXIT = 1
	ASSERTLVL = warning
endif

# Source vhd files
SOURCES = $(wildcard $(SRC)/*.vhd)
TARGETS = $(patsubst $(SRC)/%.vhd, %, $(SOURCES))
# Simulation files
SIMULATIONS = $(wildcard $(SIMU)/*.vcd)


all: builddir $(TARGETS)


# Dependencies
# <my entity>: <my other entity>
cdc_arbiter: sync_2ff


# IP with test bench
%: $(SRC)/%.vhd $(TB)/%_tb.vhd
	@echo "\033[0;33m[Compiling \`$@.vhd\` & \`$@_tb.vhd\` ...]\033[0m"
	$(GHDL) -s --workdir=$(BUILD) $(SRC)/$@.vhd $(TB)/$@_tb.vhd
	$(GHDL) -a --workdir=$(BUILD) $(SRC)/$@.vhd $(TB)/$@_tb.vhd
	$(GHDL) -e --workdir=$(BUILD) -o $(BUILD)/$@_tb $@_tb

	@echo "\033[0;33m[Running simulation of \`$@_tb\` ...]\033[0m"
# Some versions of GHDL produce executables (in $(BUILD)/) and some do not, hence the first two parts of this command
	@./$(BUILD)/$@_tb --vcd=$(SIMU)/$@.vcd --assert-level=$(ASSERTLVL) --stop-time=$(SIMTIME) 2> /dev/null || \
	$(GHDL) -r --workdir=$(BUILD) $@_tb --vcd=$(SIMU)/$@.vcd --assert-level=$(ASSERTLVL) --stop-time=$(SIMTIME) && \
		echo "\033[0;32m[\`$@\` PASS]\033[0m" || (echo "\033[0;31m[\`$@\` FAIL]\033[0m"; exit $(ERROREXIT))


# IP without test bench
%: $(SRC)/%.vhd
	@echo "\033[0;33m[Compiling \`$@.vhd\` ...]\033[0m"
	$(GHDL) -s --workdir=$(BUILD) $(SRC)/$@.vhd
	$(GHDL) -a --workdir=$(BUILD) $(SRC)/$@.vhd


builddir:
	@mkdir -p $(BUILD)/

#simu:
	#$(WAVE) $(SIMULATIONS)


clean:
	rm -rf $(BUILD)/ $(SIMU)/*.vcd


.PHONY: all builddir simu clean