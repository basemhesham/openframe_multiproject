# Regression Makefile — runs all unit + integration tests
# Usage: make all | make unit | make integration | make clean

.PHONY: all unit integration clean

all: unit integration
	@echo ""
	@echo "========================================"
	@echo " Full Regression Complete"
	@echo "========================================"

unit:
	@echo "========================================"
	@echo " Running Unit Tests"
	@echo "========================================"
	$(MAKE) -C ../unit all

integration:
	@echo "========================================"
	@echo " Running Integration Tests"
	@echo "========================================"
	$(MAKE) -C ../integration all

clean:
	$(MAKE) -C ../unit clean
	$(MAKE) -C ../integration clean
