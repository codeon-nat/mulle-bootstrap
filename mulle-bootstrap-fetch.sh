#! /bin/sh
#
#   Copyright (c) 2015 Nat! - Mulle kybernetiK
#   All rights reserved.
#
#   Redistribution and use in source and binary forms, with or without
#   modification, are permitted provided that the following conditions are met:
#
#   Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
#
#   Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
#
#   Neither the name of Mulle kybernetiK nor the names of its contributors
#   may be used to endorse or promote products derived from this software
#   without specific prior written permission.
#
#   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
#   AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
#   IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
#   ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
#   LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
#   CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
#   SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
#   INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
#   CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
#   ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
#   POSSIBILITY OF SUCH DAMAGE.

#
# this script installs the proper git clones into "clones"
# it does not to git subprojects.
# You can also specify a list of "brew" dependencies. That
# will be third party libraries, you don't tag or debug
#
. mulle-bootstrap-local-environment.sh
. mulle-bootstrap-brew.sh
. mulle-bootstrap-scripts.sh


usage()
{
   cat <<EOF
usage: fetch <install|nonrecursive|update> [repos]*
   install      : clone or symlink non-exisiting repositories and other resources
   nonrecursive : like above, but ignore .bootstrap folders of repositories
   update       : pull repositories

   You can specify the names of the repositories to update or fetch.
   Currently available names are:
EOF
   (cd "${CLONES_SUBDIR}" ; ls -1d ) 2> /dev/null
}


check_and_usage_and_help()
{
   case "$COMMAND" in
      install)
      ;;
      nonrecursive)
        COMMAND=install
        DONT_RECURSE="YES"
      ;;
      update)
      ;;
      *)
      usage >&2
      exit 1
      ;;
   esac
}


if [ "$1" = "-h" -o "$1" = "--help" ]
then
   COMMAND=help
