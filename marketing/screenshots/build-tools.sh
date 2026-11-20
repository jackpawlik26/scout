#!/bin/zsh
# Builds the two small helpers the capture scripts use (window list, mouse events) into bin/.
set -e
cd ${0:A:h}; mkdir -p bin
swiftc -O windows.swift -o bin/windows
swiftc -O mouse.swift -o bin/mouse
echo "Built bin/windows and bin/mouse"
