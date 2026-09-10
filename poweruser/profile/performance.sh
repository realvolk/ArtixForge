#!/usr/bin/env bash

ARTIX_CFLAGS="-O3 -march=native -flto=auto -fomit-frame-pointer -pipe"
ARTIX_CXXFLAGS="${ARTIX_CFLAGS}"
ARTIX_LDFLAGS="-Wl,-O1,--sort-common,--as-needed"
ARTIX_MAKEFLAGS="$(nproc)"
GLOBAL_FEATURES="lto"