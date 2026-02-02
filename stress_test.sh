#!/bin/bash
for i in {1..1000}; do
  if [ $((i % 100)) -eq 0 ]; then
    echo "echo $(head -c 2000 </dev/urandom | base64)"
  else
    echo "ls -l /tmp"
  fi
done
