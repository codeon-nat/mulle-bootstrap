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
MULLE_BOOTSTRAP_BREW_SH="included"



_brew_usage()
{
   cat <<EOF >&2
usage:
   mulle-brew ${COMMAND} [options] [repositories]

   Options
      -cs   :  check /usr/local for duplicates

   You can specify the names of the formulae to ${COMMAND}.
EOF
   exit 1
}

#
# Install brew into "addictions" via git clone
# this has the following advantages:
#    When fetching libraries or binaries they will
#    automatically appear in addictions/bin and addictions/lib / addictionsinclude
#    It's all local (!) to the project. Due to it being a git clone
#    and dependencies being wiped occasionally, its better to have a second
#    directory
#

fetch_brew_if_needed()
{
   if [ -x "${BREW}" ]
   then
      return
   fi

   case "${UNAME}" in
      darwin)
         log_info "Installing OS X brew"
         exekutor git clone https://github.com/Homebrew/brew.git "${ADDICTIONS_DIR}"
      ;;

      linux)
         log_info "Installing Linux brew"
         exekutor git clone https://github.com/Linuxbrew/brew.git "${ADDICTIONS_DIR}"
       ;;

      *)
         fail "Missing brew support for ${UNAME}"
      ;;
   esac

   if [ ! -x "${BREW}" ]
   then
      fail "brew was not successfully installed"
   fi

   return 1
}


#
# brews are now installed using a local brew
# if we are on linx
#
_brew_install_brews()
{
   local brewcmd

   brewcmd="$1" ; shift

   local brews="$@"

   if [ -z "${brews}" ]
   then
      log_fluff "Looking for brews"

      brews="`read_root_setting "brews" | sort | sort -u`"
      if [ -z "${brews}" ]
      then
         brews="`(
            MULLE_BOOTSTRAP_SETTINGS_NO_AUTO=YES
            read_root_setting "brews" | sort | sort -u
            )`"

         if [ -z "${brews}" ]
         then
            log_fluff "No brews found"
            return
         fi
      else
         log_info "Setting read from .bootstrap.auto folder. \
   You might want to use mulle-bootstrap instead of mulle-brew."
      fi
   fi

   if [ "${brewcmd}" = "update" ]
   then
      exekutor "${BREW}" update
      return
   fi

   local flag

   IFS="
"
   for formula in ${brews}
   do
      IFS="${DEFAULT_IFS}"

      if [ "${CHECK_USR_LOCAL_INCLUDE}" = "YES" ] && has_usr_local_include "${formula}"
      then
         log_info "${C_MAGENTA}${C_BOLD}${formula}${C_INFO} is a system library, so not installing it"
         continue
      fi

      local versions

      case "${brewcmd}" in
         install)
            versions="`exekutor ${BREW} ls --versions "${formula}" 2> /dev/null`"

            if [ -z "${versions}" ]
            then
               log_fluff "brew install \"${formula}\""
               exekutor "${BREW}" install "${formula}" || exit 1

               log_info "Force linking it, in case it was keg-only"
               exekutor "${BREW}" link --force "${formula}" || exit 1
            else
               log_info "\"${formula}\" is already installed."
            fi
         ;;

         upgrade)
            log_fluff "brew upgrade \"${formula}\""
            exekutor "${BREW}" upgrade "${formula}"
         ;;
      esac
   done

   IFS="${DEFAULT_IFS}"
}


brew_install_brews()
{
   local unprotect

   fetch_brew_if_needed

   unprotect="NO"
   if [ -d "${ADDICTIONS_DIR}" ]
   then
      log_fluff "Unprotecting \"${ADDICTIONS_DIR}\" for ${command}."
      exekutor chmod -R u+w "${ADDICTIONS_DIR}"
      unprotect="YES"
   fi

   _brew_install_brews "$@"

   if [ "${unprotect}" = "YES" ]
   then
      write_protect_directory "${ADDICTIONS_DIR}"
   fi
}


_brew_common_install()
{
   if [ $# -ne 0 ]
   then
      log_error "Additional parameters not allowed for fetch (" "$@" ")"
      ${USAGE}
   fi

   brew_install_brews "install" "$@"

   if read_yes_no_config_setting "update_gitignore" "YES"
   then
      if [ -d .git ]
      then
         append_dir_to_gitignore_if_needed "${ADDICTIONS_DIR}"
      fi
   fi
}


_brew_common_update()
{
   if [ $# -ne 0 ]
   then
      log_error "Additional parameters not allowed for update (" "$@" ")"
      ${USAGE}
   fi

   brew_install_brews "update"
}


_brew_common_upgrade()
{
   brew_install_brews "upgrade" "$@"
}


_brew_common_main()
{
   [ -z "${MULLE_BOOTSTRAP_LOCAL_ENVIRONMENT_SH}" ] && . mulle-bootstrap-local-environment.sh
   [ -z "${MULLE_BOOTSTRAP_SETTINGS_SH}" ]          && . mulle-bootstrap-settings.sh

   CHECK_USR_LOCAL_INCLUDE="`read_config_setting "check_usr_local_include" "NO"`"

   while [ $# -ne 0 ]
   do
      case "$1" in
         -h|-help|--help)
            ${USAGE}
         ;;

         -nr|--no-recursion)
            DONT_RECURSE="YES"
         ;;

         -cs|--check-usr-local-include)
            CHECK_USR_LOCAL_INCLUDE="YES"
            ;;

         -*)
            log_error "${MULLE_BOOTSTRAP_FAIL_PREFIX}: Unknown ${COMMAND} option $1"
            ${USAGE}
         ;;

         *)
            break
         ;;
      esac

      shift
   done

   [ -z "${MULLE_BOOTSTRAP_SCRIPTS_SH}" ] && . mulle-bootstrap-scripts.sh
   [ -z "${ADDICTIONS_DIR}" ] && internal_fail "missing ADDICTIONS_DIR"

   BREW="${ADDICTIONS_DIR}/bin/brew"

   #
   # should we check for '/usr/local/include/<name>' and don't fetch if
   # present (somewhat dangerous, because we do not check versions)
   #
   case "${COMMAND}" in
      install)
         _brew_common_install "$@"
      ;;

      update)
         _brew_common_update "$@"
      ;;

      upgrade)
         _brew_common_upgrade "$@"
      ;;

      *)
         internal_fail "Command \"${COMMAND}\" is unknown"
   esac
}


brew_upgrade_main()
{
   log_fluff "::: brew upgrade begin :::"

   USAGE="_brew_usage"
   COMMAND="upgrade"
   _brew_common_main "$@"

   log_fluff "::: brew upgrade end :::"
}


brew_update_main()
{
   log_fluff "::: brew update begin :::"

   USAGE="_brew_usage"
   COMMAND="update"
   _brew_common_main "$@"

   log_fluff "::: brew update end :::"
}


brew_install_main()
{
   log_fluff "::: brew install begin :::"

   USAGE="_brew_usage"
   COMMAND="install"
   _brew_common_main "$@"

   log_fluff "::: brew install end :::"
}


brew_initialize()
{
   log_fluff ":brew_initialize:"

   [ -z "${MULLE_BOOTSTRAP_FUNCTIONS_SH}" ] && . mulle-bootstrap-functions.sh
   :
}

brew_initialize
