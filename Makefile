# Makefile para Multiplicação de Matrizes com StarPU (CPU, OpenCL)

# Compiladores
CC = gcc
# NVCC não é mais necessário

# Flags de Compilação Comuns
CFLAGS_COMMON = -O2 -Wall -std=c11 -pthread # Adicionado -pthread

# --- Configurações do StarPU ---
# !!!!! IMPORTANTE: Certifique-se de que NÃO HÁ ESPAÇOS no final destas duas linhas !!!!!
STARPU_VERSION_MAJOR_MINOR = 1.4
STARPU_PREFIX = $(HOME)/local/starpu-1.4.7

# Flags de include APENAS para o StarPU (para GCC ao compilar arquivos .c)
# Construído cuidadosamente para evitar espaços extras
STARPU_ONLY_CFLAGS := -I$(STARPU_PREFIX)/include/starpu/$(STARPU_VERSION_MAJOR_MINOR)

# CFLAGS e LIBS do StarPU (para OpenCL, se o .pc do StarPU os fornecer)
# Definindo PKG_CONFIG_PATH explicitamente para o subshell, ignorando o do ambiente.
ALL_STARPU_CFLAGS_FROM_PKG := $(shell PKG_CONFIG_PATH=$(STARPU_PREFIX)/lib/pkgconfig pkg-config --cflags starpu-$(STARPU_VERSION_MAJOR_MINOR) | xargs)
STARPU_LIBS := $(shell PKG_CONFIG_PATH=$(STARPU_PREFIX)/lib/pkgconfig pkg-config --libs starpu-$(STARPU_VERSION_MAJOR_MINOR) | xargs)

# --- Configurações do OpenCL ---
OPENCL_CFLAGS := $(shell PKG_CONFIG_PATH=$(STARPU_PREFIX)/lib/pkgconfig pkg-config --cflags OpenCL 2>/dev/null | xargs)
OPENCL_LIBS := $(shell PKG_CONFIG_PATH=$(STARPU_PREFIX)/lib/pkgconfig pkg-config --libs OpenCL 2>/dev/null | xargs)
ifeq ($(OPENCL_CFLAGS),)
OPENCL_CFLAGS = -I/usr/include 
endif
ifeq ($(OPENCL_LIBS),)
OPENCL_LIBS = -lOpenCL 
endif

# --- Definições Globais para o Código ---
DEFINES = -DMATRIX_SIZE=1024 -DBLOCK_SIZE=64 -D_GNU_SOURCE # Adicionado -D_GNU_SOURCE
# DEFINES += -DSTARPU_USE_CUDA   # CUDA DESABILITADO NESTA VERSÃO DO MAKEFILE
DEFINES += -DSTARPU_USE_OPENCL # OpenCL HABILITADO

# --- Arquivos Fonte e Objetos ---
SRC_DIR = src
C_FILES_STARPU = $(SRC_DIR)/matmul_starpu.c $(SRC_DIR)/matmul_kernels_opencl.c
# CU_FILES não é mais usado

C_OBJS_STARPU = $(patsubst $(SRC_DIR)/%.c,$(SRC_DIR)/%.o,$(C_FILES_STARPU))
# CU_OBJS não é mais usado

ALL_OBJS_STARPU = $(C_OBJS_STARPU) # Apenas objetos C

TARGET_STARPU = matmul_starpu_opencl_cpu # Novo nome para o executável
TARGET_SEQ = matmul_sequential
C_FILE_SEQ = $(SRC_DIR)/matmul_sequential.c
C_OBJ_SEQ = $(patsubst %.c,%.o,$(C_FILE_SEQ))


.PHONY: all clean starpu_target sequential_target

all: $(TARGET_STARPU) $(TARGET_SEQ)

starpu_target: $(TARGET_STARPU)
sequential_target: $(TARGET_SEQ)

$(TARGET_STARPU): $(ALL_OBJS_STARPU)
	@echo "Linkando o executável StarPU (OpenCL+CPU): $@"
	$(CC) $(CFLAGS_COMMON) $^ -o $@ $(STARPU_LIBS) $(OPENCL_LIBS) -lm -pthread # Adicionado -pthread
	@echo "-----------------------------------------------------"
	@echo "Executável $(TARGET_STARPU) criado com sucesso."
	@echo "-----------------------------------------------------"

$(TARGET_SEQ): $(C_OBJ_SEQ)
	@echo "Linkando o executável Sequencial: $@"
	$(CC) $(CFLAGS_COMMON) -DMATRIX_SIZE=$(firstword $(subst DMATRIX_SIZE=,,$(filter %MATRIX_SIZE=%,$(DEFINES)))) $^ -o $@ -lm
	@echo "-----------------------------------------------------"
	@echo "Executável $(TARGET_SEQ) criado com sucesso."
	@echo "-----------------------------------------------------"

# Regras de compilação de objeto para StarPU
$(SRC_DIR)/matmul_starpu.o: $(SRC_DIR)/matmul_starpu.c $(SRC_DIR)/matmul_kernels.h
	@echo "Compilando fonte C (StarPU main): $<"
	@echo "DEBUG: CFLAGS for C are [$(CFLAGS_COMMON) $(DEFINES) $(STARPU_ONLY_CFLAGS) $(OPENCL_CFLAGS) -I$(SRC_DIR)]"
	$(CC) $(CFLAGS_COMMON) $(DEFINES) $(STARPU_ONLY_CFLAGS) $(OPENCL_CFLAGS) -I$(SRC_DIR) -c $< -o $@

$(SRC_DIR)/matmul_kernels_opencl.o: $(SRC_DIR)/matmul_kernels_opencl.c $(SRC_DIR)/matmul_kernels.h
	@echo "Compilando fonte C (OpenCL Wrapper): $<"
	$(CC) $(CFLAGS_COMMON) $(DEFINES) $(STARPU_ONLY_CFLAGS) $(OPENCL_CFLAGS) -I$(SRC_DIR) -c $< -o $@

# Regra para CUDA removida

# Regra de compilação de objeto para Sequencial
$(C_OBJ_SEQ): $(C_FILE_SEQ)
	@echo "Compilando fonte C (Sequencial): $<"
	$(CC) $(CFLAGS_COMMON) -DMATRIX_SIZE=$(firstword $(subst DMATRIX_SIZE=,,$(filter %MATRIX_SIZE=%,$(DEFINES)))) -c $< -o $@

clean:
	@echo "Limpando arquivos gerados..."
	rm -f $(TARGET_STARPU) $(TARGET_SEQ) $(SRC_DIR)/*.o *.o
	@echo "Limpeza concluída."

