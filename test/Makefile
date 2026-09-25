# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info

# defaults
# The tt-gds-action gl_test job only installs Icarus Verilog and invokes
# `GATES=yes make`, so gate-level runs must default to icarus.  RTL runs keep
# verilator (fastest simulator locally and in the test workflow).  An explicit
# `make SIM=...` always wins.
ifeq ($(GATES),yes)
SIM ?= icarus
else
SIM ?= verilator
endif
FST ?= -fst # Use more efficient FST format
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../src
PROJECT_SOURCES = project.v \
  cfg_spi_slave.sv host_cmd_if.sv management_decode.sv csr_block.sv \
  engine/protocol_emulator_top.sv engine/pe_host_if.sv engine/pe_imem.sv \
  engine/pe_clkdiv.sv engine/pe_core.sv engine/pe_decoder.sv engine/pe_io.sv \
  engine/pe_fifo.sv engine/pe_sync.sv

ifneq ($(GATES),yes)

# RTL simulation:
SIM_BUILD				= sim_build/rtl
VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))

else

# Gate level simulation:
SIM_BUILD				= sim_build/gl
COMPILE_ARGS    += -DGL_TEST
COMPILE_ARGS    += -DFUNCTIONAL
COMPILE_ARGS    += -DSIM
VERILOG_SOURCES += $(PDK_ROOT)/ihp-sg13g2/libs.ref/sg13g2_io/verilog/sg13g2_io.v
VERILOG_SOURCES += $(PDK_ROOT)/ihp-sg13g2/libs.ref/sg13g2_stdcell/verilog/sg13g2_stdcell.v

# this gets copied in by the GDS action workflow
VERILOG_SOURCES += $(PWD)/gate_level_netlist.v

endif

# Default goal wrapper.  The tt-gds-action gl_test job gates success on
# `! grep failure results.xml`, which false-matches the `failures="0"`
# attribute that cocotb 2.x always writes (the same bug the test workflow
# works around with a stricter grep).  Run the simulation, then strip
# zero-count attributes so the naive grep only ever matches real failures;
# a failing run keeps `failures="N"` and the <failure> elements and still
# trips the check.
.PHONY: ci_sim
ci_sim: sim
	@sed -i 's/ errors="0"//g; s/ failures="0"//g' $(COCOTB_RESULTS_FILE)

# Allow sharing configuration between design and testbench via `include`:
COMPILE_ARGS 		+= -I$(SRC_DIR)
ifeq ($(SIM),verilator)
# Verilator-only flags; Icarus Verilog rejects --timing/--Wno-fatal.
COMPILE_ARGS 		+= --timing
COMPILE_ARGS 		+= --Wno-fatal
endif

# Include the testbench sources:
VERILOG_SOURCES += $(PWD)/tb.v
TOPLEVEL = tb

# List test modules to run, separated by commas and without the .py suffix:
COCOTB_TEST_MODULES = test

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim
