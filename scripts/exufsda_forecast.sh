#!/usr/bin/env bash

set -xue

ulimit -s unlimited; ulimit -a;

export OMP_STACKSIZE=512M
export KMP_AFFINITY=scatter
export OMP_NUM_THREADS=1
export ESMF_RUNTIME_PROFILE=ON
export ESMF_RUNTIME_PROFILE_OUTPUT="SUMMARY"
export I_MPI_EXTRA_FILESYSTEM=ON
export FI_MLX_INJECT_LIMIT=0
if [ "${APP}" = "S2SWAL" ]; then
  export MPI_TYPE_DEPTH=20
  export ESMF_RUNTIME_COMPLIANCECHECK=OFF:depth=4
  export PSM_RANKS_PER_CONTEXT=4
  export PSM_SHAREDCONTEXTS=1
fi

machines_srun=( "gaeac6" "hera" "hercules" "orion" "ursa" )
if [[ ${machines_srun[@]} =~ "${MACHINE}" ]]; then
  run_cmd="srun"
else
  run_cmd=`which mpiexec`
fi
app_lower=$(echo ${APP} | tr '[A-Z]' '[a-z]')

NTIME=$($NDATE ${DATE_CYCLE_FREQ_HR} $PDY$cyc)
PTIME=$($NDATE -${DATE_CYCLE_FREQ_HR} $PDY$cyc)

YYYY=${PDY:0:4}
MM=${PDY:4:2}
DD=${PDY:6:2}
HH=${cyc}
nYYYY=${NTIME:0:4}
nMM=${NTIME:4:2}
nDD=${NTIME:6:2}
nHH=${NTIME:8:2}
PDYcm1=${PTIME:0:8}
COMINOUTcm1="${COMINOUTcm1:-${COMROOT}/${NET}/${model_ver}/${RUN}.${PDYcm1}}"

HHsec=$(( HH * 3600 ))
HHsec_5d=$(printf "%05d" "${HHsec}")
nHHsec=$(( nHH * 3600 ))
nHHsec_5d=$(printf "%05d" "${nHHsec}")

filedate=${PDY}.${cyc}0000

#############################
# Input/output directories
#############################
mkdir -p INPUT
mkdir -p RESTART

