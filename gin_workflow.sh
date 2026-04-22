#!/usr/bin/env bash
set -euo pipefail

# This was translated from the original workflow via OpenAI, 27/02/2026
# =========
# Settings
# =========
proj=$1
GINOPTION="${2:-}"  # Which Option to run the script on, this is so we run the profiler only once

PROJECT_DIR="/opt/$proj"
PROJECT_NAME="$proj"
GIN_JAR="/opt/gin/build/gin.jar"
MAVEN_HOME="/root/.sdkman/candidates/maven/current"
RESULTS_DIR="${PROJECT_DIR}/results"
TINYLOG_LEVEL="trace"

# LLM / model tag used in filenames + Gin args
#LLM="gemma2:2b"
LLM="gpt-oss:120b"
MODEL="${LLM}"

export OLLAMA_SERVER='https://ollama.com'
export OLLAMA_API_KEY=<YOUR-OLLAMA-KEY>

cd "${PROJECT_DIR}"

# =========================================
# Defaults that can be overridden per project
# =========================================

# Use arrays for optional / extra args
COMMON_JVM_ARGS=(-j)

PROFILE_TIMEOUT_MS=10000
EMPTY_TIMEOUT_MS=10000
RANDOM_TIMEOUT_MS=10000
LOCAL_TIMEOUT_MS=10000
PATCHCAT_TIMEOUT_MS=10000

PROFILE_EXTRA_ARGS=()
EMPTY_EXTRA_ARGS=()
RANDOM_EXTRA_ARGS=()
LOCAL_EXTRA_ARGS=()
PATCHCAT_EXTRA_ARGS=()

# ==========================
# Project-specific overrides
# ==========================
case "${proj}" in
    # Example: disable -j for a project
    # someproject)
    #     COMMON_JVM_ARGS=()
    # ;;

    # Example: longer timeouts
    # bigproject)
    #     EMPTY_TIMEOUT_MS=30000
    #     RANDOM_TIMEOUT_MS=30000
    #     LOCAL_TIMEOUT_MS=30000
    #     PATCHCAT_TIMEOUT_MS=30000
    # ;;

    # Example: extra options for one mode only
    # junit4)
    #     EMPTY_EXTRA_ARGS+=(-x)
    #     LOCAL_EXTRA_ARGS+=(-someFlag someValue)
    # ;;

    gson)
        PROFILE_EXTRA_ARGS+=(-ba -pl,gson)
    ;;

    mybatis-3)
        COMMON_JVM_ARGS=(-J)
        EMPTY_TIMEOUT_MS=1000000
        RANDOM_TIMEOUT_MS=1000000
        LOCAL_TIMEOUT_MS=1000000
        PATCHCAT_TIMEOUT_MS=1000000
    ;;

    biojava)
        EMPTY_TIMEOUT_MS=1000000
        RANDOM_TIMEOUT_MS=1000000
        LOCAL_TIMEOUT_MS=1000000
        PATCHCAT_TIMEOUT_MS=1000000
    ;;

    arthas)
        export TZ=UTC
        EMPTY_TIMEOUT_MS=1000000
        RANDOM_TIMEOUT_MS=1000000
        LOCAL_TIMEOUT_MS=1000000
        PATCHCAT_TIMEOUT_MS=1000000
    ;;

    opennlp)
        EMPTY_TIMEOUT_MS=1000000
        RANDOM_TIMEOUT_MS=1000000
        LOCAL_TIMEOUT_MS=1000000
        PATCHCAT_TIMEOUT_MS=1000000
    ;;

    *)
    ;;
esac

# =====================
# 1) Profile the project
# =====================
case "${GINOPTION}" in
    profile | PROFILE | prof | profiling)
        java -Dtinylog.level="${TINYLOG_LEVEL}" \
          -cp "${GIN_JAR}" \
          gin.util.Profiler \
          -r 20 \
          -mavenHome "${MAVEN_HOME}" \
          -p "${PROJECT_NAME}" \
          -d . \
          "${PROFILE_EXTRA_ARGS[@]}" \
          -o "${PROJECT_NAME}.Profiler_output.csv"
    ;;
    

