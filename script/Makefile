all: clean com sim verdi
test: clean com sim

SCRIPT_DIR	:= $(shell pwd)

RTL_FILES   += $(shell find $(abspath ../include) -name "*.svh")
RTL_FILES   += $(shell find $(abspath ../core) -name "*.sv")
RTL_FILES   += $(shell find $(abspath ../tb) -name "performance.sv")

SIM_FILES   := ${RTL_FILES}
SIM_OPTIONS := +v2k -debug_access+all -full64 -timescale=1ns/1ns -fsdb -sverilog +vcs+loopreport+10000 
SIM_INC	 	:= +incdir+"$(abspath ../include)"

WAVE_FILES  :=  ${RTL_FILES}
WAVE_OPTIONS:= -nologo -sverilog -ssf *.fsdb
WAVE_INC    := +incdir+"$(abspath ../include)"

com:
	vcs $(SIM_OPTIONS) $(SIM_FILES) ${SIM_INC} -l com.log
	
sim:
	./simv -l sim.log

verdi:
	verdi $(WAVE_OPTIONS) $(WAVE_INC) $(WAVE_FILES) & 

clean:
	rm -rf *.vpd csrc *.log *.key *.vpd simv* DVE*
	rm -rf verdiLog *.fsdb *.bak *.conf

.PHONY: com sim verdi clean