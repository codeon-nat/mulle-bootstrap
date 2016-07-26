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

. mulle-bootstrap-local-environment.sh
. mulle-bootstrap-gcc.sh
. mulle-bootstrap-scripts.sh



CLEAN_BEFORE_BUILD=`read_config_setting "clean_before_build"`
CONFIGURATIONS="`read_build_root_setting "configurations" "Release"`"
N_CONFIGURATIONS="`echo "${CONFIGURATIONS}" | wc -l | awk '{ print $1 }'`"

# get number of cores, use 50% more for make -j
CORES="`get_core_count`"
CORES="`expr $CORES + $CORES / 2`"

check_and_usage_and_help()
{
   local defk
   local defc
   local defkk

   defc="`printf "$CONFIGURATIONS" | tr '\012' ','`"
   if [ "${CLEAN_BEFORE_BUILD}" = "YES" ]
   then
      defk=""
      defkk="(default)"
   else
      defk="(default)"
      defkk=""
   fi

   cat <<EOF
usage: build [-ck] [repos]*

   -k         :  don't clean before building $defk
   -K         :  always clean before building $defkk
   -c <name>  :  configurations to build ($defc)
   -j         :  number of cores parameter for make (${CORES})

   You can optionally specify the names of the repositories to build.
   Currently available names are:
EOF
   (cd "${CLONES_SUBDIR}" ; ls -1 ) 2> /dev/null
}


