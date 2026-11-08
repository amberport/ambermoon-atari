#!/bin/sh
# Build the crash reader BOMBEN.TOS (test T109, docs/05c-ST.md) into
# build/st_bomben/.  Standalone, without Thalion's source.
set -e
cd "$(dirname "$0")"
ZIEL=../../build/st_bomben
mkdir -p $ZIEL
vasmm68k_mot -m68000 -Fvobj -quiet -o $ZIEL/bomben.o bomben.s
vlink -b ataritos -s -o $ZIEL/BOMBEN.TOS $ZIEL/bomben.o
rm -f $ZIEL/bomben.o
ls -l $ZIEL/BOMBEN.TOS
