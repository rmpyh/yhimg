# ============================================================
#  项目路径与文件
# ============================================================
PRJ_DIR    := ../..
TB_DIR     := ../test_bench
TB_FILE    := $(TB_DIR)/digital_top_tb_v3_postsim.sv
TOP_MODULE := Digital_Top_tb

# ============================================================
#  仿真控制参数
# ============================================================
SEED ?= 0
GUI  ?= 0
COV  ?= 0
CORES ?= 3                # CPU 核心数，建议 4~8
FGP  ?= 0                 # 是否开启仿真阶段多核并行 (Fine-Grained Parallelism)
SDF_PATH_IN ?= ""
DUMP_WAVE   ?= 0
# ============================================================
#  SDF 反标配置
#  可通过命令行覆盖，例如：make sim TEMP=m40 PROCESS=libFastFast RC=cmin
# ============================================================
TEMP    ?= 125
PROCESS ?= 125_libslowSlow_cmax
RC      ?= cmax

CORNER_NAME ?= default

SDF_DIR  ?= $(PRJ_DIR)/Netlist/sdf
SDF_NAME := Digital_Top_IP_Integration_$(TEMP)_$(PROCESS)_$(RC).sdf
SDF_PATH := $(SDF_DIR)/$(SDF_NAME)

# ============================================================
#  编译选项
# ============================================================
INC_DIR = +incdir+$(PRJ_DIR)

VLOGAN_OPTS = -full64 -nc -sverilog \
              +v2k -timescale=1ns/1ps -l compile.log -kdb $(INC_DIR)

# VLOGAN_OPTS += -debug_access+all  -debug_region+cell 
VHDLAN_OPTS = -full64 -nc -kdb -l compile.log

# -- VCS Elab 选项 --
VCS_ELAB_OPTS  = -full64 -l elab.log \
                 -timescale=1ns/1ps -kdb -j$(shell expr $(CORES) + 1)

# VCS_ELAB_OPTS += -debug_access+all -debug_region+cell
VCS_ELAB_OPTS += -L io_lib
VCS_ELAB_OPTS += -negdelay +neg_tchk         # 支持负延迟与负时序检查

# -- VCS 仿真选项 --
VCS_SIM_OPTIONS  = +vcs+lic+wait
VCS_SIM_OPTIONS += +sps_enable_hier_trace +fsdb+trans_begin_callstack

# -- GUI 模式 --
ifeq ($(GUI),1)
VCS_SIM_OPTIONS += -gui=verdi
endif

# -- 覆盖率采集 --
ifeq ($(COV),1)
VCS_ELAB_OPTS  += -cm line+cond+fsm+tgl -cm_hier ./cov.cfg
VCS_SIM_OPTIONS += -cm line+cond+fsm+tgl+branch
endif

# -- 多核并行 (FGP) --
ifeq ($(FGP),1)
VCS_ELAB_OPTS  += -fgp
VCS_SIM_OPTIONS += -fgp=num_threads:$(CORES)
endif

# ============================================================
#  文件列表与库
# ============================================================
VERILOG_FLIST := verilog.f
VHDL_FLIST    := vhdl.f

IO_LIB_DIR   := io_lib_dir
IO_LIB_FILES := ../lib/IO/SP55NLLD2RP_OV3_V0p2a.v \
                ../lib/SC/HVT/scc55nll_vhs_hvt.v \
                ../lib/SC/LVT/scc55nll_vhs_lvt.v \
                ../lib/SC/RVT/scc55nll_vhs_rvt.v

# ============================================================
#  编译目标
# ============================================================

# 默认目标
all: analyze elab clean

# --- IO 库编译 ---
$(IO_LIB_DIR)/.io_compiled: $(IO_LIB_FILES)
	@echo "Detected library changes or missing library. Compiling IO_LIB..."
	mkdir -p $(IO_LIB_DIR)
	vlogan $(VLOGAN_OPTS) -work io_lib $(IO_LIB_FILES)
	touch $@

analyze_iolib: $(IO_LIB_DIR)/.io_compiled

# --- 分析阶段 ---
analyze_verilog:
	vlogan $(VLOGAN_OPTS) -f $(VERILOG_FLIST)

analyze_vhdl:
	vhdlan $(VHDLAN_OPTS) -f $(VHDL_FLIST)

# 
# analyze_tb:
# 	vlogan $(VLOGAN_OPTS) +define+FSDB +define+SDF_FILE=\"$(SDF_PATH)\" $(TB_FILE)

analyze_tb:
	vlogan $(VLOGAN_OPTS) $(TB_FILE)

analyze: analyze_verilog analyze_vhdl analyze_tb

# --- 编译链接阶段 ---
# elab:
# 	vcs $(VCS_ELAB_OPTS) -top $(TOP_MODULE) -o simv
elab:
	vcs $(VCS_ELAB_OPTS) -top $(TOP_MODULE) \
	-sdf $(SDF_COND):Digital_Top_tb.dut:$(SDF_PATH_IN) \
	-Mdir=csrc_$(CORNER_NAME) \
	-l elab_$(CORNER_NAME).log \
	-o simv_$(CORNER_NAME)
# --- 仿真运行 ---
# sim:
# 	./simv -no_save +ntb_random_seed=$(SEED) $(VCS_SIM_OPTIONS) \
# 	-l sim_$(CORNER_NAME).log \
# 	+dump +fsdb+region
sim:
	@mkdir -p regression_logs/$(CORNER_NAME)
	cd regression_logs/$(CORNER_NAME) && ../../simv_$(CORNER_NAME) $(VCS_SIM_OPTIONS) \
	-no_save \
	+ntb_random_seed=$(SEED) \
	-l sim.log \
	$(if $(filter 1,$(DUMP_WAVE)),+DUMP_FSDB +FSDB_FILE_NAME=wave.fsdb,) 
# +dump +fsdb+region
# --- Verdi 波形查看 ---
verdi:
	verdi -full64 \
	      -dbdir simv.daidir \
	      -ssf Digital_All_wave.fsdb -nologo

# --- 覆盖率查看 ---
cov:
	verdi -cov -covdir *.vdb/

# --- 清理 ---
clean:
	rm -rf *.log csrc* simv* *.key *.vpd coverage *.vdb *.fsdb *.h verdiLog.* inter.* work