while :
do
   if [ "$1" = "-h" -o "$1" = "--help" ]
   then
      check_and_usage_and_help >&2
      exit 1
   fi

   if [ "$1" = "-K" ]
   then
      CLEAN_BEFORE_BUILD="YES"
      [ $# -eq 0 ] || shift
      continue
   fi

   if [ "$1" = "-k" ]
   then
      CLEAN_BEFORE_BUILD=
      [ $# -eq 0 ] || shift
      continue
   fi

   if [ "$1" = "-j" ]
   then
      if [ $# -eq 0 ]
      then
         fail "core count missing"
      fi
      shift

      CORES="$1"
      [ $# -eq 0 ] || shift
      continue
   fi

   #
   # specify configuration to build
   #
   if [ "$1" = "-c"  ]
   then
      if [ $# -eq 0 ]
      then
         fail "configuration name missing"
      fi
      shift

      CONFIGURATIONS="`printf "%s" "$1" | tr ',' '\012'`"
      [ $# -eq 0 ] || shift
      continue
   fi

   break
done


#
# move stuff produced my cmake and configure to places
# where we expect them. Expect  others to build to
# <prefix>/include  and <prefix>/lib or <prefix>/Frameworks
#
dispense_headers()
{
   local name
   local src

   name="$1"
   src="$2"

   local dst
   local headerpath

   log_fluff "Consider copying headers from \"${src}\""

   if [ -d "${src}" ]
   then
      if dir_has_files "${src}"
      then
         headerpath="`read_build_setting "${name}" "dispense_headers_path" "/${HEADER_DIR_NAME}"`"

         dst="${REFERENCE_DEPENDENCY_SUBDIR}${headerpath}"
         mkdir_if_missing "${dst}"

         # this fails with more nested header set ups, need to fix!

         log_fluff "Copying \"${src}\" to \"${dst}\""
         exekutor cp -Ra ${COPYMOVEFLAGS} "${src}"/* "${dst}" || exit 1

         rmdir_safer "${src}"
      else
         log_fluff "But there are none"
      fi
   else
      log_fluff "But it doesn't exist"
   fi
}


dispense_binaries()
{
   local name
   local src
   local findtype
   local depend_subdir
   local subpath

   name="$1"
   src="$2"
   findtype="$3"
   depend_subdir="$4"
   subpath="$5"

   local dst
   local findtype2
   local copyflag

   findtype2="l"
   copyflag="-f"
   if [ "${findtype}" = "-d"  ]
   then
      copyflag="-n"
   fi
   log_fluff "Consider copying binaries from \"${src}\" for type \"${findtype}/${findtype2}\""

   if [ -d "${src}" ]
   then
      if dir_has_files "${src}"
      then
         dst="${REFERENCE_DEPENDENCY_SUBDIR}${depend_subdir}${subpath}"

         log_fluff "Copying \"${src}\" to \"${dst}\""
         mkdir_if_missing "${dst}"
         exekutor find "${src}" -xdev -mindepth 1 -maxdepth 1 \( -type "${findtype}" -o -type "${findtype2}" \) -print0 | \
            exekutor xargs -0 -I % mv ${COPYMOVEFLAGS} "${copyflag}" % "${dst}"
         [ $? -eq 0 ]  || exit 1
      else
         log_fluff "But there are none"
      fi
      rmdir_safer "${src}"
   else
      log_fluff "But it doesn't exist"
   fi
}


collect_and_dispense_product()
{
   local  name
   local  build_subdir
   local  depend_subdir
   local  name

   name="${1}"
   build_subdir="${2}"
   depend_subdir="${3}"
   wasxcode="${4}"

   local  dst
   local  src

   if read_yes_no_config_setting "skip_collect_and_dispense" "NO"
   then
      log_info "Skipped collection and dispensal on request"
      return 0
   fi

   log_fluff "Collecting and dispensing \"${name}\" \"`basename -- "${build_subdir}"`\" products "

   #
   # probably should use install_name_tool to hack all dylib paths that contain .ref
   # (will this work with signing stuff ?)
   #
   if true
   then
      log_fluff "Choosing xcode dispense path"

      # cmake

      src="${BUILD_DEPENDENCY_SUBDIR}/usr/local/include"
      dispense_headers "${name}" "${src}"

      src="${BUILD_DEPENDENCY_SUBDIR}/usr/local/lib"
      dispense_binaries "${name}" "${src}" "f" "${depend_subdir}" "/${LIBRARY_DIR_NAME}"

      # pretty much xcodetool specific

      src="${BUILD_DEPENDENCY_SUBDIR}/usr/include"
      dispense_headers "${name}" "${src}"

      src="${BUILD_DEPENDENCY_SUBDIR}/include"
      dispense_headers "${name}" "${src}"

      src="${BUILD_DEPENDENCY_SUBDIR}${build_subdir}/lib"
      dispense_binaries "${name}" "${src}" "f" "${depend_subdir}" "/${LIBRARY_DIR_NAME}"

      src="${BUILD_DEPENDENCY_SUBDIR}${build_subdir}/Library/Frameworks"
      dispense_binaries "${name}" "${src}" "d" "${depend_subdir}" "/${FRAMEWORK_DIR_NAME}"

      src="${BUILD_DEPENDENCY_SUBDIR}${build_subdir}/Frameworks"
      dispense_binaries "${name}" "${src}" "d" "${depend_subdir}" "/${FRAMEWORK_DIR_NAME}"

      src="${BUILD_DEPENDENCY_SUBDIR}${build_subdir}/Library/Frameworks"
      dispense_binaries "${name}" "${src}" "d" "${depend_subdir}" "/${FRAMEWORK_DIR_NAME}"

      src="${BUILD_DEPENDENCY_SUBDIR}${build_subdir}/Frameworks"
      dispense_binaries "${name}" "${src}" "d" "${depend_subdir}" "/${FRAMEWORK_DIR_NAME}"

      src="${BUILD_DEPENDENCY_SUBDIR}/Library/Frameworks"
      dispense_binaries "${name}" "${src}" "d"  "${depend_subdir}" "/${FRAMEWORK_DIR_NAME}"

      src="${BUILD_DEPENDENCY_SUBDIR}/Frameworks"
      dispense_binaries "${name}" "${src}" "d" "${depend_subdir}" "/${FRAMEWORK_DIR_NAME}"
   fi

   #
   # Delete empty dirs if so
   #
   src="${BUILD_DEPENDENCY_SUBDIR}/usr/local"
   dir_has_files "${src}"
   if [ $? -ne 0 ]
   then
      rmdir_safer "${src}"
   fi

   src="${BUILD_DEPENDENCY_SUBDIR}/usr"
   dir_has_files "${src}"
   if [ $? -ne 0 ]
   then
      rmdir_safer "${src}"
   fi

   #
   # probably should hack all executables with install_name_tool that contain .ref
   #
   # now copy over the rest of the output
   if read_yes_no_build_setting "${name}" "dispense_other_product" "NO"
   then
      local usrlocal

      usrlocal="`read_build_setting "${name}" "dispense_other_path" "/usr/local"`"

      log_fluff "Considering copying ${BUILD_DEPENDENCY_SUBDIR}/*"

      src="${BUILD_DEPENDENCY_SUBDIR}"
      if [ "${wasxcode}" = "YES" ]
      then
         src="${src}${build_subdir}"
      fi

      if dir_has_files "${src}"
      then
         dst="${REFERENCE_DEPENDENCY_SUBDIR}${usrlocal}"

         log_fluff "Copying everything from \"${src}\" to \"${dst}\""
         exekutor find "${src}" -xdev -mindepth 1 -maxdepth 1 -print0 | \
               exekutor xargs -0 -I % mv ${COPYMOVEFLAGS} -f % "${dst}"
         [ $? -eq 0 ]  || fail "moving files from ${src} to ${dst} failed"
      fi

      if [ "$MULLE_BOOTSTRAP_VERBOSE" = "YES"  ]
      then
         if dir_has_files "${BUILD_DEPENDENCY_SUBDIR}"
         then
            log_fluff "Directory \"${dst}\" contained files after collect and dispense"
            log_fluff "--------------------"
            ( cd "${BUILD_DEPENDENCY_SUBDIR}" ; ls -lR >&2 )
            log_fluff "--------------------"
         fi
      fi
   fi

   rmdir_safer "${BUILD_DEPENDENCY_SUBDIR}"

   log_fluff "Done collecting and dispensing product"
   log_fluff
}


enforce_build_sanity()
{
   local builddir

   builddir="$1"

   # these must not exist
   if [ -d "${BUILD_DEPENDENCY_SUBDIR}" ]
   then
      fail "A previous build left \"${BUILD_DEPENDENCY_SUBDIR}\", can't continue"
   fi
}


determine_suffix()
{
   local configuration
   local sdk
   local suffix
   local hackish

   configuration="$1"
   sdk="$2"

   [ ! -z "$configuration" ] || fail "configuration must not be empty"
   [ ! -z "$sdk" ] || fail "sdk must not be empty"

   suffix="${configuration}"
   if [ "${sdk}" != "Default" ]
   then
      hackish=`echo "${sdk}" | sed 's/^\([a-zA-Z]*\).*$/\1/g'`
      suffix="${suffix}-${hackish}"
   fi
   echo "${suffix}"
}


#
# if only one configuration is chosen, make it the default
# if there are multiple configurations, make Release the default
# if Release is not in multiple configurations, then there is no default
#
determine_build_subdir()
{
   echo "/$1"
}


determine_dependencies_subdir()
{
   if [ "${N_CONFIGURATIONS}" -gt 1 ]
   then
      if [ "$1" != "Release" ]
      then
         echo "/$1"
      fi
   fi
}


cmake_sdk_parameter()
{
   local sdk

   sdk="$1"

   local sdkpath

   sdkpath=`gcc_sdk_parameter "${sdk}"`
   if [ "${sdkpath}" != "" ]
   then
      log_fluff "Set cmake -DCMAKE_OSX_SYSROOT to \"${sdkpath}\""
      echo '-DCMAKE_OSX_SYSROOT='"${sdkpath}"
   fi
}


create_dummy_dirs_against_warnings()
{
   local mapped
   local suffix

   mapped="$1"
   suffix="$2"

   local mappedsubdir
   local suffixsubdir

   mappedsubdir="`determine_dependencies_subdir "${mapped}"`"
   suffixsubdir="`determine_dependencies_subdir "${suffix}"`"

   local owd

   owd="${PWD}"

   # to avoid warnings, make sure directories are all there
   mkdir_if_missing "${owd}/${REFERENCE_DEPENDENCY_SUBDIR}/${HEADER_DIR_NAME}"

   mkdir_if_missing "${owd}/${REFERENCE_DEPENDENCY_SUBDIR}${mappedsubdir}/${LIBRARY_DIR_NAME}"
   mkdir_if_missing "${owd}/${REFERENCE_DEPENDENCY_SUBDIR}${mappedsubdir}/${FRAMEWORK_DIR_NAME}"

   mkdir_if_missing "${owd}/${REFERENCE_DEPENDENCY_SUBDIR}${suffixsubdir}/${LIBRARY_DIR_NAME}"
   mkdir_if_missing "${owd}/${REFERENCE_DEPENDENCY_SUBDIR}${suffixsubdir}/${FRAMEWORK_DIR_NAME}"
}


build_fail()
{
   if [ -f "${1}" ]
   then
      printf "${C_RED}"
      egrep -B1 -A5 -w "[Ee]rror" "${1}" >&2
      printf "${C_RESET}"
   fi

   if [ -z "$MULLE_BOOTSTRAP_TRACE" ]
   then
      log_info "Check the build log: ${C_RESET_BOLD}${1}${C_INFO}"
   fi
   fail "$2 failed"
}


build_log_name()
{
   local tool
   local name

   tool="$1"
   [ $# -eq 0 ] || shift
   name="$1"
   [ $# -eq 0 ] || shift

   local logfile
   logfile="${BUILDLOG_SUBDIR}/${name}"

   while [ $# -gt 0 ]
   do
      if [ ! -z "${1}" ]
      then
         logfile="${logfile}-${1}"
      fi
      [ $# -eq 0 ] || shift
   done

   echo "${logfile}.${tool}.log"
}


#
# remove old builddir, create a new one
# depending on configuration cmake with flags
# build stuff into dependencies
#
build_cmake()
{
   local configuration
   local srcdir
   local builddir
   local name
   local sdk

   configuration="$1"
   srcdir="$2"
   builddir="$3"
   name="$4"
   sdk="$5"

   enforce_build_sanity "${builddir}"

   log_info "Let ${C_RESET_BOLD}cmake${C_INFO} do a \
${C_MAGENTA}${C_BOLD}${configuration}${C_INFO} build of \
${C_MAGENTA}${C_BOLD}${name}${C_INFO} for SDK \
${C_MAGENTA}${C_BOLD}${sdk}${C_INFO} in \"${builddir}\" ..."

   local sdkparameter
   local suffix
   local mapped
   local fallback
   local localcmakeflags


   fallback="`echo "${CONFIGURATIONS}" | tail -1`"
   fallback="`read_build_setting "${name}" "fallback-configuration" "${fallback}"`"
   mapped="`read_build_setting "${name}" "cmake-${configuration}.map" "${configuration}"`"
   localcmakeflags="`read_build_root_setting "cmakeflags"`"
   suffix="`determine_suffix "${configuration}" "${sdk}"`"
   sdkparameter="`cmake_sdk_parameter "${sdk}"`"

   create_dummy_dirs_against_warnings "${mapped}" "${suffix}"

   local mappedsubdir
   local fallbacksubdir
   local suffixsubdir

   mappedsubdir="`determine_dependencies_subdir "${mapped}"`"
   suffixsubdir="`determine_dependencies_subdir "${suffix}"`"
   fallbacksubdir="`determine_dependencies_subdir "${fallback}"`"

   local other_cflags
   local other_cppflags
   local other_ldflags

   other_cflags="`gcc_cflags_value "${name}"`"
   other_cppflags="`gcc_cppflags_value "${name}"`"
   other_ldflags="`gcc_ldflags_value "${name}"`"

   local logfile1
   local logfile2

   mkdir_if_missing "${BUILDLOG_SUBDIR}"

   logfile1="`build_log_name "cmake" "${name}" "${configuration}" "${sdk}"`"
   logfile2="`build_log_name "make" "${name}" "${configuration}" "${sdk}"`"

   log_fluff "Build logs will be in \"${logfile1}\" and \"${logfile2}\""

   local   local_make_flags

   local_make_flags="${MAKE_FLAGS} -j ${CORES}"

   owd="${PWD}"

#   cmake_keep_builddir="`read_build_setting "${name}" "cmake_keep_builddir" "YES"`"
#   if [ "${cmake_keep_builddir}" != "YES" ]
#   then
#      rmdir_safer "${builddir}"
#   fi

   mkdir_if_missing "${builddir}"
   exekutor cd "${builddir}" || fail "failed to enter ${builddir}"

      #
      # cmake doesn't seem to "get" CMAKE_CXX_FLAGS or -INCLUDE
      #
      set -f

      logfile1="${owd}/${logfile1}"
      logfile2="${owd}/${logfile2}"

      if [ "$MULLE_BOOTSTRAP_VERBOSE_BUILD" = "YES" ]
      then
         logfile1="`tty`"
         logfile2="$logfile1"
      fi
      if [ "$MULLE_BOOTSTRAP_DRY_RUN" = "YES" ]
      then
         logfile1="/dev/null"
         logfile2="/dev/null"
      fi

      local frameworklines
      local librarylines

      frameworklines=
      librarylines=

      if [ ! -z "${suffixsubdir}" ]
      then
         frameworklines="-F${owd}/${REFERENCE_DEPENDENCY_SUBDIR}${suffixsubdir}/${FRAMEWORK_DIR_NAME}"
         librarylines="-L${owd}/${REFERENCE_DEPENDENCY_SUBDIR}${suffixsubdir}/${LIBRARY_DIR_NAME}"
      fi

      if [ ! -z "${mappedsubdir}" -a "${mappedsubdir}" != "${suffixsubdir}" ]
      then
         frameworklines="${frameworklines} -F${owd}/${REFERENCE_DEPENDENCY_SUBDIR}${mappedsubdir}/${FRAMEWORK_DIR_NAME}"
         librarylines="${librarylines} -L${owd}/${REFERENCE_DEPENDENCY_SUBDIR}${mappedsubdir}/${LIBRARY_DIR_NAME}"
      fi

      if [ ! -z "${fallbacksubdir}" -a "${fallbacksubdir}" != "${suffixsubdir}" -a "${fallbacksubdir}" != "${mappedsubdir}" ]
      then
         frameworklines="${frameworklines} -F${owd}/${REFERENCE_DEPENDENCY_SUBDIR}${fallbacksubdir}/${FRAMEWORK_DIR_NAME}"
         librarylines="${librarylines} -L${owd}/${REFERENCE_DEPENDENCY_SUBDIR}${fallbacksubdir}/${LIBRARY_DIR_NAME}"
      fi

      local relative_srcdir

      relative_srcdir="`relative_path_between "${owd}/${srcdir}" "${PWD}"`"

      logging_exekutor cmake "-DCMAKE_BUILD_TYPE=${mapped}" \
"${sdkparameter}" \
"-DDEPENDENCIES_DIR=${owd}/${REFERENCE_DEPENDENCY_SUBDIR}" \
"-DCMAKE_INSTALL_PREFIX:PATH=${owd}/${BUILD_DEPENDENCY_SUBDIR}"  \
"-DCMAKE_C_FLAGS=\
-I${owd}/${REFERENCE_DEPENDENCY_SUBDIR}/${HEADER_DIR_NAME} \
-I/usr/local/include \
${frameworklines} \
-F${owd}/${REFERENCE_DEPENDENCY_SUBDIR}/${FRAMEWORK_DIR_NAME} \
${other_cflags}" \
"-DCMAKE_CXX_FLAGS=\
-I${owd}/${REFERENCE_DEPENDENCY_SUBDIR}/${HEADER_DIR_NAME} \
-I/usr/local/include \
${frameworklines} \
-F${owd}/${REFERENCE_DEPENDENCY_SUBDIR}/${FRAMEWORK_DIR_NAME} \
${other_cppflags}" \
"-DCMAKE_EXE_LINKER_FLAGS=\
${librarylines} \
-L${owd}/${REFERENCE_DEPENDENCY_SUBDIR}/${LIBRARY_DIR_NAME} \
-L/usr/local/lib \
${other_ldflags}" \
"-DCMAKE_SHARED_LINKER_FLAGS=\
${librarylines} \
-L${owd}/${REFERENCE_DEPENDENCY_SUBDIR}/${LIBRARY_DIR_NAME} \
-L/usr/local/lib \
${other_ldflags}" \
"-DCMAKE_MODULE_PATH=${CMAKE_MODULE_PATH};\${CMAKE_MODULE_PATH}" \
${CMAKE_FLAGS} \
${localcmakeflags} \
"${relative_srcdir}" > "${logfile1}" || build_fail "${logfile1}" "cmake"

      if [ MULLE_BOOTSTRAP_VERBOSE_BUILD = "YES" ]
      then
         local_make_flags="${local_make_flags} VERBOSE=1"
      fi

      logging_exekutor make ${local_make_flags} install > "${logfile2}" || build_fail "${logfile2}" "make"

      set +f

   exekutor cd "${owd}"

   local depend_subdir

   depend_subdir="`determine_dependencies_subdir "${suffix}"`"
   collect_and_dispense_product "${name}" "${suffixsubdir}" "${depend_subdir}" || internal_fail "collect failed silently"
}


#
# remove old builddir, create a new one
# depending on configuration cmake with flags
# build stuff into dependencies
#
#
build_configure()
{
   local configuration
   local srcdir
   local builddir
   local name
   local sdk

   configuration="$1"
   srcdir="$2"
   builddir="$3"
   name="$4"
   sdk="$5"

   enforce_build_sanity "${builddir}"

   log_info "Let ${C_RESET_BOLD}configure${C_INFO} do a \
${C_MAGENTA}${C_BOLD}${configuration}${C_INFO} build of \
${C_MAGENTA}${C_BOLD}${name}${C_INFO} for SDK \
${C_MAGENTA}${C_BOLD}${sdk}${C_INFO} in \"${builddir}\" ..."

   local sdkpath
   local fallback
   local mapped
   local suffix
   local fallback
   local configureflags

   fallback="`echo "${CONFIGURATIONS}" | tail -1`"
   fallback="`read_build_setting "${name}" "fallback-configuration" "${fallback}"`"

   configureflags="`read_build_setting "${name}" "configure_flags"`"

   mapped="`read_build_setting "${name}" "configure-${configuration}.map" "${configuration}"`"
   suffix="`determine_suffix "${configuration}" "${sdk}"`"
   sdkpath="`gcc_sdk_parameter "${sdk}"`"
   sdkpath="`echo "${sdkpath}" | sed -e 's/ /\\ /g'`"

   create_dummy_dirs_against_warnings "${mapped}" "${suffix}"

   local mappedsubdir
   local fallbacksubdir
   local suffixsubdir

   mappedsubdir="`determine_dependencies_subdir "${mapped}"`"
   suffixsubdir="`determine_dependencies_subdir "${suffix}"`"
   fallbacksubdir="`determine_dependencies_subdir "${fallback}"`"

   local other_cflags
   local other_cppflags
   local other_ldflags

   other_cflags="`gcc_cflags_value "${name}"`"
   other_cppflags="`gcc_cppflags_value "${name}"`"
   other_ldflags="`gcc_ldflags_value "${name}"`"


   local logfile1
   local logfile2

   mkdir_if_missing "${BUILDLOG_SUBDIR}"

   logfile1="`build_log_name "configure" "${name}" "${configuration}" "${sdk}"`"
   logfile2="`build_log_name "make" "${name}" "${configuration}" "${sdk}"`"

   log_fluff "Build logs will be in \"${logfile1}\" and \"${logfile2}\""

   owd="${PWD}"
   mkdir_if_missing "${builddir}"
   exekutor cd "${builddir}" || fail "failed to enter ${builddir}"

       set -f

      logfile1="${owd}/${logfile1}"
      logfile2="${owd}/${logfile2}"

      if [ "$MULLE_BOOTSTRAP_VERBOSE_BUILD" = "YES" ]
      then
         logfile1="`tty`"
         logfile2="$logfile1"
      fi
      if [ "$MULLE_BOOTSTRAP_DRY_RUN" = "YES" ]
      then
         logfile1="/dev/null"
         logfile2="/dev/null"
      fi

      local frameworklines
      local librarylines

      frameworklines=
      librarylines=

      if [ ! -z "${suffixsubdir}" ]
      then
         frameworklines="-F${owd}/${REFERENCE_DEPENDENCY_SUBDIR}${suffixsubdir}/${FRAMEWORK_DIR_NAME}"
         librarylines="-L${owd}/${REFERENCE_DEPENDENCY_SUBDIR}${suffixsubdir}/${LIBRARY_DIR_NAME}"
      fi

      if [ ! -z "${mappedsubdir}" -a "${mappedsubdir}" != "${suffixsubdir}" ]
      then
         frameworklines="${frameworklines} -F${owd}/${REFERENCE_DEPENDENCY_SUBDIR}${mappedsubdir}/${FRAMEWORK_DIR_NAME}"
         librarylines="${librarylines} -L${owd}/${REFERENCE_DEPENDENCY_SUBDIR}${mappedsubdir}/${LIBRARY_DIR_NAME}"
      fi

      if [ ! -z "${fallbacksubdir}" -a "${fallbacksubdir}" != "${suffixsubdir}" -a "${fallbacksubdir}" != "${mappedsubdir}" ]
      then
         frameworklines="${frameworklines} -F${owd}/${REFERENCE_DEPENDENCY_SUBDIR}${fallbacksubdir}/${FRAMEWORK_DIR_NAME}"
         librarylines="${librarylines} -L${owd}/${REFERENCE_DEPENDENCY_SUBDIR}${fallbacksubdir}/${LIBRARY_DIR_NAME}"
      fi

      # use absolute paths for configure, safer (and easier to read IMO)
       DEPENDENCIES_DIR="'${owd}/${REFERENCE_DEPENDENCY_SUBDIR}'" \
       CFLAGS="\
-I${owd}/${REFERENCE_DEPENDENCY_SUBDIR}/${HEADER_DIR_NAME} \
-I/usr/local/include \
${frameworklines}
-F${owd}/${REFERENCE_DEPENDENCY_SUBDIR}/${FRAMEWORK_DIR_NAME} \
${other_cflags} \
-isysroot ${sdkpath}" \
      CPPFLAGS="\
-I${owd}/${REFERENCE_DEPENDENCY_SUBDIR}/${HEADER_DIR_NAME} \
-I/usr/local/include \
${frameworklines}
-F${owd}/${REFERENCE_DEPENDENCY_SUBDIR}/${FRAMEWORK_DIR_NAME} \
${other_cppflags} \
-isysroot ${sdkpath}" \
      LDFLAGS="\
${frameworklines}
-F${owd}/${REFERENCE_DEPENDENCY_SUBDIR}/${FRAMEWORK_DIR_NAME} \
${librarylines}
-L${owd}/${REFERENCE_DEPENDENCY_SUBDIR}/${LIBRARY_DIR_NAME} \
-L/usr/local/lib \
${other_ldflags} \
-isysroot ${sdkpath}" \
       logging_exekutor "${owd}/${srcdir}/configure" ${configureflags} \
          --prefix "${owd}/${BUILD_DEPENDENCY_SUBDIR}" >> "${logfile1}" \
      || build_fail "${logfile1}" "configure"

      logging_exekutor make install > "${logfile2}" \
      || build_fail "${logfile2}" "make"

      set +f

   exekutor cd "${owd}"

   local depend_subdir

   depend_subdir="`determine_dependencies_subdir "${suffix}"`"
   collect_and_dispense_product "${name}" "${suffixsubdir}" "${depend_subdir}" || exit 1
}


_xcode_get_setting()
{
   eval_exekutor "xcodebuild -showBuildSettings $*" || fail "failed to read xcode settings"
}


xcode_get_setting()
{
   local key

   key="$1"
   shift

   _xcode_get_setting "$@" | egrep "^[ ]*${key}" | sed 's/^[^=]*=[ ]*\(.*\)/\1/'
}


#
# Code I didn't want to throw away really
# In general just use "public_headers" or
# "private_headers" and set them to a /usr/local/include/whatever
#
create_mangled_header_path()
{
   local name
   local key
   local default

   key="$1"
   name="$2"
   default="$3"

   local headers
   local prefix

   headers=`xcode_get_setting "${key}" $*` || exit 1
   log_fluff "${key} read as \"${headers}\""

   case "${headers}" in
      /*)
      ;;

      ./*|../*)
         log_warning "relative path \"${headers}\" as header path ???"
      ;;

      "")
         headers="${default}"
      ;;

      *)
         headers="/${headers}"
      ;;
   esac

   prefix=""
   read_yes_no_build_setting "${name}" "xcode_mangle_include_prefix"
   if [ $? -ne 0 ]
   then
      headers="`remove_absolute_path_prefix_up_to "${headers}" "include"`"
      prefix="${HEADER_DIR_NAME}"
   fi

   if read_yes_no_build_setting "${name}" "xcode_mangle_header_dash"
   then
      headers="`echo "${headers}" | tr '-' '_'`"
   fi

   echo "${headers}"
}


fixup_header_path()
{
   local key
   local setting_key
   local default
   local name

   key="$1"
   shift
   setting_key="$1"
   shift
   name="$1"
   shift
   default="$1"
   shift

   headers="`read_repo_setting "${name}" "${setting_key}"`"
   if [ "$headers" = "" ]
   then
      read_yes_no_build_setting "${name}" "xcode_mangle_header_paths"
      if [ $? -ne 0 ]
      then
         return 1
      fi

      headers="`create_mangled_header_path "${key}" "${name}" "${default}"`"
   fi

   log_fluff "${key} set to \"${headers}\""

   echo "${headers}"
}


build_xcodebuild()
{
   local configuration
   local srcdir
   local builddir
   local name
   local sdk
   local project
   local schemename
   local targetname

   configuration="$1"
   srcdir="$2"
   builddir="$3"
   name="$4"
   sdk="$5"
   project="$6"
   schemename="$7"
   targetname="$8"

   [ ! -z "${configuration}" ] || internal_fail "configuration is empty"
   [ ! -z "${srcdir}" ]        || internal_fail "srcdir is empty"
   [ ! -z "${builddir}" ]      || internal_fail "builddir is empty"
   [ ! -z "${name}" ]          || internal_fail "name is empty"
   [ ! -z "${sdk}" ]           || internal_fail "sdk is empty"
   [ ! -z "${project}" ]       || internal_fail "project is empty"

   enforce_build_sanity "${builddir}"

   local info

   info=""
   if [ ! -z "${targetname}" ]
   then
      info=" Target ${C_MAGENTA}${C_BOLD}${targetname}${C_INFO}"
   fi

   if [ ! -z "${schemename}" ]
   then
      info=" Scheme ${C_MAGENTA}${C_BOLD}${schemename}${C_INFO}"
   fi

   log_info "Let ${C_RESET_BOLD}xcodebuild${C_INFO} do a \
${C_MAGENTA}${C_BOLD}${configuration}${C_INFO} build of \
${C_MAGENTA}${C_BOLD}${name}${C_INFO} for SDK \
${C_MAGENTA}${C_BOLD}${sdk}${C_INFO}${info} in \
\"${builddir}\" ..."

   local projectname

    # always pass project directly
   projectname=`read_repo_setting "${name}" "project" "${project}"`

   local mapped
   local fallback

   fallback="`echo "${CONFIGURATIONS}" | tail -1`"
   fallback="`read_build_setting "${name}" "fallback-configuration" "${fallback}"`"

   mapped=`read_build_setting "${name}" "${configuration}.map" "${configuration}"`
   [ -z "${mapped}" ] && internal_fail "mapped configuration is empty"

   local hackish
   local targetname
   local suffix

   suffix="${configuration}"
   if [ "${sdk}" != "Default" ]
   then
      hackish="`echo "${sdk}" | sed 's/^\([a-zA-Z]*\).*$/\1/g'`"
      suffix="${suffix}-${hackish}"
   else
      sdk=
   fi

   create_dummy_dirs_against_warnings "${mapped}" "${suffix}"

   local mappedsubdir
   local fallbacksubdir
   local suffixsubdir

   mappedsubdir="`determine_dependencies_subdir "${mapped}"`"
   suffixsubdir="`determine_dependencies_subdir "${suffix}"`"
   fallbacksubdir="`determine_dependencies_subdir "${fallback}"`"

   local xcode_proper_skip_install
   local skip_install

   skip_install=
   xcode_proper_skip_install=`read_build_setting "${name}" "xcode_proper_skip_install" "NO"`
   if [ "$xcode_proper_skip_install" != "YES" ]
   then
      skip_install="SKIP_INSTALL=NO"
   fi

   local xcodebuild
   local binary

   xcodebuild=`read_config_setting "xcodebuild" "xcodebuild"`
   binary=`which "${xcodebuild}"`
   if [ "${binary}"  = "" ]
   then
      echo "${xcodebuild} is an unknown build tool" >& 2
      exit 1
   fi


   #
   # xctool needs schemes, these are often autocreated, which xctool cant do
   # xcodebuild can just use a target
   # xctool is by and large useless fluff IMO
   #
   if [ "$xcodebuild" = "xctool"  -a "${schemename}" = ""  ]
   then
      if [ "$targetname" != "" ]
      then
         schemename="${targetname}"
         targetname=
      else
         echo "Please specify a scheme to compile in ${BOOTSTRAP_SUBDIR}/${name}/SCHEME for xctool" >& 2
         echo "and be sure that this scheme exists and is shared." >& 2
         echo "Or just delete ${HOME}/.mulle-bootstrap/xcodebuild and use xcodebuild (preferred)" >& 2
         exit 1
      fi
   fi

   local key
   local aux
   local value
   local keys

   aux=
   keys=`all_build_flag_keys "${name}"`
   for key in ${keys}
   do
      value=`read_build_setting "${name}" "${key}"`
      aux="${aux} ${key}=${value}"
   done

   # now don't load any settings anymoe
   local owd
   local command

   if [ "$MULLE_BOOTSTRAP_DRY" != "" ]
   then
      command=-showBuildSettings
   else
      command=install
   fi

      #
      # headers are complicated, the preference is to get it uniform into
      # dependencies/include/libraryname/..
      #

   local public_headers
   local private_headers
   local default

   default="/include/${name}"
   public_headers="`fixup_header_path "PUBLIC_HEADERS_FOLDER_PATH" "xcode_public_headers" "${name}" "${default}" ${arguments}`"
   default="/include/${name}/private"
   private_headers="`fixup_header_path "PRIVATE_HEADERS_FOLDER_PATH" "xcode_private_headers" "${name}" "${default}" ${arguments}`"


   local logfile

   mkdir_if_missing "${BUILDLOG_SUBDIR}"

   logfile="`build_log_name "xcodebuild" "${name}" "${configuration}" "${targetname}" "${schemename}" "${sdk}"`"
   log_fluff "Build log will be in: ${C_RESET_BOLD}${logfile}${C_INFO}"

   set -f

   arguments=""
   if [ ! -z "${projectname}" ]
   then
      arguments="${arguments} -project \"${projectname}\""
   fi
   if [ ! -z "${sdk}" ]
   then
      arguments="${arguments} -sdk \"${sdk}\""
   fi
   if [ ! -z "${schemename}" ]
   then
      arguments="${arguments} -scheme \"${schemename}\""
   fi
   if [ ! -z "${targetname}" ]
   then
      arguments="${arguments} -target \"${targetname}\""
   fi
   if [ ! -z "${mapped}" ]
   then
      arguments="${arguments} -configuration \"${mapped}\""
   fi

# an empty xcconfig is nice, because it acts as a reset for
   local xcconfig

   xcconfig=`read_repo_setting "${name}" "xcconfig"`
   if [ ! -z "${xcconfig}" ]
   then
      arguments="${arguments} -xcconfig \"${xcconfig}\""
   fi

   local other_cflags
   local other_cppflags
   local other_ldflags

   other_cflags="`gcc_cflags_value "${name}"`"
   other_cppflags="`gcc_cppflags_value "${name}"`"
   other_ldflags="`gcc_ldflags_value "${name}"`"

   if [ ! -z "${other_cflags}" ]
   then
      other_cflags="OTHER_CFLAGS=${other_cflags}"
   fi
   if [ ! -z "${other_cppflags}" ]
   then
      other_cppflags="OTHER_CPPFLAGS=${other_cppflags}"
   fi
   if [ ! -z "${other_ldflags}" ]
   then
      other_ldflags="OTHER_LDFLAGS=${other_ldflags}"
   fi


   owd=`pwd`
   exekutor cd "${srcdir}" || exit 1


      logfile="${owd}/${logfile}"

      if [ "${MULLE_BOOTSTRAP_VERBOSE_BUILD}" = "YES" ]
      then
         logfile="`tty`"
      fi
      if [ "$MULLE_BOOTSTRAP_DRY_RUN" = "YES" ]
      then
         logfile="/dev/null"
      fi

      # manually point xcode to our headers and libs
      # this is like manually doing xcode-setup
      local dependencies_framework_search_path
      local dependencies_header_search_path
      local dependencies_lib_search_path
      local inherited
      local path
      local escaped

      #
      # TODO: need to figure out the correct mapping here
      #
      inherited="`xcode_get_setting HEADER_SEARCH_PATHS ${arguments}`" || exit 1
      path=`combined_escaped_search_path \
"${owd}/${REFERENCE_DEPENDENCY_SUBDIR}/${HEADER_DIR_NAME}" \
"/usr/local/include"`
      if [ -z "${inherited}" ]
      then
         dependencies_header_search_path="${path}"
      else
         dependencies_header_search_path="${path} ${inherited}"
      fi

      inherited="`xcode_get_setting LIBRARY_SEARCH_PATHS ${arguments}`" || exit 1
      path=`combined_escaped_search_path \
"${owd}/${REFERENCE_DEPENDENCY_SUBDIR}${mappedsubdir}/${LIBRARY_DIR_NAME}" \
"${owd}/${REFERENCE_DEPENDENCY_SUBDIR}${fallbacksubdir}/${LIBRARY_DIR_NAME}" \
"${owd}/${REFERENCE_DEPENDENCY_SUBDIR}/${LIBRARY_DIR_NAME}" \
"/usr/local/lib"`
      if [ ! -z "$sdk" ]
      then
         escaped="`escaped_spaces "${owd}/${REFERENCE_DEPENDENCY_SUBDIR}${mappedsubdir}/${LIBRARY_DIR_NAME}"'-$(EFFECTIVE_PLATFORM_NAME)'`"
         path="${escaped} ${path}" # prepend
      fi
      if [ -z "${inherited}" ]
      then
         dependencies_lib_search_path="${path}"
      else
         dependencies_lib_search_path="${path} ${inherited}"
      fi

      inherited="`xcode_get_setting FRAMEWORK_SEARCH_PATHS ${arguments}`" || exit 1
      path=`combined_escaped_search_path \
"${owd}/${REFERENCE_DEPENDENCY_SUBDIR}${mappedsubdir}/${FRAMEWORK_DIR_NAME}" \
"${owd}/${REFERENCE_DEPENDENCY_SUBDIR}${fallbacksubdir}/${FRAMEWORK_DIR_NAME}" \
"${owd}/${REFERENCE_DEPENDENCY_SUBDIR}/${FRAMEWORK_DIR_NAME}"`
      if [ ! -z "$sdk" ]
      then
         escaped="`escaped_spaces "${owd}/${REFERENCE_DEPENDENCY_SUBDIR}${mappedsubdir}/${FRAMEWORK_DIR_NAME}"'-$(EFFECTIVE_PLATFORM_NAME)'`"
         path="${escaped} ${path}" # prepend
      fi
      if [ -z "${inherited}" ]
      then
         dependencies_framework_search_path="${path}"
      else
         dependencies_framework_search_path="${path} ${inherited}"
      fi

      if [ ! -z "${public_headers}" ]
      then
         arguments="${arguments} PUBLIC_HEADERS_FOLDER_PATH='${public_headers}'"
      fi
      if [ ! -z "${private_headers}" ]
      then
         arguments="${arguments} PRIVATE_HEADERS_FOLDER_PATH='${private_headers}'"
      fi

      # if it doesn't install, probably SKIP_INSTALL is set
      cmdline="\"${xcodebuild}\" \"${command}\" ${arguments} \
ARCHS='${ARCHS:-\${ARCHS_STANDARD_32_64_BIT\}}' \
DSTROOT='${owd}/${BUILD_DEPENDENCY_SUBDIR}' \
SYMROOT='${owd}/${builddir}/' \
OBJROOT='${owd}/${builddir}/obj' \
DEPENDENCIES_DIR='${owd}/${REFERENCE_DEPENDENCY_SUBDIR}' \
ONLY_ACTIVE_ARCH=${ONLY_ACTIVE_ARCH:-NO} \
${skip_install} \
${other_cflags} \
${other_cppflags} \
${other_ldflags} \
HEADER_SEARCH_PATHS='${dependencies_header_search_path}' \
LIBRARY_SEARCH_PATHS='${dependencies_lib_search_path}' \
FRAMEWORK_SEARCH_PATHS='${dependencies_framework_search_path}'"

      logging_eval_exekutor "${cmdline}" > "${logfile}" \
      || build_fail "${logfile}" "xcodebuild"

      set +f

   exekutor cd "${owd}"

   local depend_subdir

   depend_subdir="`determine_dependencies_subdir "${suffix}"`"
   collect_and_dispense_product "${name}" "${suffixsubdir}" "${depend_subdir}" "YES" || exit 1
}


build_xcodebuild_schemes_or_target()
{
   local builddir
   local name
   local project

   builddir="$3"
   name="$4"
   project="$6"

   local scheme
   local schemes

   schemes=`read_repo_setting "${name}" "schemes"`

   local old

   old="${IFS:-" "}"
   IFS="
"
   for scheme in $schemes
   do
      IFS="$old"
      log_fluff "Building scheme \"${scheme}\" of \"${project}\" ..."
      build_xcodebuild "$@" "${scheme}" ""
   done
   IFS="${old}"

   local target
   local targets

   targets=`read_repo_setting "${name}" "targets"`

   old="$IFS"
   IFS="
"
   for target in $targets
   do
      IFS="${old}"
      log_fluff "Building target \"${target}\" of \"${project}\" ..."
      build_xcodebuild "$@" "" "${target}"
   done
   IFS="${old}"

   if [ "${targets}" = "" -a "${schemes}" = "" ]
   then
      log_fluff "Building project \"${project}\"..."
      build_xcodebuild "$@"
   fi
}


run_build_script()
{
   local script

   script="$1"
   shift

   [ ! -z "$script" ] || internal_fail "script is empty"

   if [ -x "${script}" ]
   then
      log_fluff "Executing script \"${script}\" $1"
      exekutor "${script}" "$@"
   else
      if [ ! -e "${script}" ]
      then
         fail "script \"${script}\" not found ($PWD)"
      else
         fail "script \"${script}\" not executable"
      fi
   fi
}


run_log_build_script()
{
   echo "$@"
   run_build_script "$@"
}


build_script()
{
   local script

   script="$1"
   shift

   local configuration
   local srcdir
   local builddir
   local name
   local sdk
   local project
   local schemename
   local targetname

   configuration="$1"
   srcdir="$2"
   builddir="$3"
   name="$4"
   sdk="$5"

   local logfile

   mkdir_if_missing "${BUILDLOG_SUBDIR}"

   logfile="${BUILDLOG_SUBDIR}/${name}-${configuration}-${sdk}.script.log"
   log_fluff "Build log will be in: ${C_RESET_BOLD}${logfile}${C_INFO}"

   mkdir_if_missing "${builddir}"

   local owd

   owd=`pwd`
   exekutor cd "${srcdir}" || exit 1

      logfile="${owd}/${logfile}"

      if [ "$MULLE_BOOTSTRAP_VERBOSE_BUILD" = "YES" ]
      then
         logfile="`tty`"
      fi
      if [ "$MULLE_BOOTSTRAP_DRY_RUN" = "YES" ]
      then
         logfile="/dev/null"
      fi

      log_info "Let ${C_RESET_BOLD}script${C_INFO} do a \
${C_MAGENTA}${C_BOLD}${configuration}${C_INFO} build of \
${C_MAGENTA}${C_BOLD}${name}${C_INFO} for SDK \
${C_MAGENTA}${C_BOLD}${sdk}${C_INFO}${info} in \
\"${builddir}\" ..."

      run_log_build_script "${owd}/${script}" \
         "${configuration}" \
         "${owd}/${srcdir}" \
         "${owd}/${builddir}" \
         "${owd}/${BUILD_DEPENDENCY_SUBDIR}" \
         "${name}" \
         "${sdk}" > "${logfile}" \
      || build_fail "${logfile}" "build.sh"

   exekutor cd "${owd}"

   local suffix
   local depend_subdir
   local suffixsubdir

   suffix="`determine_suffix "${configuration}" "${sdk}"`"
   suffixsubdir="`determine_build_subdir "${suffix}"`"
   depend_subdir="`determine_dependencies_subdir "${suffix}"`"
   collect_and_dispense_product "${name}" "${suffixsubdir}" "${depend_subdir}" || internal_fail "collect failed silently"
}



build()
{
   local name
   local srcdir

   name="$1"
   srcdir="$2"

   [ "${name}" != "${CLONES_SUBDIR}" ] || internal_fail "missing repo argument (${srcdir})"

   local preferences

   #
   # repo may override how it wants to be build
   #
   preferences="`read_build_setting "${name}" "build_preferences"`"
   if [ -z "${preferences}" ]
   then
      if [ "`uname`" = 'Darwin' ]
      then
         preferences="`read_config_setting "build_preferences" "script
cmake
configure
xcodebuild"`"
      else
         preferences="`read_config_setting "build_preferences" "script
cmake
configure"`"
      fi
   fi

   local xcodebuild
   local cmake

   xcodebuild=`which "xcodebuild"`
   cmake=`which "cmake"`

   local sdk
   local sdks

   # need uniform SDK for our builds
   sdks=`read_build_root_setting "sdks" "Default"`
   [ ! -z "${sdks}" ] || fail "setting \"sdks\" must at least contain \"Default\" to build anything"

   local builddir
   local hasbuilt
   local configuration
   local preference
   local configurations

   # settings can override the commandline default
   configurations="`read_build_setting "${name}" "configurations" "${CONFIGURATIONS}"`"

   for sdk in ${sdks}
   do
      # remap macosx to Default, as EFFECTIVE_PLATFORM_NAME will not be appeneded by Xcode
      if [ "$sdk" = "macosx" ]
      then
         sdk="Default"
      fi

      for configuration in ${configurations}
      do
         if [ "/${configuration}" = "/${LIBRARY_DIR_NAME}" -o "/${configuration}" = "${HEADER_DIR_NAME}" -o "/${configuration}" = "${FRAMEWORK_DIR_NAME}" ]
         then
            fail "You are just asking for trouble naming your configuration \"${configuration}\"."
         fi

         if [ "${configuration}" = "lib" -o "${configuration}" = "include" -o "${configuration}" = "Frameworks" ]
         then
            fail "You are just asking for major trouble naming your configuration \"${configuration}\"."
         fi

         builddir="${CLONESBUILD_SUBDIR}/${configuration}/${name}"

         if [ -d "${builddir}" -a "${CLEAN_BEFORE_BUILD}" = "YES" ]
         then
            log_fluff "Cleaning build directory \"${builddir}\""
            rmdir_safer "${builddir}"
         fi

         hasbuilt=no
         for preference in ${preferences}
         do
            if [ "${preference}" = "script" ]
            then
               local script

               script="`find_build_setting_file "${name}" "bin/build.sh"`"
               if [ -x "${script}" ]
               then
                  build_script "${script}" "${configuration}" "${srcdir}" "${builddir}" "${name}" "${sdk}" || exit 1
                  hasbuilt=yes
                  break
               else
                  [ ! -e "${script}" ] || fail "script ${script} is not executable"
               fi
            fi

            if [ "${preference}" = "xcodebuild" -a -x "${xcodebuild}" ]
            then
               project=`(cd "${srcdir}" ; find_xcodeproj "${name}")`

               if [ "$project" != "" ]
               then
                  build_xcodebuild_schemes_or_target "${configuration}" "${srcdir}" "${builddir}" "${name}" "${sdk}" "${project}"  || exit 1
                  hasbuilt=yes
                  break
               fi
            fi

            if [ "${preference}" = "configure"  ]
            then
               if [ ! -f "${srcdir}/configure"  ]
               then
                  # try for autogen if installed (not coded yet)
                  :
               fi
               if [ -x "${srcdir}/configure" ]
               then
                  build_configure "${configuration}" "${srcdir}" "${builddir}" "${name}" "${sdk}"  || exit 1
                  hasbuilt=yes
                  break
               fi
            fi

            if [ "${preference}" = "cmake" ]
            then
               if [ -f "${srcdir}/CMakeLists.txt" ]
               then
                  if [ ! -x "${cmake}" ]
                  then
                     log_warning "Found a CMakeLists.txt, but cmake is not installed"
                  else
                     build_cmake "${configuration}" "${srcdir}" "${builddir}" "${name}" "${sdk}"  || exit 1
                     hasbuilt=yes
                     break
                  fi
               fi
            fi
         done

         if [ "$hasbuilt" != "yes" ]
         then
            fail "Don't know how to build ${name}"
         fi
      done
   done
}


#
# ${DEPENDENCY_SUBDIR} is split into
#
#  REFERENCE_DEPENDENCY_SUBDIR and
#  BUILD_DEPENDENCY_SUBDIR
#
# above this function, noone should access ${DEPENDENCY_SUBDIR}
#
build_wrapper()
{
   local srcdir
   local name

   name="$1"
   srcdir="$2"

   REFERENCE_DEPENDENCY_SUBDIR="${DEPENDENCY_SUBDIR}"
   BUILD_DEPENDENCY_SUBDIR="${DEPENDENCY_SUBDIR}/tmp"

   DEPENDENCY_SUBDIR="WRONG_DONT_USE_DEPENDENCY_SUBDIR_DURING_BUILD"

   log_fluff "Setting up BUILD_DEPENDENCY_SUBDIR as \"${BUILD_DEPENDENCY_SUBDIR}\""

   if [ "${COMMAND}" != "ibuild" -a -d "${BUILD_DEPENDENCY_SUBDIR}" ]
   then
      log_fluff "Cleaning up orphaned \"${BUILD_DEPENDENCY_SUBDIR}\""
      rmdir_safer "${BUILD_DEPENDENCY_SUBDIR}"
   fi

   export BUILD_DEPENDENCY_SUBDIR
   export REFERENCE_DEPENDENCY_SUBDIR

   #
   # move dependencies we have so far away into safety,
   # need that path for includes though
   #

   run_repo_settings_script "${name}" "${srcdir}" "pre-build" "$@" || exit 1

   build "${name}" "${srcdir}" || exit 1

   run_repo_settings_script "${name}" "${srcdir}" "post-build" "$@" || exit 1

   if [ "${COMMAND}" != "ibuild"  ]
   then
      log_fluff "Remove \"${BUILD_DEPENDENCY_SUBDIR}\""
      rmdir_safer "${BUILD_DEPENDENCY_SUBDIR}"
   fi

   DEPENDENCY_SUBDIR="${REFERENCE_DEPENDENCY_SUBDIR}"

   # for mulle-bootstrap developers
   REFERENCE_DEPENDENCY_SUBDIR="WRONG_DONT_USE_REFERENCE_DEPENDENCY_SUBDIR_AFTER_BUILD"
   BUILD_DEPENDENCY_SUBDIR="WRONG_DONT_USE_BUILD_DEPENDENCY_SUBDIR_AFTER_BUILD"
}


build_if_alive()
{
   local name
   local srcdir

   name="$1"
   srcdir="$2"

   local xdone
   local zombie

   zombie="`dirname -- "${srcdir}"`/.zombies/${name}"
   if [ -e "${zombie}" ]
   then
      log_warning "Ignoring zombie repo ${name} as \"${zombie}${C_WARNING} exists"
   else
      xdone="`/bin/echo "${BUILT}" | grep -x "${name}"`"
      if [ "$xdone" = "" ]
      then
         build_wrapper "${name}" "${srcdir}"
         BUILT="${name}
${BUILT}"
      else
         log_fluff "Ignoring \"${name}\". (Either in \"build_ignore\" or already built)"
      fi
   fi
}


get_source_dir()
{
   local name

   name="${1}"

   local srcdir
   local srcsubdir

   srcdir="${CLONES_SUBDIR}/${name}"
   srcsubdir="`read_build_setting "${name}" "source_dir"`"
   if [ ! -z "${srcsubdir}" ]
   then
      srcdir="${srcdir}/${srcsubdir}"
   fi
   echo "${srcdir}"
}


build_clones()
{
   local clone
   local xdone
   local name
   local srcdir
   local srcsubdir
   local old

   old="${IFS:-" "}"

   for clone in ${CLONES_SUBDIR}/*.failed
   do
      if [ -d "${clone}" ]
      then
         fail "failed checkout $clone detected, can't continue"
      fi
   done

   run_build_root_settings_script "pre-build" "$@"

   #
   # build order is there, because we want to have gits
   # and maybe later hgs
   #
   BUILT=
   export BUILT

   if [ "$#" -eq 0 ]
   then
      BUILT="`read_build_root_setting "build_ignore"`"

      clones="`read_build_root_setting "build_order"`"
      IFS="
"
      for clone in ${clones}
      do
         IFS="$old"
         name="`canonical_clone_name "${clone}"`"
         srcdir="`get_source_dir "${name}"`"
         if [ -d "${srcdir}" ]
         then
            build_if_alive  "${name}" "${srcdir}" || exit 1
         else
            if has_usr_local_include "${name}"
            then
               :
            else
               fail "build_order contains unknown repo \"${clone}\" (\"${srcdir}\")"
            fi
         fi
      done
      IFS="$old"

      #
      # otherwise compile in repositories order
      #
      clones="`read_fetch_setting "repositories"`"
      if [ "${clones}" != "" ]
      then
         IFS="
"
         for clone in ${clones}
         do
            IFS="$old"

            name="`canonical_name_from_clone "${clone}"`"
            srcdir="`get_source_dir "${name}"`"

            if [ -d "${srcdir}" ]
            then
               build_if_alive "${name}" "${srcdir}" || exit  1
            else
               if has_usr_local_include "${name}"
               then
                  :
               else
                  fail "build failed for repository \"${clone}\": not found in (\"${srcdir}\") ($PWD)"
               fi
            fi
         done
      fi
   else
      for name in "$@"
      do
         srcdir="`get_source_dir "${name}"`"

         if [ -d "${srcdir}" ]
         then
            build_if_alive "${name}" "${srcdir}"|| exit 1
         else
            if has_usr_local_include "${name}"
            then
               :
            else
               fail "unknown repo ${name}"
            fi
         fi
      done
   fi

   IFS="$old"

   run_build_root_settings_script "post-build" "$@"
}


have_tars()
{
   tarballs=`read_fetch_setting "tarballs"`
   [ "${tarballs}" != "" ]
}


install_tars()
{
   local tarballs
   local tar

   tarballs=`read_fetch_setting "tarballs" | sort | sort -u`
   if [ "${tarballs}" = "" ]
   then
      return 0
   fi

   local old

   old="${IFS:-" "}"
   IFS="
"
   for tar in ${tarballs}
   do
      if [ ! -f "$tar" ]
      then
         fail "tarball \"$tar\" not found"
      else
         mkdir_if_missing "${DEPENDENCY_SUBDIR}"
         log_info "Installing tarball \"${tar}\""
         exekutor tar -xz -C "${DEPENDENCY_SUBDIR}" -f "${tar}" || fail "failed to extract ${tar}"
      fi
   done
   IFS="${old}"
}


main()
{
   local  clean

   log_verbose "::: build :::"

   #
   # START
   #
   if [ ! -d "${CLONES_SUBDIR}" ]
   then
      log_info "No repositories in \"${CLONES_SUBDIR}\", so nothing to build."
      return 0
   fi

   ensure_consistency

   if [ $# -eq 0 ]
   then
      log_fluff "Setting up dependencies directory as \"${DEPENDENCY_SUBDIR}\""
      clean="`read_config_setting "clean_dependencies_before_build" "YES"`"
      if [ "${clean}" = "YES" ]
      then
         rmdir_safer "${DEPENDENCY_SUBDIR}"
      fi
   else
      log_fluff "Unprotecting \"${DEPENDENCY_SUBDIR}\" (as this is a partial build)."
      exekutor chmod -R u+w "${DEPENDENCY_SUBDIR}"
   fi

   # if present then we didnt't want to clean and we do nothing special
   if [ ! -d "${DEPENDENCY_SUBDIR}" ]
   then
      install_tars "$@"
   else
      if have_tars
      then
         log_warning "Tars have not been installed, as \"${DEPENDENCY_SUBDIR}\" already exists."
      fi
   fi

   build_clones "$@"

   log_info "Write-protecting ${C_RESET_BOLD}${DEPENDENCY_SUBDIR}${C_INFO} to avoid spurious header edits"
   exekutor chmod -R a-w "${DEPENDENCY_SUBDIR}"
}

main "$@"
