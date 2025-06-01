#!/bin/bash

# Define os executáveis
EXECUTABLE_STARPU="./matmul_starpu_hetero"
EXECUTABLE_SEQ="./matmul_sequential"

# Define o número de workers CPU e CUDA/OpenCL a serem usados pelo StarPU
export STARPU_NCPU=2    # Exemplo: usar 2 workers CPU para StarPU
export STARPU_NCUDA=1   
export STARPU_NOPENCL=1 
export STARPU_VERBOSITY=0 

REPETITIONS_STARPU=5 # Número de repetições para cada política StarPU
REPETITIONS_SEQ=3    # Número de repetições para o sequencial (para média, se desejado)

POLICIES_ORDERED=("random" "eager" "ws" "dmda") 

RESULTS_DIR="starpu_benchmark_results_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$RESULTS_DIR"

SUMMARY_FILE="${RESULTS_DIR}/summary_benchmark.csv"
echo "Tipo_Exec,Política_StarPU,Repetição,MATRIX_SIZE,BLOCK_SIZE,Tempo_Exec_ms,Dispositivo_Usado_Log" > "$SUMMARY_FILE"

echo "Iniciando benchmarks. Resultados serão salvos em: $RESULTS_DIR"
echo "Configuração de Workers StarPU: CPU=${STARPU_NCPU}, CUDA=${STARPU_NCUDA}, OpenCL=${STARPU_NOPENCL}"
echo ""

# --- Compilação ---
echo "Compilando os projetos..."
make clean > /dev/null
make all # Compila ambos os alvos: starpu e sequencial
if [ $? -ne 0 ]; then
    echo "Erro na compilação! Verifique o Makefile e as dependências."
    exit 1
fi
echo "Compilação concluída."
echo ""

# Verifica se os executáveis existem
if [ ! -f "$EXECUTABLE_SEQ" ]; then
    echo "Erro: Executável Sequencial '$EXECUTABLE_SEQ' não encontrado."
    exit 1
fi
if [ ! -f "$EXECUTABLE_STARPU" ]; then
    echo "Erro: Executável StarPU '$EXECUTABLE_STARPU' não encontrado."
    exit 1
fi

# Obtém MATRIX_SIZE e BLOCK_SIZE do Makefile
MATRIX_SIZE_FROM_MAKEFILE=$(grep -oP 'MATRIX_SIZE_DEF\s*=\s*\K[0-9]+' Makefile)
BLOCK_SIZE_FROM_MAKEFILE=$(grep -oP 'BLOCK_SIZE_DEF\s*=\s*\K[0-9]+' Makefile)

# --- Execução Sequencial ---
echo "-----------------------------------------------------"
echo "Executando Baseline Sequencial (CPU)..."
echo "-----------------------------------------------------"
total_seq_time=0
for i in $(seq 1 "$REPETITIONS_SEQ"); do
    iteration_num=$(printf "%02d" "$i")
    output_file_seq="${RESULTS_DIR}/results_sequential_iter${iteration_num}.log"
    echo "Executando Sequencial - Repetição $i/$REPETITIONS_SEQ ... Saída em: $output_file_seq"
    
    "$EXECUTABLE_SEQ" > "$output_file_seq" 2>&1
    
    if [ $? -eq 0 ]; then
        seq_time_ms=$(grep "Tempo_Exec_Sequencial_ms:" "$output_file_seq" | cut -d':' -f2)
        if [ -n "$seq_time_ms" ]; then
            echo "Repetição $i (Sequencial) concluída. Tempo: $seq_time_ms ms"
            echo "Sequencial,N/A,$i,$MATRIX_SIZE_FROM_MAKEFILE,N/A,$seq_time_ms,CPU" >> "$SUMMARY_FILE"
            total_seq_time=$(echo "$total_seq_time + $seq_time_ms" | bc)
        else
            echo "ERRO ao extrair tempo da Repetição $i (Sequencial). Verifique $output_file_seq."
            echo "Sequencial,N/A,$i,$MATRIX_SIZE_FROM_MAKEFILE,N/A,ERROR,CPU" >> "$SUMMARY_FILE"
        fi
    else
        echo "ERRO na Repetição $i (Sequencial)! Verifique $output_file_seq."
        echo "Sequencial,N/A,$i,$MATRIX_SIZE_FROM_MAKEFILE,N/A,ERROR,CPU" >> "$SUMMARY_FILE"
    fi
