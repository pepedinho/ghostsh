#!/bin/bash

PROJECT_ROOT="$(pwd)"
GSH="${PROJECT_ROOT}/zig-out/bin/gsh"
TEMP_DIR="/tmp/gsh_tests"

C_GREEN='\033[0;32m'
C_RED='\033[0;31m'
C_BLUE='\033[0;34m'
C_YELLOW='\033[0;33m'
C_RESET='\033[0m'

echo -e "${C_BLUE}======================================${C_RESET}"
echo -e "${C_BLUE}Starting GSH Integration Tests${C_RESET}"
echo -e "${C_BLUE}======================================${C_RESET}\n"

mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR" || exit 1

run_test() {
  local test_name="$1"
  local command="$2"
  local expected_output="$3"

  echo -n -e "Test: ${test_name}... "

  local stdout_file="${TEMP_DIR}/out.log"
  local stderr_file="${TEMP_DIR}/err.log"

  echo -e "$command\n" | $GSH >"$stdout_file" 2>"$stderr_file"
  local exit_code=$?

  if [ $exit_code -eq 42 ]; then
    echo -e "[ ${C_RED}FAIL - MEMORY LEAK${C_RESET} ]"
    cat "$stderr_file"
    exit 1
  fi

  if [ $exit_code -gt 128 ]; then
    echo -e "[ ${C_RED}FAIL - CRASH (Code $exit_code)${C_RESET} ]"
    exit 1
  fi

  local actual_output
  actual_output=$(cat "$stdout_file" | tr -d '\0')

  if [ -z "$expected_output" ]; then
    # When no expected output is provided, require that there is no
    # non-whitespace output on stdout.
    if echo "$actual_output" | grep -q '[^[:space:]]'; then
      echo -e "[ ${C_RED}FAIL - LOGIC${C_RESET} ]"
      echo -e "   ${C_YELLOW}Expected (partial) :${C_RESET} '' (no output)"
      echo -e "   ${C_YELLOW}Received           :${C_RESET} '$actual_output'"
      echo -e "   ${C_RED}Errors (stderr)    :${C_RESET}"
      sed 's/^/      /' "$stderr_file"
      exit 1
    else
      echo -e "[ ${C_GREEN}OK${C_RESET} ]"
    fi
  else
    if echo "$actual_output" | grep -Fq "$expected_output"; then
      echo -e "[ ${C_GREEN}OK${C_RESET} ]"
    else
      echo -e "[ ${C_RED}FAIL - LOGIC${C_RESET} ]"
      echo -e "   ${C_YELLOW}Expected (partial) :${C_RESET} '$expected_output'"
      echo -e "   ${C_YELLOW}Received           :${C_RESET} '$actual_output'"
      echo -e "   ${C_RED}Errors (stderr)    :${C_RESET}"
      sed 's/^/      /' "$stderr_file"
      exit 1
    fi
  fi
}

echo -e "${C_YELLOW}--- Builtin Tests ---${C_RESET}"

run_test "cd (absolute path)" \
  "cd /tmp && /bin/pwd" \
  "/tmp"

run_test "cd (without argument goes to HOME)" \
  "cd && /bin/pwd" \
  "$HOME"

echo -e "\n${C_YELLOW}--- AST and Execution Tests ---${C_RESET}"

run_test "Simple command" \
  "echo hello_world" \
  "hello_world"

run_test "Basic pipeline" \
  "echo 'data_to_pipe' | grep data" \
  "data_to_pipe"

run_test "Logical AND operator (&&)" \
  "true && echo 'success_and'" \
  "success_and"

run_test "Logical AND operator (&&) short-circuit" \
  "false && echo 'should_not_print'" \
  ""

echo -e "\n${C_YELLOW}--- Stress and Memory Resilience Tests ---${C_RESET}"
echo -n -e "Test: Generating 10000 commands... "

cat <<'EOF' >stress.gsh
for i in $(seq 1 10000); do
    echo "echo stress_test_$i > /dev/null"
done
EOF
bash stress.gsh >payload.gsh

# Launch GSH in the background to monitor memory
$GSH <payload.gsh >/dev/null 2>stress_err.log &
GSH_PID=$!

PEAK_MEM=0
TOTAL_MEM=0
COUNT=0

# Monitor loop while the process is alive
while kill -0 $GSH_PID 2>/dev/null; do
  CURRENT_MEM=$(ps -o rss= -p $GSH_PID 2>/dev/null | tr -d ' ')
  if [[ "$CURRENT_MEM" =~ ^[0-9]+$ ]]; then
    if [ "$CURRENT_MEM" -gt "$PEAK_MEM" ]; then
      PEAK_MEM=$CURRENT_MEM
    fi
    TOTAL_MEM=$((TOTAL_MEM + CURRENT_MEM))
    COUNT=$((COUNT + 1))
  fi
  sleep 0.01
done

wait $GSH_PID
stress_exit=$?

AVG_MEM=0
if [ $COUNT -gt 0 ]; then
  AVG_MEM=$((TOTAL_MEM / COUNT))
fi

PEAK_MB=$(awk "BEGIN {printf \"%.2f\", $PEAK_MEM/1024}")
AVG_MB=$(awk "BEGIN {printf \"%.2f\", $AVG_MEM/1024}")

if [ $stress_exit -eq 42 ]; then
  echo -e "[ ${C_RED}FAIL - MEMORY LEAK DETECTED${C_RESET} ]"
  cat stress_err.log
  exit 1
elif [ $stress_exit -ne 0 ]; then
  echo -e "[ ${C_RED}FAIL - CRASH (Code $stress_exit)${C_RESET} ]"
  exit 1
else
  echo -e "[ ${C_GREEN}OK${C_RESET} ]"
  echo -e "   ${C_BLUE}Memory Peak    :${C_RESET} ${PEAK_MB} MB"
  echo -e "   ${C_BLUE}Memory Average :${C_RESET} ${AVG_MB} MB"
  echo -e "   ${C_BLUE}Samples Taken  :${C_RESET} ${COUNT}"
fi

cd /tmp || exit
rm -rf "$TEMP_DIR"

echo -e "\n${C_GREEN}All integration tests passed!${C_RESET}"
