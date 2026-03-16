# Unit test Makefile for MP-SoC OpenFrame Wrapper
# Usage: make all | make tb_scan_node | make clean

RTL_PATH = ../../rtl
TECH_PATH = $(RTL_PATH)/tech_lib
COMMON_PATH = ../common

IVERILOG = iverilog
VVP = vvp

DEFINES = -DFUNCTIONAL -DSIM
INCLUDES = -I$(RTL_PATH) -I$(TECH_PATH) -I$(COMMON_PATH)

# RTL sources for each test
TECH_SRCS = $(TECH_PATH)/tech_buf.v $(TECH_PATH)/tech_clkbuf.v $(TECH_PATH)/tech_clkgate.v
SCAN_NODE_SRC = $(RTL_PATH)/scan_macro_node.v
SCAN_CTRL_SRC = $(RTL_PATH)/scan_controller_macro.v
GREEN_SRC = $(RTL_PATH)/green_macro.v
ORANGE_SRC = $(RTL_PATH)/orange_macro.v
PURPLE_SRC = $(RTL_PATH)/purple_macro.v

UNIT_TESTS = tb_scan_node tb_scan_ctrl tb_green tb_orange tb_purple

.PHONY: all clean $(UNIT_TESTS)

all: $(UNIT_TESTS)
	@echo ""
	@echo "========================================"
	@echo " Unit Test Summary"
	@echo "========================================"
	@pass=0; fail=0; \
	for t in $(UNIT_TESTS); do \
		if grep -q "ALL TESTS PASSED" $$t.log 2>/dev/null; then \
			echo "  PASS: $$t"; pass=$$((pass+1)); \
		else \
			echo "  FAIL: $$t"; fail=$$((fail+1)); \
		fi; \
	done; \
	echo "========================================"; \
	echo " $$pass passed, $$fail failed"; \
	echo "========================================"; \
	[ $$fail -eq 0 ]

tb_scan_node: tb_scan_node.vvp
	$(VVP) $< | tee $@.log
	@grep -q "ALL TESTS PASSED" $@.log

tb_scan_ctrl: tb_scan_ctrl.vvp
	$(VVP) $< | tee $@.log
	@grep -q "ALL TESTS PASSED" $@.log

tb_green: tb_green.vvp
	$(VVP) $< | tee $@.log
	@grep -q "ALL TESTS PASSED" $@.log

tb_orange: tb_orange.vvp
	$(VVP) $< | tee $@.log
	@grep -q "ALL TESTS PASSED" $@.log

tb_purple: tb_purple.vvp
	$(VVP) $< | tee $@.log
	@grep -q "ALL TESTS PASSED" $@.log

tb_scan_node.vvp: tb_scan_node.v $(TECH_SRCS) $(SCAN_NODE_SRC)
	$(IVERILOG) $(DEFINES) $(INCLUDES) -o $@ $^

tb_scan_ctrl.vvp: tb_scan_ctrl.v $(TECH_SRCS) $(SCAN_NODE_SRC) $(SCAN_CTRL_SRC)
	$(IVERILOG) $(DEFINES) $(INCLUDES) -o $@ $^

tb_green.vvp: tb_green.v $(TECH_SRCS) $(SCAN_NODE_SRC) $(GREEN_SRC)
	$(IVERILOG) $(DEFINES) $(INCLUDES) -o $@ $^

tb_orange.vvp: tb_orange.v $(TECH_SRCS) $(SCAN_NODE_SRC) $(ORANGE_SRC)
	$(IVERILOG) $(DEFINES) $(INCLUDES) -o $@ $^

tb_purple.vvp: tb_purple.v $(TECH_SRCS) $(SCAN_NODE_SRC) $(PURPLE_SRC)
	$(IVERILOG) $(DEFINES) $(INCLUDES) -o $@ $^

clean:
	rm -f *.vvp *.vcd *.log
