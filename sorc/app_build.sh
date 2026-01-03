#!/usr/bin/env bash

set -x

# usage instructions
usage () {
cat << EOF_USAGE
Usage: $0 [OPTIONS]

OPTIONS
  -h, --help
      show this help guide
  -p, --platform=PLATFORM
      name of machine you are building on
      (e.g. gaeac6 | hercules | orion | ursa | derecho)
  -c, --compiler=COMPILER
      compiler to use; default depends on platform
      (e.g. intel | gnu | cray | gccgfortran)
  -a, --app=APPLICATION
      weather model application to build; for example, S2SWA for GFS
      (e.g. S2SWA | S2SWAL | NG-GODAS | ATM )
  --ccpp="CCPP_SUITE1,CCPP_SUITE2..."
      CCPP suites (CCPP_SUITES) to include in build; delimited with ','
  --remove
      removes existing build; overrides --continue
  --clean
      does a "make clean"
  --build
      build only in BUILD_DIR
  --move
      move binaries to final location.
  --fix_only
      soft-link static (fix) files to FIX dir and exit.
  --build-dir=BUILD_DIR
      build directory
  --install-dir=INSTALL_DIR
      installation prefix
  --jedi=BUILD_JEDI ( off | bundle | gdas | bundle-only | gdas-only )
  --jedi-dir=JEDI_DIR
      installation location of JEDI (bundle|GDAS)
  --build-type=BUILD_TYPE
      build type; defaults to Release
      (e.g. Debug | Release | RelWithDebInfo)
  --build-jobs=BUILD_JOBS
      number of build jobs; defaults to 4
  -v, --verbose
      build with verbose output

NOTE: See User's Guide for detailed build instructions

EOF_USAGE
}

# print settings
settings () {
cat << EOF_SETTINGS
Settings:

  HOME_DIR=${HOME_DIR}
  BUILD_DIR=${BUILD_DIR}
  INSTALL_DIR=${INSTALL_DIR}
  PLATFORM=${PLATFORM}
  COMPILER=${COMPILER}
  APP=${APPLICATION}
  CCPP=${CCPP_SUITES}
  REMOVE=${REMOVE}
  CLEAN=${CLEAN}
  BUILD=${BUILD}
  MOVE=${MOVE}
  FIX_ONLY=${FIX_ONLY}
  BUILD_TYPE=${BUILD_TYPE}
  BUILD_JOBS=${BUILD_JOBS}
  VERBOSE=${VERBOSE}

EOF_SETTINGS
}

# print usage error and exit
usage_error () {
  printf "ERROR: $1\n" >&2
  usage >&2
  exit 1
}

# default settings
LCL_PID=$$
SORC_DIR=$(cd "$(dirname "$(readlink -f -n "${BASH_SOURCE[0]}" )" )" && pwd -P)
HOME_DIR=$(realpath "${SORC_DIR}/..")
BUILD_DIR="${SORC_DIR}/build"
INSTALL_DIR="${SORC_DIR}/build"
JEDI_BUILD_DIR=""
COMPILER="intel"
APPLICATION="S2SWA"
CCPP_SUITES=""
BUILD_TYPE="Release"
BUILD_JOBS=4
REMOVE=false
VERBOSE=false
BUILD_JEDI="off"

# Make options
CLEAN=false
BUILD=false
MOVE=false
FIX_ONLY=false

# process required arguments
if [[ ("$1" == "--help") || ("$1" == "-h") ]]; then
  usage
  exit 0
fi

