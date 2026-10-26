#!/bin/zsh

# Kill whatever process is listening on a TCP port.
# Usage: kill-port.sh [port]

set -euo pipefail

port=${1:-}
if [[ -z $port ]]; then
  read -r "port?Port to free: "
fi

if [[ ! $port =~ ^[0-9]+$ ]]; then
  echo "Not a valid port: $port" >&2
  exit 1
fi

pids=(${(f)"$(lsof -ti tcp:$port -sTCP:LISTEN || true)"})
if (( ${#pids} == 0 )); then
  echo "Nothing is listening on port $port."
  exit 0
fi

for pid in $pids; do
  cmd=$(ps -o command= -p $pid 2>/dev/null || true)
  echo "port $port -> pid $pid: ${cmd:-unknown}"
done

read -r "reply?Kill ${#pids} process(es)? [y/N] "
[[ $reply == [yY] ]] || { echo "Aborted."; exit 0; }

kill $pids 2>/dev/null || true

for _ in {1..10}; do
  if [[ -z $(lsof -ti tcp:$port -sTCP:LISTEN || true) ]]; then
    echo "Port $port is free."
    exit 0
  fi
  sleep 0.2
done

echo "Still listening after SIGTERM, sending SIGKILL." >&2
kill -9 $pids 2>/dev/null || true
echo "Port $port is free."