########################
# ATM model component
########################
echo "==================== ATM model component ============================"
if [ "${atm_model}" = "fv3" ]; then
  echo "===== ATM: FV3 ====="
  ###############
  # FV3 files
  ###############
  # field_table
  cp -p "${COMINOUT}/field_table_${PDY}${cyc}" field_table

  # FV3 global fix files
  ln -nsf ${FIXufsda}/DATA_fix/FV3/Global/* .

  # FV3 tiled fix files
  sfc_fns=( "facsf" \
	    "maximum_snow_albedo" \
	    "slope_type" \
	    "snowfree_albedo" \
	    "soil_color" \
	    "soil_type" \
	    "substrate_temperature" \
	    "vegetation_greenness" \
	    "vegetation_type" )
  for ifn in "${sfc_fns[@]}" ; do
    for itile in {1..6};
    do
      ifp="${FIXufsda}/DATA_fix/FV3/Tiled/C${RES}/C${RES}.${ifn}.tile${itile}.nc"
      if [ -e "${ifp}" ]; then
        ln -nsf ${ifp} .
      else
        err_exit "Symlink failed: ${ifp} does not exist."
      fi
    done
  done

  # INPUT directory
  cd ${DATA}/INPUT
  ## Grid/orography/mosaic files
  for itile in {1..6}
  do
    ln -nsf "${FIXufsda}/DATA_fix/FV3/Tiled/C${RES}/C${RES}_oro_data.tile${itile}.nc" oro_data.tile${itile}.nc
    ln -nsf "${FIXufsda}/DATA_fix/FV3/Tiled/C${RES}/C${RES}_grid.tile${itile}.nc" .
    ln -nsf "${FIXufsda}/DATA_fix/FV3/Tiled/C${RES}/C${RES}_oro_data_ls.tile${itile}.nc" oro_data_ls.tile${itile}.nc
    ln -nsf "${FIXufsda}/DATA_fix/FV3/Tiled/C${RES}/C${RES}_oro_data_ss.tile${itile}.nc" oro_data_ss.tile${itile}.nc
  done
  ln -nsf "${FIXufsda}/DATA_fix/FV3/Tiled/C${RES}/C${RES}_mosaic.nc" .
  if [ "${APP}" = "ATM" ]; then
    ln -nsf "${FIXufsda}/DATA_fix/FV3/Tiled/C${RES}/C${RES}_grid_spec.nc_${app_lower}" grid_spec.nc
  else
    ln -nsf "${FIXufsda}/DATA_fix/FV3/Tiled/C${RES}/C${RES}_grid_spec.nc" grid_spec.nc
  fi
  
  ## IC (initial condition) files for cold start
  if [ "${COLDSTART}" = "YES" ] && [ "${PDY}${cyc}" = "${DATE_FIRST_CYCLE:0:10}" ]; then
    if [ "${IC_FROM_FIX_DIR}" = "YES" ]; then
      data_dir="${FIXufsda}/DATA_ics/${PDY}/${cyc}"
    else
      data_dir="${COMINOUT}"
    fi
    ln -nsf "${data_dir}/gfs_ctrl.nc" .
    for itile in {1..6}
    do
      ln -nsf "${data_dir}/gfs_data.tile${itile}.nc" .
      ln -nsf "${data_dir}/sfc_data.tile${itile}.nc" .
    done
  fi
  
  ## Copy restart files
  if [ "${COLDSTART}" = "NO" ] || [ "${PDY}${cyc}" != "${DATE_FIRST_CYCLE:0:10}" ]; then
    if [ "${COLDSTART}" = "NO" ] && [ "${PDY}${cyc}" = "${DATE_FIRST_CYCLE:0:10}" ]; then
      data_dir="${WARMSTART_DIR}"
    else
      data_dir="${COMINOUTcm1}/RESTART"
    fi
  
    ### Tiled files
    rst_fns=( "ca_data" "fv_core.res" "fv_srf_wnd.res" "fv_tracer.res" "phy_data" )
    for ifn in "${rst_fns[@]}" ; do
      for itile in {1..6};
      do
        r_fp="${data_dir}/${filedate}.${ifn}.tile${itile}.nc"
        if [ -e "${r_fp}" ]; then
          ln -nsf "${r_fp}" "${ifn}.tile${itile}.nc"
        else
          err_exit "Symlink failed: ${r_fp} file does not exist."
        fi
      done
    done
  
    ### Single files (time format: YYYYMMDD.HH0000)
    r_fp="${data_dir}/${filedate}.fv_core.res.nc"
    if [ -e "${r_fp}" ]; then
      ln -nsf "${r_fp}" "fv_core.res.nc"
    else
      err_exit "Symlink failed: ${r_fp} file does not exist."
    fi
  
    ### Files updated by ANALYSIS (JEDI)
    if [ "${DO_FREE_FORECAST}" = "none" ]; then
      data_dir="${COMINOUT}"
    else
      if [ "${COLDSTART}" = "NO" ] && [ "${PDY}${cyc}" = "${DATE_FIRST_CYCLE:0:10}" ]; then
        data_dir="${WARMSTART_DIR}"
      else
        data_dir="${COMINOUTcm1}/RESTART"
      fi
    fi
    for itile in {1..6};
    do
      r_fp="${data_dir}/${filedate}.sfc_data.tile${itile}.nc"
      if [ -e "${r_fp}" ]; then
        ln -nsf "${r_fp}" "sfc_data.tile${itile}.nc"
      else
        err_exit "Symlink failed: ${r_fp} file does not exist."
      fi
    done
  
    ### create coupler.res file
    settings="\
  'yyyp': !!str ${YYYY}
  'mp': !!str ${MM}
  'dp': !!str ${DD}
  'hp': !!str ${HH}
  'yyyy': !!str ${YYYY}
  'mm': !!str ${MM}
  'dd': !!str ${DD}
  'hh': !!str ${HH}
" # End of settings variable
    fp_template="${PARMufsda}/templates/template.coupler.res"
    fn_namelist="coupler.res"
    ${USHufsda}/fill_jinja_template.py -u "${settings}" -t "${fp_template}" -o "${fn_namelist}"
  fi
  cd ${DATA}

  # Declaration of variables not for fv3 but for template
  datm_mesh_fn=""

elif [ "${atm_model}" = "datm" ]; then
  echo "===== ATM: DATM ====="
  ######################
  # DATM forcing data
  ######################
  datm_data_type_upper=$(echo ${DATM_DATA_TYPE} | tr '[a-z]' '[A-Z]')
  # List of stream data files
  list_stream_data_files=()
  list_stream_fn=()
  cmonth=$(date -d "${PDY:0:6}01" +%Y%m)
  while [ "${cmonth}" -le "${NTIME:0:6}" ]; do
    list_stream_data_files+=("\"INPUT/${DATM_DATA_TYPE}.${cmonth}.nc\"")
    list_stream_fn+=("${DATM_DATA_TYPE}.${cmonth}.nc")
    cmonth=$(date -d "${cmonth}01 +1 month" +%Y%m)
  done

  datm_datamode="GEFS"
  datm_mesh_fn="mesh.datm.${datm_nx_global}x${datm_ny_global}.nc"
  datm_model_maskfile="INPUT/${datm_mesh_fn}"
  datm_model_meshfile="INPUT/${datm_mesh_fn}"
  datm_export_all=".false."
  stream_dtlimit01="1.0"
  stream_info="${DATM_DATA_TYPE}.01"
  stream_mesh_file="INPUT/${datm_mesh_fn}"

  # datm_in
  settings="\
  'datm_datamode': ${datm_datamode}
  'datm_model_maskfile': ${datm_model_maskfile}
  'datm_model_meshfile': ${datm_model_meshfile}
  'datm_nx_global': ${datm_nx_global}
  'datm_ny_global': ${datm_ny_global}
  'datm_export_all': ${datm_export_all}
" # End of settings variable
  fp_template="${PARMufsda}/templates/template.datm_in"
  fn_namelist="datm_in"
  ${USHufsda}/fill_jinja_template.py -u "${settings}" -t "${fp_template}" -o "${fn_namelist}"
  
  # datm.streams
  settings="\
  'year_first': !!str ${YYYY}
  'year_last': !!str ${nYYYY}
  'year_align': !!str ${YYYY}
  'stream_dtlimit01': ${stream_dtlimit01}
  'stream_info': ${stream_info}
  'stream_mesh_file': ${stream_mesh_file}
  'stream_data_files': '${list_stream_data_files[@]}'
" # End of settings variable
  fp_template="${PARMufsda}/templates/template.datm.streams"
  fn_namelist="datm.streams"
  ${USHufsda}/fill_jinja_template.py -u "${settings}" -t "${fp_template}" -o "${fn_namelist}"

  # INPUT directory
  cd ${DATA}/INPUT
  ## Fix (mesh) file
  ln -nsf "${FIXufsda}/DATA_fix/DATM/${DATM_DATA_TYPE}/${datm_mesh_fn}" .
  ## Forcing data files
  for ifn in "${list_stream_fn[@]}" ; do
    ln -nsf "${FIXufsda}/DATA_datm/${DATM_DATA_TYPE}/${ifn}" .
  done
  cd ${DATA}

  # Restart files
  if [ "${COLDSTART}" = "NO" ] || [ "${PDY}${cyc}" != "${DATE_FIRST_CYCLE:0:10}" ]; then
    if [ "${COLDSTART}" = "NO" ] && [ "${PDY}${cyc}" = "${DATE_FIRST_CYCLE:0:10}" ]; then
      data_dir="${WARMSTART_DIR}"
    else
      data_dir="${COMINOUTcm1}/RESTART"
    fi
    r_fn="DATM_${datm_data_type_upper}.datm.r.${YYYY}-${MM}-${DD}-${HHsec_5d}.nc"
    r_fp="${data_dir}/${r_fn}"
    if [ -e "${r_fp}" ]; then
      ln -nsf "${r_fp}" .
      ls -1 "${r_fn}">rpointer.atm
    else
      err_exit "Symlink failed: ${r_fp} file does not exist."
    fi
  fi
fi


########################
# OCN model component
########################
echo "==================== OCN model component ============================"
if [ "${ocn_model}" = "mom6" ]; then
  echo "===== OCN: MOM6 ====="
  ###############
  # MOM6 files
  ###############
  # output directory
  mkdir -p MOM6_OUTPUT

  ## Mesh file
  if [ ! -e "${OCN_MESH_FN}" ]; then
    ln -nsf "${FIXufsda}/DATA_fix/MOM6/${OCN_MESH_FN}" .
  fi

  # INPUT directory
  cd ${DATA}/INPUT
  ## Fix files
  ocn_fns=( "atmos_mosaic_tile1Xland_mosaic_tile1.nc" \
	    "atmos_mosaic_tile1Xocean_mosaic_tile1.nc" \
            "hycom1_75_800m.nc" \
	    "interpolate_zgrid_40L.nc" \
	    "KH_background_2d.nc" \
	    "land_mask.nc" \
            "land_mosaic_tile1Xocean_mosaic_tile1.nc" \
	    "layer_coord.nc" \
	    "MOM_channels_SPEAR" \
	    "ocean_hgrid.nc" \
	    "ocean_mask.nc" \
	    "ocean_mosaic.nc" \
	    "seawifs_1998-2006_smoothed_2X.nc" \
	    "tidal_amplitude.nc" \
	    "topog.nc" \
	    "ufs.topo_edits_011818.nc" \
	    "vgrid_75_2m.nc" )
  for ifn in "${ocn_fns[@]}" ; do
    ifp="${FIXufsda}/DATA_fix/MOM6/${ifn}"
    if [ -e "${ifp}" ]; then
      ln -nsf ${ifp} .
    else
      err_exit "Symlink failed: ${ifp} does not exist."
    fi
  done
  
  ## MOM6 input namelist files
  ### MOM_input
  cp -p "${COMINOUT}/MOM_input_${PDY}${cyc}" MOM_input

  ### MOM_override
  cp -p "${PARMufsda}/templates/template.MOM_override" MOM_override

  ## IC (initial condition) files for cold start
  if [ "${COLDSTART}" = "YES" ] && [ "${PDY}${cyc}" = "${DATE_FIRST_CYCLE:0:10}" ]; then
    if [ "${IC_FROM_FIX_DIR}" = "YES" ]; then
      data_dir="${FIXufsda}/DATA_ics/${PDY}/${cyc}"
    else
      data_dir="${COMINOUT}"
    fi
    ln -nsf "${data_dir}/MOM6_IC_TS_${PDY}${cyc}.nc" "MOM6_IC_TS.nc"
  fi

  ## Restart files
  if [ "${COLDSTART}" = "NO" ] || [ "${PDY}${cyc}" != "${DATE_FIRST_CYCLE:0:10}" ]; then
    ### Files updated by ANALYSIS (JEDI)
    if [ "${JEDI_TYPE_SOCA}" = "YES" ] && [ "${DO_FREE_FORECAST}" = "none" ]; then
      data_dir="${COMINOUT}"
    else
      if [ "${COLDSTART}" = "NO" ] && [ "${PDY}${cyc}" = "${DATE_FIRST_CYCLE:0:10}" ]; then
        data_dir="${WARMSTART_DIR}"
      else
        data_dir="${COMINOUTcm1}/RESTART"
      fi
    fi
    r_fp="${data_dir}/${filedate}.MOM.res.nc"
    if [ -e "${r_fp}" ]; then
      ln -nsf "${r_fp}" "MOM.res.nc"
    else
      err_exit "Symlink failed: ${r_fp} file does not exist."
    fi
  fi
  cd ${DATA}
fi


########################
# ICE model component
########################
echo "==================== ICE model component ============================"
if [ "${ice_model}" = "cice6" ]; then
  echo "===== ICE: CICE6 ====="
  ###############
  # CICE files
  ###############
  # copy ice_in
  cp -p "${COMINOUT}/ice_in_${PDY}${cyc}" ice_in

  # Fix files
  ice_fns=( "grid_cice_NEMS_mx100.nc" "kmtu_cice_NEMS_mx100.nc" )
  for ifn in "${ice_fns[@]}" ; do
    ifp="${FIXufsda}/DATA_fix/CICE/${ifn}"
    if [ -e "${ifp}" ]; then
      ln -nsf ${ifp} .
    else
      err_exit "Symlink failed: ${ifp} does not exist."
    fi
  done

  # CICE histoy directory
  mkdir -p history

  # IC file for cold start (set by parameter 'ice_ic' in input namelist 'ice_in')
  if [ "${COLDSTART}" = "YES" ] && [ "${PDY}${cyc}" = "${DATE_FIRST_CYCLE:0:10}" ]; then
    if [ "${IC_FROM_FIX_DIR}" = "YES" ]; then
      data_dir="${FIXufsda}/DATA_ics/${PDY}/${cyc}"
    else
      data_dir="${COMINOUT}"
    fi
    ln -nsf "${data_dir}/cice_model.res.nc" .
  fi

  # Restart and pointer files
  if [ "${COLDSTART}" = "NO" ] || [ "${PDY}${cyc}" != "${DATE_FIRST_CYCLE:0:10}" ]; then
    if [ "${COLDSTART}" = "NO" ] && [ "${PDY}${cyc}" = "${DATE_FIRST_CYCLE:0:10}" ]; then
      data_dir="${WARMSTART_DIR}"
    else
      data_dir="${COMINOUTcm1}/RESTART"
    fi
    r_fn="iced.${YYYY}-${MM}-${DD}-${HHsec_5d}.nc"
    r_fp="${data_dir}/${r_fn}"
    if [ -e "${r_fp}" ]; then
      ln -nsf "${r_fp}" "RESTART/${r_fn}"
      ls -1 "./RESTART/${r_fn}">ice.restart_file
    else
      err_exit "Symlink failed: ${r_fp} file does not exist."
    fi
  fi
fi


########################
# WAV model component
########################
echo "==================== WAV model component ============================"
if [ "${wav_model}" = "ww3" ]; then
  echo "===== WAV: WW3 ====="
  ##############
  # WW3 files
  ##############
  # set ww3_shel.nml
  output_fh_ww3_sec=$(( OUTPUT_FH_WW3 * 3600 ))
  settings="\
  'output_fh_ww3_sec': ${output_fh_ww3_sec}
" # End of settings variable
  fp_template="${PARMufsda}/templates/template.ww3_shel.nml"
  fn_namelist="ww3_shel.nml"
  ${USHufsda}/fill_jinja_template.py -u "${settings}" -t "${fp_template}" -o "${fn_namelist}"

  # fix files	
  wav_fns=( "ww3_points.list" "mesh.global_270k.nc" )
  for ifn in "${wav_fns[@]}" ; do
    ifp="${FIXufsda}/DATA_fix/WW3/${ifn}"
    if [ -e "${ifp}" ]; then
      ln -nsf ${ifp} .
    else
      err_exit "Symlink failed: ${ifp} does not exist."
    fi
  done

  # mod_def.ww3 file
  ifp="${FIXufsda}/DATA_fix/WW3/mod_def.ww3_${APP}"
  if [ -e "${ifp}" ]; then
    ln -nsf ${ifp} "mod_def.ww3"
  else
    err_exit "Symlink failed: ${ifp} does not exist."
  fi  

  # CMEPS restart files
  if [ "${COLDSTART}" = "NO" ] || [ "${PDY}${cyc}" != "${DATE_FIRST_CYCLE:0:10}" ]; then
    if [ "${COLDSTART}" = "NO" ] && [ "${PDY}${cyc}" = "${DATE_FIRST_CYCLE:0:10}" ]; then
      data_dir="${WARMSTART_DIR}"
    else
      data_dir="${COMINOUTcm1}"
    fi
    r_fn="ufs.cpld.ww3.r.${YYYY}-${MM}-${DD}-${HHsec_5d}.nc"
    r_fp="${data_dir}/${r_fn}"
    if [ -e "${r_fp}" ]; then
      ln -nsf "${r_fp}" .
    else
      err_exit "Symlink failed: ${r_fp} file does not exist."
    fi
  fi
fi


########################
# CHM model component
########################
echo "==================== CHM model component ============================"
if [ "${chm_model}" = "gocart" ]; then
  echo "===== CHM: GOCART ====="
  # Fix files   
  ln -nsf ${FIXufsda}/DATA_fix/GOCART/ExtData .
  # Input files
  cp -p ${PARMufsda}/templates/gocart/*.rc .
  # cap_restart file
  if [ "${COLDSTART}" = "NO" ] || [ "${PDY}${cyc}" != "${DATE_FIRST_CYCLE:0:10}" ]; then
    cat <<< "${PDY} ${cyc}0000" > cap_restart
  fi
fi


########################
# LND model component
########################
echo "==================== LND model component ============================"
if [ "${lnd_model}" = "noahmp" ]; then
  echo "===== LND: Noah-MP ====="
  # LND restart files
  if [ "${COLDSTART}" = "NO" ] || [ "${PDY}${cyc}" != "${DATE_FIRST_CYCLE:0:10}" ]; then
    if [ "${COLDSTART}" = "NO" ] && [ "${PDY}${cyc}" = "${DATE_FIRST_CYCLE:0:10}" ]; then
      data_dir="${WARMSTART_DIR}"
    else
      data_dir="${COMINOUTcm1}/RESTART"
    fi
    for itile in {1..6};
    do
      r_fp="${data_dir}/ufs.cpld.lnd.out.${YYYY}-${MM}-${DD}-${HHsec_5d}.tile${itile}.nc"
      if [ -e "${r_fp}" ]; then
        ln -nsf "${r_fp}" RESTART/.
      else
        err_exit "Symlink failed: ${r_fp} file does not exist."
      fi
    done
  fi
fi


################
# CMEPS files
################
if [ "${APP}" != "ATM" ]; then
  echo "==================== CMEPS Files ===================================="
  if [ "${COLDSTART}" = "NO" ] || [ "${PDY}${cyc}" != "${DATE_FIRST_CYCLE:0:10}" ]; then
    if [ "${COLDSTART}" = "NO" ] && [ "${PDY}${cyc}" = "${DATE_FIRST_CYCLE:0:10}" ]; then
      data_dir="${WARMSTART_DIR}"
    else
      data_dir="${COMINOUTcm1}/RESTART"
    fi
    # Restart from RESTART and pointer files
    if [ "${atm_model}" = "fv3" ]; then
      r_fn_prefix="ufs.cpld"
    elif [ "${atm_model}" = "datm" ]; then
      r_fn_prefix="DATM_${datm_data_type_upper}"
    fi
    r_fn="${r_fn_prefix}.cpl.r.${YYYY}-${MM}-${DD}-${HHsec_5d}.nc"
    r_fp="${data_dir}/${r_fn}"
    if [ -e "${r_fp}" ]; then
      ln -nsf "${r_fp}" .
      ls -1 "${r_fn}">rpointer.cpl
    else
      err_exit "Symlink failed: ${r_fp} file does not exist."
    fi
  fi
fi


#####################################
# Copy app-independent input files
#####################################
# fd_ufs.yaml
cp -p "${PARMufsda}/templates/template.fd_ufs.yaml" fd_ufs.yaml
# data_table
if [ "${APP}" != "ATM"]; then
  cp -p "${PARMufsda}/templates/template.data_table" data_table
fi

########################################################
# Copy input namelist files created by PREP_DATA task
########################################################
# inpt.nml
cp -p "${COMINOUT}/input.nml_${PDY}${cyc}" input.nml
# ufs.configure
cp -p "${COMINOUT}/ufs.configure_${PDY}${cyc}" ufs.configure
# model_configure
cp -p "${COMINOUT}/model_configure_${PDY}${cyc}" model_configure
# diag_table
cp -p "${COMINOUT}/diag_table_${PDY}${cyc}" diag_table

##########################
# Run ufs-weather-model
##########################
export pgm="ufs_model_${app_lower}"
. prep_step
${run_cmd} --label -n ${nprocs_forecast} ${EXECufsda}/$pgm >>$pgmout 2>errfile
export err=$?; err_chk
cp errfile errfile_ufs_model
if [[ $err != 0 ]]; then
  err_exit "ufs_model failed"
fi

##################################
# Copy output files to COMINOUT
##################################
########
# FV3
########
if [ "${atm_model}" = "fv3" ]; then
  read -ra out_fh <<< "${OUTPUT_FH}"
  out_fh1="${out_fh[0]}"
  out_fh2="${out_fh[1]}"
  if [ "${out_fh2}" = "-1" ]; then
    list_out_fh=$(seq 0 ${out_fh1} ${FCST_HRS})
  else
    list_out_fh=${OUTPUT_FH}
  fi
  for ihr in ${list_out_fh}
  do
    ihr_3d=$(printf "%03d" "${ihr}")
    for itile in {1..6}
    do
      cp -p "${DATA}/atmf${ihr_3d}.tile${itile}.nc" "${COMINOUT}/${NET}.${cycle}.atm.f${ihr_3d}.c${RES}.tile${itile}.nc"
      cp -p "${DATA}/sfcf${ihr_3d}.tile${itile}.nc" "${COMINOUT}/${NET}.${cycle}.sfc.f${ihr_3d}.c${RES}.tile${itile}.nc"
    done
  done

#########
# DATM
#########
elif [ "${atm_model}" = "datm" ]; then
  # Restart file
  cp -p "DATM_${datm_data_type_upper}.datm.r.${nYYYY}-${nMM}-${nDD}-${nHHsec_5d}.nc" "${COMINOUT}/RESTART"
fi

#########
# MOM6
#########
if [ "${ocn_model}" = "mom6" ]; then
  # time-averaged => output time line is different
  cp -rp "${DATA}/MOM6_OUTPUT" ${COMINOUT}
  out_start_mom6=$(( OUTPUT_FH_MOM6 / 2 ))
  list_out_fh_mom6=$(seq ${out_start_mom6} ${OUTPUT_FH_MOM6} ${FCST_HRS})
  for ihr in ${list_out_fh_mom6}
  do
    idate=$($NDATE ${ihr} $PDY$cyc)
    iyyyy=${idate:0:4}
    imm=${idate:4:2}
    idd=${idate:6:2}
    ihh=${idate:8:2}
    ihr_3d=$(printf "%03d" "${ihr}")
    cp -p "${DATA}/MOM6_OUTPUT/ocn_${iyyyy}_${imm}_${idd}_${ihh}.nc" "${COMINOUT}/${NET}.${cycle}.ocn.f${ihr_3d}.c${RES}.nc"
  done
fi

#########
# CICE
#########
if [ "${ice_model}" = "cice6" ]; then
  # time-averaged if hist_avg = true in ice_in
  # output frequency: output time is not based on forecast hours but based on wall-clock hour
  cp -rp "${DATA}/history" ${COMINOUT}
  output_fh_cice_2d=$(printf "%02d" "${OUTPUT_FH_CICE}")
  fdate_fcst=$($NDATE ${FCST_HRS} ${PDY}${cyc})
  idate="${PDY}00"
  ihr="0"
  icnt="0"
  while [ "${idate}" -le "${fdate_fcst}" ]; do
    if (( "${idate}" > "${PDY}${cyc}" )); then
      iyyyy=${idate:0:4}
      imm=${idate:4:2}
      idd=${idate:6:2}
      ihh=${idate:8:2}
      ihh_nz="${ihh#0}"
      if (( "${icnt}" == 0 )); then
        ihr0=$(( cyc - ihh_nz ))
        ihr=$(( ihr + ihr0 ))
        icnt=$(( icnt + 1 ))
      fi
      ihh_sec=$(( ihh_nz * 3600 ))
      ihh_sec_5d=$(printf "%05d" "${ihh_sec}")
      ihr=$(( ihr + OUTPUT_FH_CICE ))
      ihr_3d=$(printf "%03d" "${ihr}")
      cp -p "${DATA}/history/iceh_${output_fh_cice_2d}h.${iyyyy}-${imm}-${idd}-${ihh_sec_5d}.nc" "${COMINOUT}/${NET}.${cycle}.ice.f${ihr_3d}.c${RES}.nc"
    fi
    idate=$($NDATE ${OUTPUT_FH_CICE} ${idate})
  done
fi

########
# WW3
########
if [ "${wav_model}" = "ww3" ]; then
  list_out_fh_ww3=$(seq ${OUTPUT_FH_WW3} ${OUTPUT_FH_WW3} ${FCST_HRS})
  for ihr in ${list_out_fh_ww3}
  do
    idate=$($NDATE ${ihr} $PDY$cyc)
    ipdy=${idate:0:8}
    ihh=${idate:8:2}
    ihr_3d=$(printf "%03d" "${ihr}")
    cp -p "${DATA}/${ipdy}.${ihh}0000.out_grd.ww3" "${COMINOUT}/${NET}.${cycle}.wav_grd.f${ihr_3d}.c${RES}.ww3"
    cp -p "${DATA}/${ipdy}.${ihh}0000.out_pnt.ww3.nc" "${COMINOUT}/${NET}.${cycle}.wav.f${ihr_3d}.c${RES}.nc"
  done
  if [ "${APP}" != "S2SWAL" ]; then
    rsync -av --update --no-links out.pnt_wght.ww3.nc ${COMINOUT}
  fi
  rsync -av --update --no-links ${DATA}/ufs.cpld.ww3.r.* ${COMINOUT}
fi

###########
# GOCART
###########
if [ "${chm_model}" = "gocart" ]; then
  # Copy GOCART output to COMINOUT
  read -ra out_fh <<< "${OUTPUT_FH}"
  out_fh1="${out_fh[0]}"
  out_fh2="${out_fh[1]}"
  if [ "${out_fh2}" = "-1" ]; then
    list_out_fh=$(seq ${out_fh1} ${out_fh1} ${FCST_HRS})
  else
    list_out_fh=${OUTPUT_FH}
  fi
  for ihr in ${list_out_fh}
  do
    idate=$($NDATE ${ihr} $PDY$cyc)
    ipdy=${idate:0:8}
    ihh=${idate:8:2}
    ihr_3d=$(printf "%03d" "${ihr}")
    cp -p "${DATA}/gocart.inst_aod.${ipdy}_${ihh}00z.nc4" "${COMINOUT}/${NET}.${cycle}.aod.f${ihr_3d}.c${RES}.nc"
  done  
fi

############
# Noah-MP
############
if [ "${lnd_model}" = "noahmp" ]; then
  # Copy LND output to COMINOUT/RESTART
  rsync -av --update --no-links ${DATA}/ufs.cpld.lnd.out.* ${COMINOUTrestart}

  # Copy LND output to COMINOUT
  ## ufs.cpld.lnd.ini
  for itile in {1..6};
  do
    cp -p "${DATA}/ufs.cpld.lnd.ini.${YYYY}-${MM}-${DD}-${HHsec_5d}.tile${itile}.nc" "${COMINOUT}/${NET}.${cycle}.lnd.f000.c${RES}.tile${itile}.nc"
  done
  ## ufs.cpld.lnd.out
  list_out_fh_lnd=$(seq ${OUTPUT_FH_LND} ${OUTPUT_FH_LND} ${FCST_HRS})
  for ihr in ${list_out_fh_lnd}
  do
    idate=$($NDATE ${ihr} $PDY$cyc)
    iyyyy=${idate:0:4}
    imm=${idate:4:2}
    idd=${idate:6:2}
    ihh=${idate:8:2}
    ihh_nz="${ihh#0}"
    if (( "${icnt}" == 0 )); then
      ihr0=$(( cyc - ihh_nz ))
      ihr=$(( ihr + ihr0 ))
      icnt=$(( icnt + 1 ))
    fi
    ihh_sec=$(( ihh_nz * 3600 ))
    ihh_sec_5d=$(printf "%05d" "${ihh_sec}")
    ihr_3d=$(printf "%03d" "${ihr}")
    for itile in {1..6};
    do
      cp -p "${DATA}/ufs.cpld.lnd.out.${iyyyy}-${imm}-${idd}-${ihh_sec_5d}.tile${itile}.nc" "${COMINOUT}/${NET}.${cycle}.lnd.f${ihr_3d}.c${RES}.tile${itile}.nc"
    done
  done
fi

######################
# RESTART directory
######################
# Copy only newer files and exclude all symlinks
rsync -av --update --no-links ${DATA}/RESTART/ ${COMINOUTrestart}

###################################################################
# Set soft-links to DATA_RESTART to trigger next tasks in Rocoto
###################################################################
# sfc_data
if [ "${atm_model}" = "fv3" ]; then
  if [ "${DO_FREE_FORECAST}" = "first" ]; then
    ln -nsf ${COMINOUTrestart}/*.sfc_data.tile*.nc ${DATA_RESTART}
  else
    for itile in {1..6};
    do
      ln -nsf "${COMINOUTrestart}/${nYYYY}${nMM}${nDD}.${nHH}0000.sfc_data.tile${itile}.nc" ${DATA_RESTART}/.
    done
  fi
fi
if [ "${ocn_model}" = "mom6" ]; then
  if [ "${DO_FREE_FORECAST}" = "first" ]; then
    ln -nsf ${COMINOUTrestart}/*.MOM.res.nc ${DATA_RESTART}
  else
    ln -nsf "${COMINOUTrestart}/${nYYYY}${nMM}${nDD}.${nHH}0000.MOM.res.nc" ${DATA_RESTART}/.
  fi
fi