else
   if [ -z "${COMMAND}" ]
   then
      COMMAND=${1:-"install"}
      [ $# -eq 0 ] || shift
   fi

   if [ "${MULLE_BOOTSTRAP}" = "mulle-bootstrap" ]
   then
      COMMAND="install"
   fi
fi

check_and_usage_and_help


#
# Use brews for stuff we don't tag
#
install_taps()
{
   local tap
   local taps
   local old

   log_fluff "Looking for taps"

   taps=`read_fetch_setting "taps" | sort | sort -u`
   if [ "${taps}" != "" ]
   then
      local old

      fetch_brew_if_needed

      old="${IFS:-" "}"
      IFS="
"
      for tap in ${taps}
      do
         exekutor brew tap "${tap}" > /dev/null || exit 1
      done
   else
      log_fluff "No taps found"
   fi
}


install_brews()
{
   local brew
   local brews

   install_taps

   log_fluff "Looking for brews"

   brews=`read_fetch_setting "brews" | sort | sort -u`
   if [ "${brews}" != "" ]
   then
      local old

      old="${IFS:-" "}"
      IFS="
"
      for brew in ${brews}
      do
         if [ "`which "${brew}"`" = "" ]
         then
            brew_update_if_needed "${brew}"

            log_fluff "brew ${COMMAND} \"${brew}\""
            exekutor brew "${COMMAND}" "${brew}" || exit 1
         else
            log_info "\"${brew}\" is already installed."
         fi
      done
      IFS="${old}"
   else
      log_fluff "No brews found"
   fi
}


#
# future, download tarballs...
# we check for existance during fetch, but install during build
#
check_tars()
{
   local tarballs
   local tar

   log_fluff "Looking for tarballs"

   tarballs="`read_fetch_setting "tarballs" | sort | sort -u`"
   if [ "${tarballs}" != "" ]
   then
      local old

      old="${IFS:-" "}"
      IFS="
"
      for tar in ${tarballs}
      do
         if [ ! -f "$tar" ]
         then
            fail "tarball \"$tar\" not found"
         fi
         log_fluff "tarball \"$tar\" found"
      done
      IFS="${old}"
   else
      log_fluff "No tarballs found"
   fi
}


#
# Use gems for stuff we don't tag
#
install_gems()
{
   local gems
   local gem

   log_fluff "Looking for gems"

   gems="`read_fetch_setting "gems" | sort | sort -u`"
   if [ "${gems}" != "" ]
   then
      local old

      old="${IFS:-" "}"
      IFS="
"
      for gem in ${gems}
      do
         log_fluff "gem install \"${gem}\""

         echo "gem needs sudo to install ${gem}" >&2
         exekutor sudo gem install "${gem}" || exit 1
      done
      IFS="${old}"
   else
      log_fluff "No gems found"
   fi
}


#
# Use pips for stuff we don't tag
#
install_pips()
{
   local pips
   local pip

   log_fluff "Looking for pips"

   pips="`read_fetch_setting "pips" | sort | sort -u`"
   if [ "${pips}" != "" ]
   then
      local old

      old="${IFS:-" "}"
      IFS="
"
      for pip in ${pips}
      do
         log_fluff "pip install \"${gem}\""

         echo "pip needs sudo to install ${pip}" >&2
         exekutor sudo pip install "${pip}" || exit 1
      done
      IFS="${old}"
   else
      log_fluff "No pips found"
   fi
}

#
###
#
link_command()
{
   local src
   local dst
   local tag

   src="$1"
   dst="$2"
   tag="$3"

   local dstdir
   dstdir="`dirname "${dst}"`"

   if [ ! -e "${dstdir}/${src}" ]
   then
      fail "${C_RESET}${dstdir}/${src}${C_ERROR} does not exist ($PWD)"
   fi

   if [ "${COMMAND}" = "install" ]
   then
      #
      # relative paths look nicer, but could fail in more complicated
      # settings, when you symlink something, and that repo has symlinks
      # itself
      #
      if read_yes_no_config_setting "absolute_symlinks" "NO"
      then
         local real

         real="`( cd "${dstdir}" ; realpath "${src}")`"
         log_fluff "Converted symlink ${C_RESET}${src}${C_FLUFF} to ${C_RESET}${real}${C_FLUFF}"
         src="${real}"
      fi

      exekutor ln -s -f "$src" "$dst" || fail "failed to setup symlink \"$dst\" (to \"$src\")"
      if [ "$tag" != "" ]
      then
         local name

         name="`basename "${dst}"`"
         log_warning "tag ${tag} will be ignored, due to symlink" >&2
         log_warning "if you want to checkout this tag do:" >&2
         log_warning "${C_RESET}(cd .repos/${name}; git ${GITFLAGS} checkout \"${tag}\" )${C_WARNING}" >&2
      fi
   fi

   # when we link, we assume that dependencies are there
}


ask_symlink_it()
{
   local  clone

   clone="$1"
   if [ ! -d "${clone}" ]
   then
      fail "You need to check out ${clone} yourself, as it's not there."
   fi

   # check if checked out
   if [ -d "${clone}"/.git ]
   then
      flag=1  # mens clone it
      if [ "${SYMLINK_FORBIDDEN}" != "YES" ]
      then
         user_say_yes "Should ${clone} be symlinked instead of cloned ?
   You usually say NO to this, even more so, if tag is set (tag=${tag})"
         flag=$?
      fi
      [ $flag -eq 0 ]
      return $?
   fi

    # if bare repo, we can only clone anyway
   if [ -f "${clone}"/HEAD -a -d "${clone}/refs" ]
   then
      log_info "${clone} looks like a bare git repository. So cloning"
      log_info "is the only way to go."
      return 1
   fi

   # can only symlink because not a .git repo yet
   if [ "${SYMLINK_FORBIDDEN}" != "YES" ]
   then
      log_info "${clone} is not a git repository (yet ?)"
      log_info "So symlinking is the only way to go."
      return 0
   fi

   fail "Can't symlink"
}


git_checkout_tag()
{
   local dst
   local tag

   dst="$1"
   tag="$2"

   log_info "Checking out ${C_MAGENTA}${tag}${C_INFO} ..."
   ( exekutor cd "${dst}" ; exekutor git checkout ${GITFLAGS} "${tag}" )

   if [ $? -ne 0 ]
   then
      log_error "Checkout failed, moving ${C_CYAN}${dst}${C_ERROR} to {C_CYAN}${dst}.failed${C_ERROR}"
      log_error "You need to fix this manually and then move it back."
      log_info "Hint: check ${BOOTSTRAP_SUBDIR}/`basename "${dst}"`/TAG" >&2

      rmdir_safer "${dst}.failed"
      exekutor mv "${dst}" "${dst}.failed"
      exit 1
   fi
}


git_clone()
{
   local src
   local dst
   local tag

   src="$1"
   dst="$2"
   tag="$3"

   [ ! -z "$src" ] || internal_fail "src is empty"
   [ ! -z "$dst" ] || internal_fail "dst is empty"

   log_info "Cloning ${C_MAGENTA}${src}${C_INFO} ..."
   exekutor git clone ${GITFLAGS} "${src}" "${dst}" || fail "git clone of \"${src}\" into \"${dst}\" failed"

   if [ "${tag}" != "" ]
   then
      git_checkout_tag "${dst}" "${tag}"
   fi
}


git_pull()
{
   local dst
   local tag

   dst="$1"
   tag="$2"

   [ ! -z "$dst" ] || internal_fail "dst is empty"

   log_info "Updating ${C_RESET}${dst}${C_INFO} ..."
   ( exekutor cd "${dst}" ; exekutor git pull ${GITFLAGS} ) || fail "git pull of \"${dst}\" failed"

   if [ "${tag}" != "" ]
   then
      git_checkout_tag "${dst}" "${tag}"
   fi
}


INHERIT_SETTINGS="taps brews gits pips gems settings/build_order settings/build_ignore"


bootstrap_auto_update()
{
   local dst

   dst="$1"

   [ ! -z "${dst}" ] || internal_fail "dst was empty"
   [ "${PWD}" != "${dst}" ] || internal_fail "configuration error"

   local name

   name="`basename "${dst}"`"

   # contains own bootstrap ? and not a symlink
   if [ ! -d "${dst}/.bootstrap" ] # -a ! -L "${dst}" ]
   then
      log_fluff "no .bootstrap folder in \"${dst}\" found"
      return 1
   fi

   log_info "Recursively acquiring ${dstdir} .bootstrap settings ..."

   # prepare auto folder if it doesn't exist yet
   if [ ! -d "${BOOTSTRAP_SUBDIR}.auto" ]
   then
      log_info "Found a .bootstrap folder for `basename "${dst}"` will set up ${BOOTSTRAP_SUBDIR}.auto"

      mkdir_if_missing "${BOOTSTRAP_SUBDIR}.auto/settings"
      for i in $INHERIT_SETTINGS
      do
         if [ -f "${BOOTSTRAP_SUBDIR}.local/${i}" ]
         then
            exekutor cp "${BOOTSTRAP_SUBDIR}}.local/${i}" "${BOOTSTRAP_SUBDIR}.auto/${i}" || exit 1
         else
            if [ -f "${BOOTSTRAP_SUBDIR}/${i}" ]
            then
               exekutor cp "${BOOTSTRAP_SUBDIR}/${i}" "${BOOTSTRAP_SUBDIR}.auto/${i}" || exit 1
            fi
         fi
      done
   fi

   #
   # prepend new contents to old contents
   # of a few select and known files
   #
   local srcfile
   local dstfile
   local i

   for i in $INHERIT_SETTINGS
   do
      srcfile="${dst}/.bootstrap/${i}"
      dstfile="${BOOTSTRAP_SUBDIR}.auto/${i}"
      if [ -f "${srcfile}" ]
      then
         log_fluff "Inheriting \"`basename ${i}`\" from \"${srcfile}\""

         mkdir_if_missing "${BOOTSTRAP_SUBDIR}.auto/`dirname "${i}"`"
         if [ -f "${BOOTSTRAP_SUBDIR}.auto/${i}" ]
         then
            local tmpfile

            tmpfile="${BOOTSTRAP_SUBDIR}.auto/${i}.tmp"

            exekutor mv "${dstfile}" "${tmpfile}" || exit 1
            exekutor cat "${srcfile}" "${tmpfile}" > "${dstfile}"  || exit 1
            exekutor rm "${tmpfile}" || exit 1
         else
            exekutor cp "${srcfile}" "${dstfile}" || exit 1
         fi
      fi
   done

   #
   # link up other non-inheriting settings
   #
   if dir_has_files "${dst}/.bootstrap/settings"
   then
      local relative

      log_fluff "Link up build settings of \"${name}\" to \"${BOOTSTRAP_SUBDIR}.auto/settings/${name}\""

      mkdir_if_missing "${BOOTSTRAP_SUBDIR}.auto/settings/${name}"
      relative="`compute_relative "${BOOTSTRAP_SUBDIR}"`"
      exekutor find "${dst}/.bootstrap/settings" -xdev -mindepth 1 -maxdepth 1 -type f -print0 | \
         exekutor xargs -0 -I % ln -s -f "${relative}/../../"% "${BOOTSTRAP_SUBDIR}.auto/settings/${name}"

      if [ -e "${dst}/.bootstrap/settings/bin"  ]
      then
         exekutor ln -s -f "${relative}/../../${dst}/.bootstrap/settings/bin" "${BOOTSTRAP_SUBDIR}.auto/settings/${name}"
      fi

      # flatten other folders into our own settings
      # don't force though, keep first
      exekutor find "${dst}/.bootstrap/settings" -xdev -mindepth 1 -maxdepth 1 -type d -print0 | \
         exekutor xargs -0 -I % ln -s "${relative}/../"% "${BOOTSTRAP_SUBDIR}.auto/settings"
   fi

   return 0
}


ensure_clones_directory()
{
   if [ ! -d "${CLONES_FETCH_SUBDIR}" ]
   then
      if [ "${COMMAND}" = "update" ]
      then
         fail "install first before upgrading"
      fi
      mkdir_if_missing "${CLONES_FETCH_SUBDIR}"
   fi

   if [ -d "${BOOTSTRAP_SUBDIR}.auto" ]
   then
      log_warning "Folder ${C_RESET}${BOOTSTRAP_SUBDIR}.auto${C_WARNING} already exists!"
   fi
}


#
# used to do this with chmod -h, alas Linux can't do that
# So we create a special directory .zombies
# and create files there
#
mark_all_zombies()
{
   local i
   local name

      # first mark all repos as stale
   if dir_has_files "${CLONES_FETCH_SUBDIR}"
   then
      log_fluff "Marking all repositories as zombies for now"

      mkdir_if_missing "${CLONES_FETCH_SUBDIR}/.zombies"

      for i in `ls -1d "${CLONES_FETCH_SUBDIR}/"*`
      do
         if [ -d "${i}" -o -L "${i}" ]
         then
            name="`basename "${i}"`"
            exekutor touch "${CLONES_FETCH_SUBDIR}/.zombies/${name}"
         fi
      done
   fi
}


mark_alive()
{
   local dstdir
   local name

   name="$1"
   dstdir="$2"

   local permission
   local zombie

   zombie="`dirname "${dstdir}"`/.zombies/${name}"

   # mark as alive
   if [ -d "${dstdir}" -o -L "${dstdir}" ]
   then
      if [ -e "${zombie}" ]
      then
         log_fluff "Mark ${C_RESET}${dstdir}${C_FLUFF} as alive"

         exekutor rm -f "${zombie}" || fail "failed to delete zombie ${zombie}"
      else
         log_fluff "Marked ${C_RESET}${dstdir}${C_FLUFF} is already alive"
      fi
   else
      log_fluff "${C_RESET}${dstdir}${C_FLUFF} is neither a symlink nor a directory"
   fi
}


log_fetch_action()
{
   local dstdir
   local clone

   clone="$1"
   dstdir="$2"

   local info

   if [ -L "${clone}" ]
   then
      info=" symlinked "
   else
      info=" "
   fi

   log_fluff "Perform ${COMMAND}${info}${clone} in ${dstdir} ..."
}


checkout()
{
   local clone
   local name
   local tag
   local dstdir

   clone="$1"
   name="$2"
   dstdir="$3"
   tag="$4"

   [ ! -z "$clone" ]  || internal_fail "clone is empty"
   [ ! -z "$name" ]   || internal_fail "name is empty"
   [ ! -z "$dstdir" ] || internal_fail "dstdir is empty"

   local srcname
   local operation
   local flag
   local found
   local name2
   local relative

   relative="`dirname "${dstdir}"`"
   relative="`compute_relative "${relative}"`"
   if [ ! -z "${relative}" ]
   then
      relative="${relative}/"
   fi
   name2="`basename "${clone}"`"

   #
   # this implicitly ensures, that these folders are
   # movable and cleanable by mulle-bootstrap
   # so ppl can't really use  src mistakenly

   if [ -e "${DEPENDENCY_SUBDIR}" -o -e "${CLONESBUILD_SUBDIR}" ]
   then
      log_error "Stale folders ${C_RESET}${DEPENDENCY_SUBDIR}${C_ERROR} and/or ${C_RESET}${CLONESBUILD_SUBDIR}${C_ERROR} found."
      log_error "Please remove them before continuing."
      log_info  "Suggested command: ${C_RESET}mulle-bootstrap clean output${C_INFO}"
      exit 1
   fi

   srcname="${clone}"
   script="`find_repo_setting_file "${name}" "bin/${COMMAND}.sh"`"
   operation="git_clone"

   if [ ! -z "${script}" ]
   then
      run_script "${script}" "$@"
   else
      case "${clone}" in
         /*)
            ask_symlink_it "${clone}"
            if [ $? -eq 0 ]
            then
               operation=link_command
            fi
         ;;

         ../*|./*)
            ask_symlink_it "${clone}"
            if [ $? -eq 0 ]
            then
               operation=link_command
               srcname="${relative}${clone}"
            fi
         ;;

         *)
            found="../${name}.${tag}"
            if [ ! -d "${found}" ]
            then
               found="../${name}"
               if [ ! -d "${found}" ]
               then
                  found="../${name2}.${tag}"
                  if [ ! -d "${found}" ]
                  then
                     found="../${name2}"
                     if [ ! -d "${found}" ]
                     then
                        found=""
                     fi
                  fi
               fi
            fi

            if [ "${found}" != ""  ]
            then
               user_say_yes "There is a ${found} folder in the parent
directory of this project.
Use it ?"
               if [ $? -eq 0 ]
               then
                  srcname="${found}"
                  ask_symlink_it "${srcname}"
                  if [ $? -eq 0 ]
                  then
                     operation=link_command
                     srcname="${relative}${found}"
                  fi
               fi
            fi
         ;;
      esac

      "${operation}" "${srcname}" "${dstdir}" "${tag}"
      mulle-bootstrap-warn-scripts.sh "${dstdir}/.bootstrap" "${dstdir}" || fail "Ok, aborted"  #sic
   fi
}


#
# Use git clones for stuff that gets tagged
# if you specify ../ it will assume you have
# checked it out yourself, If there is something
# checked out already it will use it, or ask
# convention: .git suffix == repo to clone
#          no .git suffix, try to symlink
#
checkout_repository()
{
   local dstdir
   local name
   local flag

   name="$2"
   dstdir="$3"

   if [ ! -e "${dstdir}" ]
   then
      checkout "$@"
      flag=1

      if [ "${COMMAND}" = "install" -a "${DONT_RECURSE}" = "" ]
      then
         bootstrap_auto_update "${dstdir}"
         flag=$?
      fi

      run_build_settings_script "${name}" "${dstdir}" "post-${COMMAND}" "$@"

      # means we recursed and should start fetch from top
      if [ ${flag} -eq 0 ]
      then
         return 1
      fi

   else
      log_fluff "Repository ${C_RESET}${dstdir}${C_FLUFF} already exists"
   fi
   return 0
}


clone_repository()
{
   local clone

   clone="$1"

   local name
   local tag
   local dstdir

   name="`basename "${clone}" .git`"
   tag="`read_repo_setting "${name}" "tag"`" #repo (sic)
   dstdir="${CLONES_FETCH_SUBDIR}/${name}"
   mark_alive "${name}" "${dstdir}"
   log_fetch_action "${name}" "${dstdir}"

   checkout_repository "${clone}" "${name}" "${dstdir}" "${tag}"
}


did_clone_repository()
{
   local clone

   clone="$1"

   local name
   local dstdir

   name="`basename "${clone}" .git`"
   dstdir="${CLONES_FETCH_SUBDIR}/${name}"

   run_build_settings_script "${name}" "${dstdir}" "did-install" "${dstdir}" "${name}"
}


clone_repositories()
{
   local stop
   local clones
   local clone

   mark_all_zombies

   stop=0
   while [ $stop -eq 0 ]
   do
      stop=1

      clones="`read_fetch_setting "gits"`"
      if [ "${clones}" != "" ]
      then
         ensure_clones_directory

         for clone in ${clones}
         do
            clone_repository "${clone}"
            if [ $? -eq 1 ]
            then
               stop=0
               break
            fi
         done
      fi
   done

   clones="`read_fetch_setting "gits"`"
   for clone in ${clones}
   do
      did_clone_repository "${clone}"
   done
}


install_subgits()
{
   local clones
   local clone

   clones="`read_fetch_setting "subgits"`"
   if [ "${clones}" != "" ]
   then
      for clone in ${clones}
      do
         name="`basename "${clone}" .git`"
         tag="`read_repo_setting "${name}" "tag"`" #repo (sic)
         dstdir="${name}"
         log_fetch_action "${name}" "${dstdir}"

         #
         # subgits are just cloned, no symlinks,
         #
         local old

         old="${SYMLINK_FORBIDDEN}"

         SYMLINK_FORBIDDEN="YES"
         checkout "${clone}" "${name}" "${dstdir}" "${tag}"
         SYMLINK_FORBIDDEN="$old"

         if read_yes_no_config_setting "update_gitignore" "YES"
         then
            if [ -d .git ]
            then
               append_dir_to_gitignore_if_needed "${dstdir}"
            fi
         fi
      done
   fi
}


update()
{
   local clone
   local name
   local tag
   local dstdir

   clone="$1"
   name="$2"
   dstdir="$3"
   tag="$4"

   [ ! -z "$clone" ]         || internal_fail "clone is empty"
   exekutor [ -d "$dstdir" ] || internal_fail "dstdir \"${dstdir}\" is wrong ($PWD)"
   [ ! -z "$name" ]          || internal_fail "name is empty"

   local script

   log_info "Updating \"${dstdir}\""
   if [ ! -L "${dstdir}"  ]
   then
      run_repo_settings_script "${name}" "${dstdir}" "pre-update" "%@"

      script="`find_repo_setting_file "${name}" "bin/update.sh"`"
      if [ ! -z "${script}" ]
      then
         run_script "${script}" "$@"
      else
         exekutor git_pull "${dstdir}" "${tag}"
      fi

      run_repo_settings_script "${name}" "${dstdir}" "post-update" "%@"
   fi
}


update_repository()
{
   local clone

   clone="$1"

   local name
   local tag
   local dstdir

   name="`basename "${clone}" .git`"
   tag="`read_repo_setting "${name}" "tag"`" #repo (sic)

   dstdir="${CLONES_FETCH_SUBDIR}/${name}"
   exekutor [ -e "${dstdir}" ] || fail "You need to install first, before updating"
   exekutor [ -x "${dstdir}" ] || fail "${name} is not anymore in \"gits\""

   log_fetch_action "${clone}" "${dstdir}"

   update "${clone}" "${name}" "${dstdir}" "${tag}"
}


did_update_repository()
{
   local clone

   clone="$1"

   local name
   local dstdir

   name="`basename "${clone}" .git`"
   dstdir="${CLONES_FETCH_SUBDIR}/${name}"

   run_build_settings_script "${name}" "${dstdir}" "did-update" "${dstdir}" "${name}"
}


#
# Use git clones for stuff that gets tagged
# if you specify ../ it will assume you have
# checked it out yourself, If there is something
# checked out already it will use it, or ask
# convention: .git suffix == repo to clone
#          no .git suffix, try to symlink
#
update_repositories()
{
   local clones
   local clone
   local name
   local i

   if [ $# -ne 0 ]
   then
      for name in "$@"
      do
         update_repository "${name}"
      done

      for name in "$@"
      do
         did_update_repository "${name}"
      done
   else
      clones="`read_fetch_setting "gits"`"
      if [ "${clones}" != "" ]
      then
         for clone in ${clones}
         do
            update_repository "${clone}"
         done

         # reread because of auto
         clones="`read_fetch_setting "gits"`"
         for clone in ${clones}
         do
            did_update_repository "${clone}"
         done
      fi
   fi
}


update_subgits()
{
   local clones
   local clone

   clones="`read_fetch_setting "subgits"`"
   if [ "${clones}" != "" ]
   then
      for clone in ${clones}
      do
         name="`basename "${clone}" .git`"
         tag="`read_repo_setting "${name}" "tag"`" #repo (sic)
         dstdir="${name}"
         log_fetch_action "${name}" "${dstdir}"

         # again, just refresh no specialties
         exekutor git_pull "${dstdir}" "${tag}"
      done
   fi
}


append_dir_to_gitignore_if_needed()
{
   grep -s -x "$1/" .gitignore > /dev/null 2>&1
   if [ $? -ne 0 ]
   then
      exekutor echo "$1/" >> .gitignore || fail "Couldn't append to .gitignore"
      log_info "Added ${C_MAGENTA}$1/${C_INFO} to ${C_CYAN}.gitignore${C_INFO}"
   fi
}


main()
{
   log_fluff "::: fetch :::"

   SYMLINK_FORBIDDEN="`read_config_setting "symlink_forbidden"`"
   export SYMLINK_FORBIDDEN

   #
   # Run prepare scripts if present
   #
   if [ "${COMMAND}" = "install" ]
   then
      if [ $# -ne 0 ]
      then
         log_error  "Additional parameters not allowed for install"
         usage >&2
         exit 1
      fi

      clone_repositories

      install_subgits
      install_brews
      install_gems
      install_pips
      check_tars
   else
      update_repositories "$@"

      update_subgits
   fi

   #
   # Run prepare scripts if present
   #
   run_fetch_settings_script "post-${COMMAND}" "%@"

   if read_yes_no_config_setting "update_gitignore" "YES"
   then
      if [ -d .git ]
      then
         append_dir_to_gitignore_if_needed "${BOOTSTRAP_SUBDIR}.auto"
         append_dir_to_gitignore_if_needed "${BOOTSTRAP_SUBDIR}.local"
         append_dir_to_gitignore_if_needed "${DEPENDENCY_SUBDIR}"
         append_dir_to_gitignore_if_needed "${CLONES_SUBDIR}"
      fi
   fi
}

main "$@"
