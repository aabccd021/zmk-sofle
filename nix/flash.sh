# shellcheck shell=bash
# Flash firmware to nice_nano_v2
# UF2_FILE is set via Nix string interpolation

echo "Waiting for nice_nano_v2 bootloader..."
echo "Double-tap reset button on your keyboard"

while true; do
  MOUNT_POINT=$(lsblk -o NAME,LABEL,MOUNTPOINT -r | grep -i "NICENANO" | awk '{print $3}')
  if [ -n "$MOUNT_POINT" ] && [ -d "$MOUNT_POINT" ]; then
    break
  fi
  sleep 0.5
done

echo "Found bootloader at $MOUNT_POINT"
echo "Flashing $UF2_FILE..."

cp "$UF2_FILE" "$MOUNT_POINT/"
sync

echo "Done! Keyboard will reboot automatically."
