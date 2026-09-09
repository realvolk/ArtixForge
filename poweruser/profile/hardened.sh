#!/usr/bin/env bash

ARTIX_CFLAGS="-O2 -march=x86-64 -mtune=generic -pipe -fstack-protector-strong -D_FORTIFY_SOURCE=2 -fPIE"
ARTIX_CXXFLAGS="${ARTIX_CFLAGS}"
ARTIX_LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,relro,-z,now -pie"
ARTIX_MAKEFLAGS="$(nproc)"
GLOBAL_FEATURES="pie relro stack-protector"