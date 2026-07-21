# shellcheck shell=bash
# ------------------------------------------------------------------------------
# TITLE   : MC message shim (03_message.sh)
# PURPOSE : Load the message engine from lib/message.sh. Kept as a numbered
#           chain entry so load order and the msg_* contract are unchanged; the
#           implementation now lives in lib/message.sh (VERSION 1).
# ------------------------------------------------------------------------------
# shellcheck source=../lib/message.sh
source "$MC_ROOT/lib/message.sh"
