#!/usr/bin/env bash

ARTIX_CFLAGS="-O2 -march=x86-64 -mtune=generic -pipe"
ARTIX_CXXFLAGS="${ARTIX_CFLAGS}"
ARTIX_LDFLAGS="-Wl,-O1,--sort-common,--as-needed"
ARTIX_MAKEFLAGS="$(nproc)"
GLOBAL_FEATURES=""