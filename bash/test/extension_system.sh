#!/bin/bash

# Setup
mkdir -p ~/.config/mc_extensions
mkdir -p ~/.config/mc_extensions/sample

# Test 1: Simple file extension
echo 'msg_info "test.sh loaded"' > ~/.config/mc_extensions/test.sh

# Test 2: Directory with dirname.sh entry point
echo 'msg_info "sample/sample.sh loaded"' > ~/.config/mc_extensions/sample/sample.sh

# Test 3: Skipped by prefix
echo 'msg_info "should not see this"' > ~/.config/mc_extensions/_disabled.sh

# Reload shell
source ~/.bashrc

# Verify
mc_extensions_status -v

# Cleanup (when done testing)
rm -rf ~/.config/mc_extensions/test.sh
rm -rf ~/.config/mc_extensions/sample
rm -rf ~/.config/mc_extensions/_disabled.sh
