#!/usr/bin/env bash
#
# xghost — install a prescribed Arch Linux desktop.
#
# This script is the front end. The installer itself is lib/install.sh and the
# steps under install/steps/, and docs/installing.md records what each group
# does and why the order is what it is.
#
# Run it as the user who will use the desktop. The one step that needs root
# raises its own privileges.

set -euo pipefail

INSTALL_SCRIPT_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=lib/install.sh
. "$INSTALL_SCRIPT_DIR/lib/install.sh"

install_main "$@"