done
avg_seq_time_ms="N/A"
if [ "$REPETITIONS_SEQ" -gt 0 ]; then
    avg_seq_time_ms=$(echo "scale=2; $total_seq_time / $REPETITIONS_SEQ" | bc)
fi
echo "Tempo Médio Sequencial: $avg_seq_time_ms ms"
echo "-----------------------------------------------------"
echo ""


# --- Execução StarPU ---
echo "-----------------------------------------------------"
echo "Iniciando Testes StarPU..."
echo "-----------------------------------------------------"
for policy in "${POLICIES_ORDERED[@]}"; do
    echo "Testando Política de Escalonamento StarPU: $policy"
    export STARPU_SCHED="$policy"

    for i in $(seq 1 "$REPETITIONS_STARPU"); do
        iteration_num=$(printf "%02d" "$i")
        output_file_starpu="${RESULTS_DIR}/results_starpu_${policy}_iter${iteration_num}.log"
        
        echo "Executando StarPU ($policy) - Repetição $i/$REPETITIONS_STARPU ... Saída em: $output_file_starpu"
        
        "$EXECUTABLE_STARPU" > "$output_file_starpu" 2>&1
        
        if [ $? -eq 0 ]; then
            echo "Repetição $i (StarPU $policy) concluída."
            
            starpu_exec_line=$(grep "Tempo_StarPU_ms:" "$output_file_starpu" | tail -n 1) # Mudado para Tempo_StarPU_ms
            starpu_time_ms=$(echo "$starpu_exec_line" | grep -oP 'Tempo_StarPU_ms:\K[0-9]+\.[0-9]+')

            device_used_summary="VERIFICAR_LOG" 
            # Você pode adicionar uma lógica mais sofisticada aqui para determinar o dispositivo
            # baseado no conteúdo do log, se as funções de tarefa imprimirem algo.
            if grep -q "Executando matmul na CPU" "$output_file_starpu"; then
                device_used_summary="CPU"
            elif grep -q "Chamando wrapper para GPU CUDA" "$output_file_starpu"; then
                device_used_summary="CUDA"
            elif grep -q "Chamando wrapper para GPU OpenCL" "$output_file_starpu"; then
                device_used_summary="OpenCL"
            elif grep -q "StarPU CPU: Bloco" "$output_file_starpu" && (grep -q "StarPU CUDA: Bloco" "$output_file_starpu" || grep -q "StarPU OpenCL: Bloco" "$output_file_starpu"); then
                device_used_summary="CPU+GPU_Mix" # Exemplo se ambos forem detectados
            fi


            echo "StarPU,$policy,$i,$MATRIX_SIZE_FROM_MAKEFILE,$BLOCK_SIZE_FROM_MAKEFILE,$starpu_time_ms,$device_used_summary" >> "$SUMMARY_FILE"
        else
            echo "ERRO na Repetição $i (StarPU $policy)! Verifique $output_file_starpu."
            echo "StarPU,$policy,$i,$MATRIX_SIZE_FROM_MAKEFILE,$BLOCK_SIZE_FROM_MAKEFILE,ERROR,ERROR" >> "$SUMMARY_FILE"
        fi
    done
    echo "Testes para a política StarPU $policy concluídos."
    echo ""
done

echo "-----------------------------------------------------"
echo "Todos os benchmarks concluídos."
echo "Resultados salvos em: $RESULTS_DIR"
echo "Resumo em: $SUMMARY_FILE"
echo "-----------------------------------------------------"

unset STARPU_NCPU
unset STARPU_NCUDA
unset STARPU_NOPENCL
unset STARPU_VERBOSITY
unset STARPU_SCHED
