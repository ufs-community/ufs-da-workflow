################################################################################
# UFS-DA-Workflow
################################################################################

cmake_minimum_required( VERSION 3.12 )
project( UFSDA VERSION 0.0.0 LANGUAGES C CXX Fortran )
find_package(ecbuild 3.3.2 REQUIRED)
enable_testing()

# Inlcude externalproject
# -----------------------
add_custom_target(build DEPENDS pbuild)
include(ExternalProject)

################################################################################
# Dependencies
################################################################################
find_package(MPI REQUIRED COMPONENTS C CXX Fortran)
find_package(NetCDF REQUIRED COMPONENTS Fortran)
include_directories( ${NETCDF_INCLUDE_DIRS} )

################################################################################
# Sources
################################################################################

message(APP="${APP}")
if(NOT APP)
  set(APP "S2SWA")
endif()
message(APP="${APP}")

message(CCPP_SUITES="${CCPP_SUITES}")
if( NOT CCPP_SUITES )
  if( APP MATCHES "S2SWA" OR APP MATCHES "S2SWAL" )
    set(CCPP_SUITES "FV3_GFS_v17_coupled_p8_ugwpv1")
  elseif( APP MATCHES "ATML" OR APP MATCHES "ATM" )
    set(CCPP_SUITES "FV3_GFS_v17_p8_ugwpv1" )
  endif()
endif()
message(CCPP_SUITES="${CCPP_SUITES}")

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE "Release")
endif()

# UFS Weather Model (ufs_model)
list(APPEND UFS_MODEL_ARGS
  "-DCMAKE_INSTALL_PREFIX=${CMAKE_INSTALL_PREFIX}"    
  "-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}"
  "-DAPP=${APP}"
  "-DCCPP_SUITES=${CCPP_SUITES}"
  "-DMPI=ON"
)
if( APP MATCHES "S2SWA" )
  list(APPEND UFS_MODEL_ARGS
    "-D32BIT=ON"
    "-DPDLIB=ON"
  )
elseif( APP MATCHES "ATML" OR APP MATCHES "ATM" )
  list(APPEND UFS_MODEL_ARGS
    "-D32BIT=ON"
  )
endif()
if( NOT DA_UTILS_ONLY )
  list(APPEND TARGET LIST ufs_model.fd)
  ExternalProject_Add(ufs_model.fd
    PREFIX ${CMAKE_CURRENT_BINARY_DIR}/ufs_model.fd
    SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/ufs_model.fd
    INSTALL_DIR ${CMAKE_INSTALL_PREFIX}
    CMAKE_ARGS ${UFS_MODEL_ARGS}
    INSTALL_COMMAND mkdir -p ${CMAKE_INSTALL_PREFIX}/bin && cp ${CMAKE_CURRENT_BINARY_DIR}/ufs_model.fd/src/ufs_model.fd-build/ufs_model ${CMAKE_INSTALL_PREFIX}/bin
    BUILD_ALWAYS TRUE
    STEP_TARGETS build
)
endif()

# UFS_UTILS
if( APP MATCHES "ATML" )
  list(APPEND UFS_UTILS_ARGS
    "-DCMAKE_INSTALL_PREFIX=${CMAKE_INSTALL_PREFIX}"
    "-DBUILD_TESTING=OFF"
    "-DCHGRES=ON"
    "-DCPLD_GRIDGEN=OFF"
    "-DFRENCTOOLS=OFF"
    "-DFVCOMTOOLS=OFF"
    "-DGBLEVENTS=OFF"
    "-DGCYCLE=OFF"
    "-DGRIDTOOLS=OFF"
    "-DICEBLEND=OFF"
    "-DOCEAN_MERGE=OFF"
    "-DOROG_MASK_TOOLS=OFF"
    "-DSFC_CLIMO_GEN=OFF"
    "-DSNOW2MDL=OFF"
    "-DVCOORD_GEN=OFF"
    "-DWEIGHT_GEN=OFF"
  )
