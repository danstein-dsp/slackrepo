#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# installfunctions.sh - package install functions for slackrepo
#   install_packages
#   uninstall_packages
#   dotprofilizer
#-------------------------------------------------------------------------------

function install_packages
# Run installpkg if the package is not already installed,
# finding the package in either the package or the dryrun repository
# $1 = itempath
# Return status:
# 0 = installed ok or already installed
# 1 = install failed or not found
{
  local itempath="$1"
  local prgnam=${itempath##*/}

  # Look for the package(s).
  # Start with the temp output dir
  pkglist=$(ls $SR_TMPOUT/*.t?z 2>/dev/null)
  # If nothing there, look in the dryrun repo
  [ -z "$pkglist" -a "$OPT_DRYRUN" = 'y' ] &&
    pkglist=$(ls $DRYREPO/$itempath/*.t?z 2>/dev/null)
  # Finally, look in the proper package repo
  [ -z "$pkglist" ] && \
    pkglist=$(ls $SR_PKGREPO/$itempath/*.t?z 2>/dev/null)
  # should have something by now!
  [ -n "$pkglist" ] || { log_error -a "${itempath}: Can't find any packages to install"; return 1; }

  for pkgpath in $pkglist; do
    pkgbase=$(basename $pkgpath | sed 's/\.t.z$//')
    pkgid=$(echo $pkgbase | rev | cut -f4- -d- | rev )
    # Is it already installed? Find it in /var/log/packages
    if [ -f /var/log/packages/$pkgbase ]; then
      log_verbose -a "$pkgbase is already installed"
    elif [ -f /var/log/packages/${pkgid}-*-*-* ]; then
      log_verbose -a "Another version of $pkgid is already installed; upgrading ..."
      upgradepkg $pkgpath >>$ITEMLOG 2>&1
      stat=$?
      [ $stat = 0 ] || { log_error -a "${itempath}: upgradepkg $pkgbase failed (status $stat)"; return 1; }
      dotprofilizer $pkgpath
    else
      if [ "$OPT_VERBOSE" = 'y' ]; then
        installpkg --terse $pkgpath 2>&1 | tee -a $ITEMLOG
        stat=$?
      else
        installpkg --terse $pkgpath >>$ITEMLOG 2>&1
        stat=$?
      fi
      [ $stat = 0 ] || { log_error -a "${itempath}: installpkg $pkgbase failed (status $stat)"; return 1; }
      dotprofilizer $pkgpath
    fi
  done
  return 0
}

#-------------------------------------------------------------------------------

function uninstall_packages
# Run removepkg, and do extra cleanup
# $1 = itempath
# Return status: always 0
{
  local itempath="$1"
  local prgnam=${itempath##*/}

  if [ "${HINT_no_uninstall[$itempath]}" = 'y' ]; then return 0; fi

  # Look for the package(s).
  # Start with the temp output dir
  pkglist=$(ls $SR_TMPOUT/*.t?z 2>/dev/null)
  # If nothing there, look in the dryrun repo
  [ -z "$pkglist" -a "$OPT_DRYRUN" = 'y' ] &&
    pkglist=$(ls $DRYREPO/$itempath/*.t?z 2>/dev/null)
  # Finally, look in the proper package repo
  [ -z "$pkglist" ] && \
    pkglist=$(ls $SR_PKGREPO/$itempath/*.t?z 2>/dev/null)
  # should have something by now!
  [ -n "$pkglist" ] || { log_error -a "${itempath}: Can't find any packages to install"; return 1; }

  for pkgpath in $pkglist; do
    pkgbase=$(basename $pkgpath | sed 's/\.t.z$//')
    pkgid=$(echo $pkgbase | rev | cut -f4- -d- | rev )
    # Is it installed? Find it in /var/log/packages
    if [ -f /var/log/packages/$pkgbase ]; then

      # Save a list of potential detritus in /etc
      etcnewfiles=$(grep '^etc/.*\.new$' /var/log/packages/$pkgbase)
      etcdirs=$(grep '^etc/.*/$' /var/log/packages/$pkgbase)

      log_verbose -a "Uninstalling $pkgbase ..."
      removepkg $pkgbase >> $ITEMLOG 2>&1

      # Remove any surviving detritus
      for f in $etcnewfiles; do
        # (this is why we shouldn't run on an end user system!)
        rm -f /"$f" /"$(echo "$f" | sed 's/\.new$//')"
      done
      for d in $etcdirs; do
        if [ -d "$d" ]; then
          find "$d" -type d -depth -exec rmdir --ignore-fail-on-non-empty {} \;
        fi
      done

      # Do this last so it can mend things the package broke.
      # The cleanup file can contain any required shell commands, for example:
      #   * Reinstalling Slackware packages that conflict with prgnam
      #   * Unsetting environment variables set in an /etc/profile.d script
      #   * Removing specific files and directories that removepkg doesn't remove
      #   * Running depmod to remove references to removed kernel modules
      if [ -n "${HINT_cleanup[$itempath]}" ]; then
        . ${HINT_cleanup[$itempath]} >>$ITEMLOG 2>&1
      fi

    fi
  done

  return 0
}

#-------------------------------------------------------------------------------

function dotprofilizer
# Execute the /etc/profile.d scriptlets that came with a specific package
# $1 = path of package
# Return status: always 0
{
  local pkgpath="$1"
  # examine /var/log/packages/xxxx because it's quicker than looking inside a .t?z
  varlogpkg=/var/log/packages/$(basename $pkgpath | sed 's/\.t.z$//')
  if grep -q -E 'etc/profile\.d/.*\.sh(\.new)?' $varlogpkg; then
    for script in $(grep 'etc/profile\.d/.*\.sh' $varlogpkg | sed 's/.new$//'); do
      if [ -f /$script ]; then
        log_verbose -a "Running profile script /$script"
        . /$script
      elif [ -f /$script.new ]; then
        log_verbose -a "Running profile script /$script.new"
        . /$script.new
      fi
    done
  fi
  return
}
