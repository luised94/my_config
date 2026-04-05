#!/bin/bash
# 06_usb.sh -- Infrastructure: USB detection and project configuration
#
# This wrapper sources usb.sh from the usb-sh repository. It runs in the
# numbered bash/ chain BEFORE the extension loop (99_extensions.sh) so
# that modules like kbd.sh can read USB_* variables without sourcing
# usb.sh themselves.
#
# Why here and not in mc_extensions:
#   usb.sh is infrastructure that extensions depend on, not a peer
#   extension. Sourcing it in the extension loop caused double-source
#   (once from the loop, once from modules that also sourced it) and
#   confusing "already initialized" guard messages.
#
# Dependencies: ~/personal_repos/usb-sh/usb.sh
# Consumers: kbd.sh, any module using USB_* variables
# See also: ~/personal_repos/usb-sh/docs/usb-setup.md (Loading Architecture)
#
# If usb-sh is not cloned on this machine, USB features are unavailable
# and modules degrade gracefully via their own defensive checks.

if [[ -f "$HOME/personal_repos/usb-sh/usb.sh" ]]; then
    source "$HOME/personal_repos/usb-sh/usb.sh"
else
    echo "mc/usb: usb.sh file not available."
    export USB_CONNECTED=false
fi
