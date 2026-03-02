# shellcheck shell=bash
# Flash firmware to nice_nano_v2
# Usage: flash <left|right|dongle|reset-left|reset-right|reset-dongle>

set -euo pipefail

PART="${1:-}"

case "$PART" in
  left)
    SERIAL="0185553E293B1D17"
    FILE="sofle_left nice_view_adapter nice_view-nice_nano_v2-zmk.uf2"
    ;;
  right)
    SERIAL="ABBA719DF81D2968"
    FILE="sofle_right nice_view_adapter nice_view-nice_nano_v2-zmk.uf2"
    ;;
  dongle)
    SERIAL="189DE36E62D43928"
    FILE="sofle_dongle dongle_display-nice_nano_v2-zmk.uf2"
    ;;
  reset-left)
    SERIAL="0185553E293B1D17"
    FILE="settings_reset-nice_nano_v2-zmk.uf2"
    ;;
  reset-right)
    SERIAL="ABBA719DF81D2968"
    FILE="settings_reset-nice_nano_v2-zmk.uf2"
    ;;
  reset-dongle)
    SERIAL="189DE36E62D43928"
    FILE="settings_reset-nice_nano_v2-zmk.uf2"
    ;;
  *)
    echo "Usage: flash <left|right|dongle|reset-left|reset-right|reset-dongle>"
    exit 1
    ;;
esac

DEVICE_PATH="/dev/disk/by-id/usb-Adafruit_nRF_UF2_${SERIAL}-0:0"

if [ ! -e "$DEVICE_PATH" ]; then
  echo "Device '$PART' with serial ${SERIAL} not found"
  echo "Put the device in bootloader mode (double-tap reset button)"
  exit 1
fi

MOUNT_POINT=$(lsblk -o MOUNTPOINT -nr "$DEVICE_PATH" 2>/dev/null)
if [ -z "$MOUNT_POINT" ] || [ ! -d "$MOUNT_POINT" ]; then
  echo "Device found but not mounted"
  exit 1
fi

cp "${KEYBOARD}/${FILE}" "$MOUNT_POINT/"
sync
echo "Flashed $PART successfully!"
