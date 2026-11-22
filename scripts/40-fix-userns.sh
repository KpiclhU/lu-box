#!/usr/bin/env bash
# 40-fix-userns.sh — scoped AppArmor profile so the LU binary may create user namespaces.
#
#   sudo ./scripts/40-fix-userns.sh
#
# Only run this if the launch log shows a sandbox failure (bwrap / "operation not permitted" /
# "Failed to create namespace"). Ubuntu 24.04+ sets
# kernel.apparmor_restrict_unprivileged_userns=1, and an unconfined third-party binary cannot
# create the namespace WebKitGTK's web process sandbox needs.
#
# This grants userns to the LU executable and nothing else. It does not change the sysctl, so
# every other unconfined program keeps the restriction.
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }
say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

[ "$(id -u)" -eq 0 ] || die "run with sudo: sudo ./scripts/40-fix-userns.sh"
command -v apparmor_parser >/dev/null || die "apparmor_parser missing: sudo apt-get install -y apparmor apparmor-utils"

say "Setting"
if [ -r /proc/sys/kernel/apparmor_restrict_unprivileged_userns ]; then
  val=$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns)
  echo "kernel.apparmor_restrict_unprivileged_userns=$val"
  if [ "$val" = "0" ]; then
    echo "already permissive — nothing to do. Do not add a profile to work around something else."
    exit 0
  fi
else
  echo "the restriction is not present on this kernel — nothing to do."
  exit 0
fi

say "Binary"
pkg=$(dpkg-query -W -f='${Package}\n' 2>/dev/null | grep -iE 'locally[-.]?uncensored|^lu$' | head -1 || true)
[ -n "$pkg" ] || die "Locally Uncensored is not installed as a .deb (./scripts/20-install-lu.sh)"
bin=$(dpkg -L "$pkg" 2>/dev/null | grep -E '/(usr/)?bin/[^/]+$' | head -1 || true)
[ -n "$bin" ] && [ -x "$bin" ] || die "could not find the LU executable inside $pkg"
echo "package $pkg"
echo "binary  $bin"

profile="/etc/apparmor.d/${bin##*/}"

say "Profile"
if [ -f "$profile" ]; then
  echo "$profile already exists, rewriting it"
fi
cat > "$profile" <<EOF
# Installed by lu-box/40-fix-userns.sh
# Grants unprivileged user namespaces to this one executable so WebKitGTK's bwrap sandbox can
# start on Ubuntu 24.04+, where kernel.apparmor_restrict_unprivileged_userns=1 by default.
abi <abi/4.0>,
include <tunables/global>

profile ${bin##*/} $bin flags=(unconfined) {
  userns,

  include if exists <local/${bin##*/}>
}
EOF
chmod 644 "$profile"

if apparmor_parser -r "$profile"; then
  echo "loaded $profile"
else
  rm -f "$profile"
  die "apparmor_parser rejected the profile; removed it. Paste the error above when asking for help."
fi

cat <<EOF

Done. Restart LU from inside the desktop session:

  ./scripts/90-launch.sh

To undo: sudo rm $profile && sudo apparmor_parser -R $profile  (or reboot)
EOF