else()
  list(APPEND UFS_UTILS_ARGS
  "-DCMAKE_INSTALL_PREFIX=${CMAKE_INSTALL_PREFIX}"
  "-DBUILD_TESTING=OFF"
  "-DCHGRES=ON"
  "-DCHGRES_ALL=OFF"
  "-DCPLD_GRIDGEN=ON"
  "-DFRENCTOOLS=OFF"
  "-DFVCOMTOOLS=OFF"
  "-DGBLEVENTS=OFF"
  "-DGCYCLE=OFF"
  "-DGFS=OFF"
  "-DGRIDTOOLS=OFF"
  "-DICEBLEND=OFF"
  "-DOCEAN_MERGE=OFF"
  "-DOCNICE_PREP=ON"
  "-DREGRID=OFF"
  "-DOROG_MASK_TOOLS=ON"
  "-DOROG_NETCDF_TOOLS=OFF"
  "-DSFC_CLIMO_GEN=OFF"
  "-DSNOW2MDL=OFF"
  "-DVCOORD_GEN=OFF"
  "-DWEIGHT_GEN=OFF"
  )
endif()
if( NOT DA_UTILS_ONLY AND NOT APP STREQUAL "LND" )
  if( APP MATCHES "ATML" )
    list(APPEND TARGET LIST UFS_UTILS_nofrac.fd)
    ExternalProject_Add(UFS_UTILS_nofrac.fd
      PREFIX ${CMAKE_CURRENT_BINARY_DIR}/UFS_UTILS_nofrac.fd
      SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/UFS_UTILS_nofrac.fd
      INSTALL_DIR ${CMAKE_INSTALL_PREFIX}
      CMAKE_ARGS ${UFS_UTILS_ARGS}
      BUILD_ALWAYS TRUE
      STEP_TARGETS build
    )
  else()
    list(APPEND TARGET LIST UFS_UTILS.fd)
    ExternalProject_Add(UFS_UTILS.fd
      PREFIX ${CMAKE_CURRENT_BINARY_DIR}/UFS_UTILS.fd
      SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/UFS_UTILS.fd
      INSTALL_DIR ${CMAKE_INSTALL_PREFIX}
      CMAKE_ARGS ${UFS_UTILS_ARGS}
      BUILD_ALWAYS TRUE
      STEP_TARGETS build
    )
  endif()
endif()

# For snow / soil-moisture DA analysis
if( NOT APP STREQUAL "NG-GODAS" OR DA_UTILS_ONLY )
  # APPLY_INCR for JEDI snow-DA
  list(APPEND APPLY_INCR_ARGS
  "-DCMAKE_INSTALL_PREFIX=${CMAKE_INSTALL_PREFIX}"
  )
  list(APPEND TARGET LIST apply_incr.fd)
  ExternalProject_Add(apply_incr.fd
    PREFIX ${CMAKE_CURRENT_BINARY_DIR}/apply_incr.fd
    SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/apply_incr.fd
    INSTALL_DIR ${CMAKE_INSTALL_PREFIX}
    CMAKE_ARGS ${APPLY_INCR_ARGS}
    BUILD_ALWAYS TRUE
    STEP_TARGETS build
  )

  # calcfIMS for IMS snow data
  list(APPEND calcfIMS_ARGS
  "-DCMAKE_INSTALL_PREFIX=${CMAKE_INSTALL_PREFIX}"
  )
  list(APPEND TARGET LIST calcfIMS.fd)
  ExternalProject_Add(calcfIMS.fd
    PREFIX ${CMAKE_CURRENT_BINARY_DIR}/calcfIMS.fd
    SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/calcfIMS.fd
    INSTALL_DIR ${CMAKE_INSTALL_PREFIX}
    CMAKE_ARGS ${calcfIMS_ARGS}
    BUILD_ALWAYS TRUE
    STEP_TARGETS build
  )
endif()

# C-Test
#add_subdirectory(test)

# add custom target for separate build and install
foreach(i ${TARGET_LIST})
  list(APPEND BUILD_LIST "${i}-build")
endforeach()

add_custom_target(pbuild DEPENDS ${BUILD_LIST})
