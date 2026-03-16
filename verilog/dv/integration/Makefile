# Integration test Makefile for MP-SoC OpenFrame Wrapper
# Usage: make all | make tb_scan_chain | make clean

RTL_PATH = ../../rtl
TECH_PATH = $(RTL_PATH)/tech_lib
COMMON_PATH = ../common

IVERILOG = iverilog
VVP = vvp

DEFINES = -DFUNCTIONAL -DSIM
INCLUDES = -I$(RTL_PATH) -I$(TECH_PATH) -I$(COMMON_PATH)

# All RTL sources needed for the full wrapper
RTL_SRCS = \
	$(TECH_PATH)/tech_buf.v \
	$(TECH_PATH)/tech_clkbuf.v \
	$(TECH_PATH)/tech_clkgate.v \
	$(RTL_PATH)/scan_macro_node.v \
	$(RTL_PATH)/green_macro.v \
	$(RTL_PATH)/orange_macro.v \
	$(RTL_PATH)/purple_macro.v \
	$(RTL_PATH)/project_macro.v \
	$(RTL_PATH)/scan_controller_macro.v \
	$(RTL_PATH)/vccd1_connection.v \
	$(RTL_PATH)/vssd1_connection.v \
	$(RTL_PATH)/openframe_project_wrapper.v

INTEG_TESTS = tb_scan_chain tb_project_select tb_gpio_routing tb_reset_behavior tb_security

.PHONY: all clean $(INTEG_TESTS)

all: $(INTEG_TESTS)
	@echo ""
	@echo "========================================"
	@echo " Integration Test Summary"
	@echo "========================================"
	@pass=0; fail=0; \
	for t in $(INTEG_TESTS); do \
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

$(INTEG_TESTS): %: %.vvp
	$(VVP) $< | tee $@.log
	@grep -q "ALL TESTS PASSED" $@.log

%.vvp: %.v $(RTL_SRCS)
	$(IVERILOG) $(DEFINES) $(INCLUDES) -o $@ $^

clean:
	rm -f *.vvp *.vcd *.log