# process optional arguments
while :; do
  case $1 in
    --help|-h) usage; exit 0 ;;
    --platform=?*|-p=?*) PLATFORM=${1#*=} ;;
    --platform|--platform=|-p|-p=) usage_error "$1 requires argument." ;;
    --compiler=?*|-c=?*) COMPILER=${1#*=} ;;
    --compiler|--compiler=|-c|-c=) usage_error "$1 requires argument." ;;
    --app=?*|-a=?*) APPLICATION=${1#*=} ;;
    --app|--app=|-a|-a=) usage_error "$1 requires argument." ;;
    --ccpp=?*) CCPP_SUITES=${1#*=} ;;
    --ccpp|--ccpp=) usage_error "$1 requires argument." ;;
    --remove) REMOVE=true ;;
    --remove=?*|--remove=) usage_error "$1 argument ignored." ;;
    --clean) CLEAN=true ;;
    --build) BUILD=true ;;
    --move) MOVE=true ;;
    --fix_only) FIX_ONLY=true ;;
    --build-dir=?*) BUILD_DIR=${1#*=} ;;
    --build-dir|--build-dir=) usage_error "$1 requires argument." ;;
    --install-dir=?*) INSTALL_DIR=${1#*=} ;;
    --install-dir|--install-dir=) usage_error "$1 requires argument." ;;
    --jedi=?*) BUILD_JEDI=${1#*=} ;;
    --jedi|--jedi=) usage_error "$1 requires argument." ;;
    --jedi-dir=?*) JEDI_BUILD_DIR=${1#*=} ;;
    --jedi-dir|--jedi-dir=) usage_error "$1 requires argument." ;;
    --build-type=?*) BUILD_TYPE=${1#*=} ;;
    --build-type|--build-type=) usage_error "$1 requires argument." ;;
    --build-jobs=?*) BUILD_JOBS=$((${1#*=})) ;;
    --build-jobs|--build-jobs=) usage_error "$1 requires argument." ;;
    --verbose|-v) VERBOSE=true ;;
    --verbose=?*|--verbose=) usage_error "$1 argument ignored." ;;
    # unknown
    -?*|?*) usage_error "Unknown option $1" ;;
    *) break
  esac
  shift
done

# print settings
if [ "${VERBOSE}" = true ] ; then
  settings
fi
# make settings
MAKE_SETTINGS="-j ${BUILD_JOBS}"
if [ "${VERBOSE}" = true ]; then
  MAKE_SETTINGS="${MAKE_SETTINGS} VERBOSE=1"
fi

# Ensure uppercase / lowercase
APPLICATION=$(echo ${APPLICATION} | tr '[a-z]' '[A-Z]')
PLATFORM=$(echo ${PLATFORM} | tr '[A-Z]' '[a-z]')
COMPILER=$(echo ${COMPILER} | tr '[A-Z]' '[a-z]')
APP_LOWER=$(echo ${APPLICATION} | tr '[A-Z]' '[a-z]')

# check if PLATFORM is set
if [ -z $PLATFORM ] ; then
  # Automatically detect NOAA RDHPCS
  source ${HOME_DIR}/parm/detect_platform.sh
  if [ "${PLATFORM}" = "unknown" ]; then
    printf "\nERROR: Please set PLATFORM.\n\n"
    usage
    exit 0
  fi
fi
printf "PLATFORM(MACHINE)=${PLATFORM}\n" >&2

