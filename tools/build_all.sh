#!/bin/sh
# The one build: the Falcon (tools/build_falcon.sh) and the ST
# (tools/build_st.sh) into the shared folder ATARI/ (tools/build_common.sh).
#
#   sh tools/build_all.sh
#   sh tools/build_all.sh ambermoone.zip                   these game files
#   VASM_EXTRA="-DZEIGERTAKT=1" sh tools/build_all.sh      diagnostic switch
#   TESTBUILDS=1 sh tools/build_all.sh                     with the test builds
#
# Sources are checked and the extracts from the original files written once,
# for both.
set -e
GAME_FILES_ARG=$1; CALLED_FROM=$PWD
cd "$(dirname "$0")/.."
. tools/build_common.sh

prepare all
_AMBER_PREPARED=1
export _AMBER_PREPARED
step_done
sh tools/build_falcon.sh
sh tools/build_st.sh
summary
