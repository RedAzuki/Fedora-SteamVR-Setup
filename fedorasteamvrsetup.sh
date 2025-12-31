#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO: $BASH_COMMAND" >&2; exit 1' ERR

setupFedora() {
  echo "Install RPM Fusion repositories"
  dnf install -y \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

  echo "Setting up nonfree multimedia and codecs"
  echo "Multimedia and codec information can be found here: https://rpmfusion.org/Howto/Multimedia"
  echo "Swap to Non-Free ffmpeg"
  dnf swap -y ffmpeg-free ffmpeg --allowerasing

  echo "Install Restricted Codecs"
  dnf update -y @multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin

  echo "Swap to Nonfree AMD Hardware codecs"
  dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld
  dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld
  dnf swap -y mesa-vulkan-drivers mesa-vulkan-drivers-freeworld
  dnf swap -y mesa-va-drivers.i686 mesa-va-drivers-freeworld.i686
  dnf swap -y mesa-vdpau-drivers.i686 mesa-vdpau-drivers-freeworld.i686
  dnf swap -y mesa-vulkan-drivers.i686 mesa-vulkan-drivers-freeworld.i686

  echo "NOTICE: NVidia codecs setup not included in this script. Feel free to make a PR to add them..."
  echo "NOTICE: Intel codecs setup not included in this script. Feel free to make a PR to add them..."
}

setupSteam() {
  echo "Install Steam"
  dnf install -y steam

  local system_desktop="/usr/share/applications/steam.desktop"
  local user_dir="${SUDO_USER:+/home/$SUDO_USER/.local/share/applications}"
  local user_desktop="${user_dir}/steam.desktop"

  if [[ -z "${SUDO_USER:-}" || "${SUDO_USER}" == "root" ]]; then
    echo "Could not determine the non-root user (SUDO_USER). Run with: sudo $0" >&2
    exit 1
  fi

  if [[ ! -f "$system_desktop" ]]; then
    echo "System Steam desktop file not found at: $system_desktop" >&2
    exit 1
  fi

  mkdir -p "$user_dir"
  cp -f "$system_desktop" "$user_desktop"
  chown "$SUDO_USER:$SUDO_USER" "$user_dir" "$user_desktop"

  # Replace ONLY the plain Exec=/usr/bin/steam %U line
  # (Keeps other Exec entries like steam-runtime if present)
  sed -i -E \
    '0,/^Exec=(\/usr\/bin\/steam(-runtime)?|steam)( .*)?$/s//Exec=env RADV_PERFTEST=video_encode,video_decode \1\3/' \
    "$user_desktop"

  # Refresh desktop database for the target user (best effort)
  if command -v update-desktop-database >/dev/null 2>&1; then
    sudo -u "$SUDO_USER" update-desktop-database "${user_dir}" >/dev/null 2>&1 || true
  fi

  echo "✅ Patched Steam launcher for user: $SUDO_USER"
  echo "   $user_desktop"
  echo "   Exec=env RADV_PERFTEST=video_encode,video_decode /usr/bin/steam %U"
  echo
}

if [[ "$EUID" -ne 0 ]]; then
  echo "Please run this script with sudo:"
  echo "  sudo $0 $*"
  exit 1
fi

echo "This script will install or update your system so VR tools work on your computer."
read -rp "Are you sure you wish to continue? [y/N] " confirm

case "$confirm" in
  [yY]|[yY][eE][sS]) ;;
  *) echo "Aborted."; exit 0 ;;
esac

if [[ -r /etc/os-release ]]; then
  . /etc/os-release
else
  echo "Cannot detect operating system."
  exit 1
fi

if [[ "$ID" != "fedora" ]]; then
  echo "This script is intended for Fedora only."
  echo "Detected OS: ${PRETTY_NAME:-unknown}"
  exit 1
fi

echo
echo "It is recommended that you run system updates before continuing."
read -rp "Would you like to run OS updates now? [Y/n] " run_updates

case "$run_updates" in
  [nN]|[nN][oO])
    echo "Skipping system updates."
    ;;
  *)
    echo "Running system updates..."
    dnf -y upgrade
    ;;
esac

setupFedora
setupSteam

echo
echo "Complete! You may want to reboot your computer - especially if the kernel was updated"
echo

exit 0
