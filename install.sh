#!/bin/sh
# POSIX-compliant version of Homebrew installer
# Note: This is a simplified version with core functionality

set -e

# Terminal formatting (simplified, POSIX-compatible)
if [ -t 1 ]
then
  tty_escape() { printf "\033[%sm" "$1"; }
else
  tty_escape() { :; }
fi
tty_mkbold() { tty_escape "1;$1"; }
tty_underline=$(tty_escape "4;39")
tty_blue=$(tty_mkbold 34)
tty_red=$(tty_mkbold 31)
tty_bold=$(tty_mkbold 39)
tty_reset=$(tty_escape 0)

# Functions
abort() {
  printf "%s\n" "$@" >&2
  exit 1
}

chomp() {
  printf "%s" "$1" | tr -d '\n'
}

ohai() {
  printf "${tty_blue}==>${tty_bold} %s${tty_reset}\n" "$*"
}

warn() {
  printf "${tty_red}Warning${tty_reset}: %s\n" "$(chomp "$1")" >&2
}

# Determine OS
OS=$(uname)
if [ "$OS" = "Linux" ]
then
  HOMEBREW_ON_LINUX=1
elif [ "$OS" = "Darwin" ]
then
  HOMEBREW_ON_MACOS=1
else
  abort "Homebrew is only supported on macOS and Linux."
fi

# Set installation paths
if [ -n "$HOMEBREW_ON_MACOS" ]
then
  UNAME_MACHINE=$(/usr/bin/uname -m)

  if [ "$UNAME_MACHINE" = "arm64" ]
  then
    # On ARM macOS, this script installs to /opt/homebrew only
    HOMEBREW_PREFIX="/opt/homebrew"
    HOMEBREW_REPOSITORY="${HOMEBREW_PREFIX}"
  else
    # On Intel macOS, this script installs to /usr/local only
    HOMEBREW_PREFIX="/usr/local"
    HOMEBREW_REPOSITORY="${HOMEBREW_PREFIX}/Homebrew"
  fi
  HOMEBREW_CACHE="${HOME}/Library/Caches/Homebrew"

  STAT="stat -f"
  CHOWN="/usr/sbin/chown"
  CHGRP="/usr/bin/chgrp"
  GROUP="admin"
else
  UNAME_MACHINE=$(uname -m)

  # On Linux, this script installs to /home/linuxbrew/.linuxbrew only
  HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
  HOMEBREW_REPOSITORY="${HOMEBREW_PREFIX}/Homebrew"
  HOMEBREW_CACHE="${HOME}/.cache/Homebrew"

  STAT="stat --printf"
  CHOWN="chown"
  CHGRP="chgrp"
  GROUP="$(id -gn)"
fi

# Check for sudo
have_sudo_access() {
  if [ ! -x "/usr/bin/sudo" ]; then
    return 1
  fi
  
  local SUDO_EXIT
  SUDO="/usr/bin/sudo"
  
  if [ -n "$SUDO_ASKPASS" ]; then
    SUDO="$SUDO -A"
  elif [ -n "$NONINTERACTIVE" ]; then
    SUDO="$SUDO -n"
  fi
  
  $SUDO -v && $SUDO -l mkdir >/dev/null 2>&1
  SUDO_EXIT="$?"
  
  if [ "$SUDO_EXIT" != "0" ] && [ -n "$HOMEBREW_ON_MACOS" ]; then
    abort "Need sudo access on macOS!"
  fi
  
  return "$SUDO_EXIT"
}

execute() {
  if ! "$@"
  then
    abort "Failed during: $*"
  fi
}

execute_sudo() {
  if [ "$(id -u)" != "0" ] && have_sudo_access
  then
    ohai "/usr/bin/sudo $*"
    /usr/bin/sudo "$@"
  else
    ohai "$*"
    "$@"
  fi
}

getc() {
  local save_state
  save_state=$(/bin/stty -g)
  /bin/stty raw -echo
  IFS= read -r -n 1 c
  /bin/stty "$save_state"
  echo "$c"
}

major_minor() {
  echo "${1%%.*}.${1#*.}" | cut -d. -f1,2
}

version_gt() {
  [ "$(echo "$1" | cut -d. -f1)" -gt "$(echo "$2" | cut -d. -f1)" ] || 
  [ "$(echo "$1" | cut -d. -f1)" -eq "$(echo "$2" | cut -d. -f1)" -a "$(echo "$1" | cut -d. -f2)" -gt "$(echo "$2" | cut -d. -f2)" ]
}

wait_for_user() {
  printf "Press RETURN/ENTER to continue or any other key to abort:\n"
  c=$(getc)
  if [ "$c" != "$(printf '\r')" ] && [ "$c" != "$(printf '\n')" ]; then
    exit 1
  fi
}

# Check if running as root
if [ "$(id -u)" = "0" ]; then
  # Allow running in Docker/Kubernetes environments
  if [ ! -f /.dockerenv ] && [ ! -f /run/.containerenv ] && ! grep -qE "docker|garden|kubepods" /proc/1/cgroup 2>/dev/null; then
    abort "Don't run this as root!"
  fi
fi

ohai 'Checking for `sudo` access (which may request your password)...'

if [ -n "$HOMEBREW_ON_MACOS" ]; then
  [ "$(id -u)" = "0" ] || have_sudo_access