# ==========================
# 2) Empty Patch Tester (sanity check)
# ==========================
    empty | Empty | ept | EPT)
        mkdir -p "${RESULTS_DIR}"

        java -Dtinylog.level="${TINYLOG_LEVEL}" \
          -cp "${GIN_JAR}" \
          gin.util.EmptyPatchTester \
          "${COMMON_JVM_ARGS[@]}" \
          -p "${PROJECT_NAME}" \
          -d . \
          -m "${PROJECT_NAME}.Profiler_output.csv" \
          -o "${RESULTS_DIR}/${PROJECT_NAME}.EmptyPatchTester_output.csv" \
          -mavenHome "${MAVEN_HOME}" \
          -timeoutMS "${EMPTY_TIMEOUT_MS}" \
          "${EMPTY_EXTRA_ARGS[@]}" \
          &> "${RESULTS_DIR}/${PROJECT_NAME}.EmptyPatchTester_stderrstdout.txt"
    ;;
    


# ==========================
# 3) Masking Random Search
# ==========================
    random | Random | rand | RANDOM)
        mkdir -p "${RESULTS_DIR}"

        java -Dtinylog.level="${TINYLOG_LEVEL}" \
          -cp "${GIN_JAR}" \
          gin.util.RandomSampler \
          "${COMMON_JVM_ARGS[@]}" \
          -p "${PROJECT_NAME}" \
          -d . \
          -m "${PROJECT_NAME}.Profiler_output.csv" \
          -o "${RESULTS_DIR}/${PROJECT_NAME}.RandomSampler_1000_output.${MODEL}.csv" \
          -mavenHome "${MAVEN_HOME}" \
          -timeoutMS "${RANDOM_TIMEOUT_MS}" \
          -et gin.edit.llm.LLMMaskedStatement \
          -mt "${MODEL}" \
          -pt MASKED \
          -pn 1000 \
          "${RANDOM_EXTRA_ARGS[@]}" \
          &> "${RESULTS_DIR}/${PROJECT_NAME}.RandomSampler_COMBINED_1000_stderrstdout.${MODEL}.txt"
    ;;

# =========================
# 4) Masking Local Search
# =========================
    local | Local | LOCAL)
        mkdir -p "${RESULTS_DIR}"

        java -Dtinylog.level="${TINYLOG_LEVEL}" \
          -cp "${GIN_JAR}" \
          gin.util.LocalSearchRuntime \
          "${COMMON_JVM_ARGS[@]}" \
          -p "${PROJECT_NAME}" \
          -d . \
          -m "${PROJECT_NAME}.Profiler_output.csv" \
          -o "${RESULTS_DIR}/${PROJECT_NAME}.LocalSearchRuntime_COMBINED_50_output.${MODEL}.csv" \
          -mavenHome "${MAVEN_HOME}" \
          -timeoutMS "${LOCAL_TIMEOUT_MS}" \
          -et gin.edit.llm.LLMMaskedStatement \
          -mt "${LLM}" \
          -pt MASKED \
          -in 100 \
          "${LOCAL_EXTRA_ARGS[@]}" \
          &> "${RESULTS_DIR}/${PROJECT_NAME}.LocalSearchRuntime_LLM_MASKED_50_stderrstdout.${MODEL}.txt"
    ;;

# =========================
# 5) Local Search with PatchCat
# =========================
    LocalPatchCat | lpc | LPC | localpatchcat | LOCALPATCHCAT)
        mkdir -p "${RESULTS_DIR}"
        echo "Starting Gin with PatchCat"

        java -Dtinylog.level="${TINYLOG_LEVEL}" \
          -cp "${GIN_JAR}" \
          gin.util.LocalSearchRuntime \
          "${COMMON_JVM_ARGS[@]}" \
          -p "${PROJECT_NAME}" \
          -d . \
          -m "${PROJECT_NAME}.Profiler_output.csv" \
          -o "${RESULTS_DIR}/${PROJECT_NAME}.LocalSearchRuntime_COMBINED_50_output.${MODEL}.csv" \
          -mavenHome "${MAVEN_HOME}" \
          -timeoutMS "${PATCHCAT_TIMEOUT_MS}" \
          -et gin.edit.llm.LLMReplaceStatement \
          -mt "${LLM}" \
          -pc \
          -pt MEDIUM \
          -in 100 \
          -mn 10 \
          "${PATCHCAT_EXTRA_ARGS[@]}" \
          &> "${RESULTS_DIR}/${PROJECT_NAME}.LocalSearchRuntime_LLM_MEDIUM_50_stderrstdout.${MODEL}.txt"
    ;;

    *)
        echo "Option is unknown"
        exit 1
    ;;
esac