# === Soft-link static input files to FIX directory ===
if [ "${BUILD_JEDI}" != "bundle-only" ] && [ "${BUILD_JEDI}" != "gdas-only" ]; then
  ver_fix_data="v1.0"
  if [ "${PLATFORM}" = "ursa" ] || [ "${PLATFORM}" = "hera" ]; then
    fix_orig="/scratch3/NAGAPE/epic/UFS-DA-Workflow_${ver_fix_data}/inputs"
  elif [ "${PLATFORM}" = "orion" ] || [ "${PLATFORM}" = "hercules" ]; then
    fix_orig="/work2/noaa/epic/UFS-DA-Workflow_${ver_fix_data}/inputs"
  elif [ "${PLATFORM}" = "gaeac6" ]; then
    fix_orig="/gpfs/f6/epic/world-shared/UFS-DA-Workflow_${ver_fix_data}/inputs"
  elif [ "${PLATFORM}" = "derecho" ]; then
    fix_orig="/glade/work/chanhooj/UFS-DA-Workflow_${ver_fix_data}/inputs"
  else
    printf "FATAL ERROR: path to the fix files is not defined !!!"
    exit 1
  fi
  if find "${HOME_DIR}/fix" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) | grep -q .; then
    echo "At least one directory or symlink exists in FIX directory. Removing ..."
    rm -rf ${HOME_DIR}/fix/*
  fi
  ln -nsf ${fix_orig}/* ${HOME_DIR}/fix
  [[ "${FIX_ONLY}" == true ]] && exit 0
fi

# Move the pre-compiled executables to the designated location and exit
if [ "${BUILD}" = false ] && [ "${MOVE}" = true ]; then
  if [[ ! ${HOME_DIR} -ef ${INSTALL_DIR} ]]; then
    printf "... Moving pre-compiled executables to designated location ...\n"
    mkdir -p ${HOME_DIR}/exec
    cd "${INSTALL_DIR}/exec"
    for file in *; do
      [ -x "${file}" ] && mv "${file}" "${HOME_DIR}/exec"
    done
  fi
  exit 0
fi

# Remove option
if [ "${REMOVE}" = true ]; then
  printf "Remove build directory\n"
  printf "  BUILD_DIR=${BUILD_DIR}\n"
  if [ -d "${BUILD_DIR}" ]; then
    rm -rf ${BUILD_DIR}
  fi
  printf "Remove exec directory\n"
  if [ -d "${HOME_DIR}/exec" ]; then
    rm -rf "${HOME_DIR}/exec"
  fi
  printf "Remove lib directory\n"
  printf "  LIB_DIR=${HOME_DIR}/lib64\n"
  if [ -d "${HOME_DIR}/lib64" ]; then
    rm -rf "${HOME_DIR}/lib64"
  fi
  if [ -d "${HOME_DIR}/lib" ]; then
    rm -rf "${HOME_DIR}/lib"
  fi
  printf "Remove submodules\n"
  if [ -d "${SORC_DIR}/ufs_model.fd" ]; then
    printf "... Remove ufs_model.fd ...\n"
    rm -rf "${SORC_DIR}/ufs_model.fd"
  fi
  if [ -d "${SORC_DIR}/UFS_UTILS.fd" ]; then
    printf "... Remove UFS_UTILS.fd ...\n"
    rm -rf "${SORC_DIR}/UFS_UTILS.fd"
  fi

  cd "${HOME_DIR}"
  git submodule update --init --recursive
  cd "${SORC_DIR}"
  exit 0  
fi

# === Build JEDI-bundle, if requested (default: off) ===
if [ "${BUILD_JEDI}" != "off" ]; then
  if [ -z "${JEDI_BUILD_DIR}" ]; then
    if [ "${BUILD_JEDI}" = "bundle" ] || [ "${BUILD_JEDI}" = "bundle-only" ]; then
      JEDI_BUILD_DIR="${HOME_DIR}/../jedi"
    elif [ "${BUILD_JEDI}" = "gdas" ] || [ "${BUILD_JEDI}" = "gdas-only" ]; then
      JEDI_PDIR=$(dirname "${HOME_DIR}")
      JEDI_BUILD_DIR="${JEDI_PDIR}/GDASApp"
    fi
  fi
  jedi_build_skip="NO"
  if [ -d "${JEDI_BUILD_DIR}" ]; then
    printf "JEDI build directory (${JEDI_BUILD_DIR}) already exists.\n"
    printf "Do you want to remove the existing directory? \n"
    read -p "Type Y or y to remove, otherwise this step will be skipped:" jedi_dir_remove
    if [ "${jedi_dir_remove}" = "Y" ] || [ "${jedi_dir_remove}" = "y" ]; then
      rm -rf ${JEDI_BUILD_DIR}
      printf "The existing JEDI build directory has been removed. Rebuilding ... \n"
    else
      jedi_build_skip="YES"
    fi
  fi
  if [ "${jedi_build_skip}" = "NO" ]; then
    if [ "${PLATFORM}" = "gaeac6" ]; then
      module reset
    else
      module purge
    fi
    if [ "${PLATFORM}" = "hera" ]; then
      git lfs install --skip-repo
    else
      module load git-lfs
    fi
    if [ "${BUILD_JEDI}" = "bundle" ] || [ "${BUILD_JEDI}" = "bundle-only" ]; then
      module use ${SORC_DIR}/jedi-bundle/modulefiles
      module load ${PLATFORM}.${COMPILER}
      module list
      mkdir -p ${JEDI_BUILD_DIR}
      cd "${JEDI_BUILD_DIR}"
      cp -rp "${SORC_DIR}/jedi-bundle" .
      mkdir -p build
      cd build
      ecbuild "${JEDI_BUILD_DIR}/jedi-bundle" 2>&1 | tee log.jedibundle_ecbuild
      make ${MAKE_SETTINGS} 2>&1 | tee log.jedibundle_make
    elif [ "${BUILD_JEDI}" = "gdas" ] || [ "${BUILD_JEDI}" = "gdas-only" ]; then
      cd "${JEDI_PDIR}"
      git clone --recursive https://github.com/NOAA-EMC/GDASApp.git
      cd GDASApp
      # For specific hash
      git checkout 54dbb71
      git submodule update --init --recursive
      # Run build script
      ./build.sh -f -a -d -t ${PLATFORM}
    fi
    cd "${SORC_DIR}"
  fi
fi
[[ "${BUILD_JEDI}" == "bundle-only" || "${BUILD_JEDI}" == "gdas-only" ]] && exit 0

# === Build workflow components === 
if [ -d "${BUILD_DIR}" ]; then
  while true; do
    if [[ $(ps -o stat= -p ${LCL_PID}) != *"+"* ]] ; then
      printf "ERROR: Build directory already exists.\n" >&2
      printf "  BUILD_DIR=${BUILD_DIR}\n\n" >&2
      usage >&2
      exit 64
    fi
    # interactive selection
    printf "Build directory (${BUILD_DIR}) already exists.\n"
    printf "Please choose what to do:\n\n"
    printf "[R]emove the existing directory and continue to build\n"
    printf "[C]ontinue building in the existing directory\n"
    printf "[Q]uit this build script\n"
    read -p "Choose an option (R/C/Q):" choice
    case ${choice} in
      [Rr]* ) rm -rf ${BUILD_DIR}; break ;;
      [Cc]* ) break ;;
      [Qq]* ) exit ;;
      * ) printf "Invalid option selected.\n" ;;
    esac
  done
fi

# cmake settings
CMAKE_SETTINGS="\
 -DCMAKE_BUILD_TYPE=${BUILD_TYPE}\
 -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}"

if [ ! -z "${APPLICATION}" ]; then
  CMAKE_SETTINGS="${CMAKE_SETTINGS} -DAPP=${APPLICATION}"
fi
if [ ! -z "${CCPP_SUITES}" ]; then
  CMAKE_SETTINGS="${CMAKE_SETTINGS} -DCCPP_SUITES=${CCPP_SUITES}"
fi

if [ "${PLATFORM}" = "gaeac6" ]; then
  module reset
else
  module purge
fi

# set MODULE_FILE for this platform/compiler combination
MODULE_FILE="ufsda_${PLATFORM}.${COMPILER}"
if [ ! -f "${HOME_DIR}/modulefiles/${MODULE_FILE}.lua" ]; then
  printf "FATAL ERROR: module file does not exist for platform/compiler\n" >&2
  printf "  MODULE_FILE=${MODULE_FILE}\n" >&2
  printf "  PLATFORM=${PLATFORM}\n" >&2
  printf "  COMPILER=${COMPILER}\n\n" >&2
  printf "Please make sure PLATFORM and COMPILER are set correctly\n" >&2
  usage >&2
  exit 1
fi
printf "MODULE_FILE=${MODULE_FILE}\n" >&2

# load modules for platform/compiler combination, then build the code
printf "... Load MODULE_FILE and create BUILD directory ...\n"
module use ${HOME_DIR}/modulefiles
module load ${MODULE_FILE}
module list

mkdir -p ${BUILD_DIR}
cd ${BUILD_DIR}

if [ "${CLEAN}" = true ]; then
  if [ -f $PWD/Makefile ]; then
    printf "... Clean executables ...\n"
    make ${MAKE_SETTINGS} clean 2>&1 | tee log.make
  fi
else
  printf "... Generate CMAKE configuration ...\n"
  ecbuild ${SORC_DIR} ${CMAKE_SETTINGS} 2>&1 | tee log.ecbuild

  printf "... Compile executables ...\n"
  make ${MAKE_SETTINGS} 2>&1 | tee log.make

  # move executables to the designated location (HOMEdir/exec) only when 
  # both --build and --move are not set (no additional arguments) or
  # both --build and --move are set in the build command line
  if [[ "${BUILD}" = false && "${MOVE}" = false ]] || 
     [[ "${BUILD}" = true && "${MOVE}" = true ]]; then
    printf "... Moving pre-compiled executables to designated location ...\n"
    mkdir -p "${HOME_DIR}/exec"
    cd "${INSTALL_DIR}/bin"
    # copy executables in build/bin to HOME_DIR/exec
    for file in *; do
      [ -x "${file}" ] && cp "${file}" "${HOME_DIR}/exec"
    done
    # change executable name of ufs_model
    if [ -f "${HOME_DIR}/exec/ufs_model" ]; then
      mv "${HOME_DIR}/exec/ufs_model" "${HOME_DIR}/exec/ufs_model_${APP_LOWER}"
    fi
    # copy libraries
    if [ -d "${BUILD_DIR}/lib64" ]; then
      mkdir -p ${HOME_DIR}/lib64
      cd ${BUILD_DIR}/lib64
      for file in *; do
        [ -f "${file}" ] && cp "${file}" "${HOME_DIR}/lib64"
      done
    fi
  fi
fi

exit 0