elif [ ! -w "$HOMEBREW_PREFIX" ] && [ ! -w "/home/linuxbrew" ] && [ ! -w "/home" ] && ! have_sudo_access; then
  abort "Insufficient permissions to install Homebrew to \"$HOMEBREW_PREFIX\""
fi

# For Linux, check for required tools
if [ -n "$HOMEBREW_ON_LINUX" ]; then
  if ! command -v git >/dev/null; then
    abort "You must install Git before installing Homebrew."
  fi
  if ! command -v curl >/dev/null; then
    abort "You must install cURL before installing Homebrew."
  fi
fi

# Setup the directories
mkdir_or_sudo() {
  local dir=$1
  if [ -d "$dir" ]; then
    return
  fi
  
  if [ "$(id -u)" = "0" ]; then
    mkdir -p "$dir"
  elif have_sudo_access; then
    execute_sudo mkdir -p "$dir"
    execute_sudo chown "$(id -un)" "$dir"
    execute_sudo chgrp "$(id -gn)" "$dir"
  else
    mkdir -p "$dir"
  fi
}

# Create required directories
if [ -n "$HOMEBREW_ON_MACOS" ]; then
  for dir in \
    bin etc include lib sbin share opt var \
    Frameworks \
    etc/bash_completion.d lib/pkgconfig \
    share/aclocal share/doc share/info share/locale share/man \
    share/man/man1 share/man/man2 share/man/man3 share/man/man4 \
    share/man/man5 share/man/man6 share/man/man7 share/man/man8 \
    var/log var/homebrew var/homebrew/linked
  do
    mkdir_or_sudo "${HOMEBREW_PREFIX}/${dir}"
  done
else
  for dir in \
    bin etc include lib sbin share var opt \
    share/zsh share/zsh/site-functions \
    var/homebrew var/homebrew/linked \
    Cellar Caskroom Frameworks
  do
    mkdir_or_sudo "${HOMEBREW_PREFIX}/${dir}"
  done
fi

# Setup brew repository
if [ ! -d "$HOMEBREW_REPOSITORY" ]; then
  execute_sudo mkdir -p "$HOMEBREW_REPOSITORY"
fi
execute_sudo chown -R "$(id -un):$(id -gn)" "$HOMEBREW_REPOSITORY"

# Cache directory
if [ ! -d "$HOMEBREW_CACHE" ]; then
  if [ -n "$HOMEBREW_ON_MACOS" ]; then
    execute_sudo mkdir -p "$HOMEBREW_CACHE"
  else
    mkdir -p "$HOMEBREW_CACHE"
  fi
fi
if [ -n "$HOMEBREW_ON_MACOS" ]; then
  execute_sudo chown -R "$(id -un)" "$HOMEBREW_CACHE"
  execute_sudo chgrp -R "$GROUP" "$HOMEBREW_CACHE"
fi

# Download Homebrew
ohai "Downloading and installing Homebrew..."
(
  cd "$HOMEBREW_REPOSITORY" >/dev/null || exit
  
  # Initialize git repository
  git init --quiet
  git config remote.origin.url "https://github.com/Homebrew/brew"
  git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
  git config --bool core.autocrlf false
  git config --bool core.symlinks true
  
  # Fetch the repository
  git fetch --quiet --force origin
  git fetch --quiet --force --tags origin
  
  # Get latest tag
  LATEST_TAG=$(git tag | sort -V | tail -n1)
  if [ -z "$LATEST_TAG" ]; then
    abort "Failed to query latest Homebrew/brew Git tag."
  fi
  git checkout --quiet --force -B stable "$LATEST_TAG"
  
  # Link brew executable
  if [ "$HOMEBREW_REPOSITORY" != "$HOMEBREW_PREFIX" ]; then
    if [ "$HOMEBREW_REPOSITORY" = "$HOMEBREW_PREFIX/Homebrew" ]; then
      ln -sf "../Homebrew/bin/brew" "$HOMEBREW_PREFIX/bin/brew"
    else
      abort "The Homebrew/brew repository should be placed in the Homebrew prefix directory."
    fi
  fi
  
  # Run initial update
  "$HOMEBREW_PREFIX/bin/brew" update --force --quiet
) || exit 1

# Success message
ohai "Installation successful!"

# Show next steps
ohai "Next steps:"
if [ -n "$HOMEBREW_ON_LINUX" ]; then
  cat <<EOS
- Install Homebrew's dependencies if you have sudo access:
  - Debian/Ubuntu: sudo apt-get install build-essential
  - Fedora: sudo dnf group install 'Development Tools'
  - Red Hat/CentOS: sudo yum groupinstall 'Development Tools'
  - Arch: sudo pacman -S base-devel
  - Alpine: sudo apk add build-base

  For more information, see:
    ${tty_underline}https://docs.brew.sh/Homebrew-on-Linux${tty_reset}
EOS
fi

cat <<EOS
- Add Homebrew to your PATH by adding this to your profile:
    For bash/zsh:
    echo 'eval "\$(${HOMEBREW_PREFIX}/bin/brew shellenv)"' >> ~/.profile
    eval "\$(${HOMEBREW_PREFIX}/bin/brew shellenv)"

- Run ${tty_bold}brew help${tty_reset} to get started
- Further documentation:
    ${tty_underline}https://docs.brew.sh${tty_reset}
EOS
