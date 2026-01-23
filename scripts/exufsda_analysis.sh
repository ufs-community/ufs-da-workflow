#!/usr/bin/env bash

set -xue

ulimit -s unlimited; ulimit -a;

# Set other dates
YYYY=${PDY:0:4}
MM=${PDY:4:2}
DD=${PDY:6:2}
HH=${cyc}

next_date=$($NDATE ${DATE_CYCLE_FREQ_HR} $PDY$cyc)
PDYpc1=${next_date:0:8}
nHH=${next_date:8:2}

pdate=$($NDATE -${DATE_CYCLE_FREQ_HR} $PDY$cyc)
YYYYp=${pdate:0:4}
MMp=${pdate:4:2}
DDp=${pdate:6:2}
HHp=${pdate:8:2}
PDYmc1=${pdate:0:8}
COMINrestart_mc1="${COMROOT}/${NET}/${model_ver}/${RUN}.${PDYmc1}/RESTART"

filedate="${PDY}.${cyc}0000"
filedate_next="${PDYpc1}.${nHH}0000"

# Global parameters
orog_path="${FIXufsda}/DATA_fix/FV3/Tiled/C${RES}"
orog_fn_base="C${RES}.${OCN_MESH_RES}_oro_data"
fn_ice_data=""
fn_ice_incr=""
fn_ocn_data=""
fn_ocn_incr=""
fn_sfc_data=""
fn_sfc_incr=""
if [ "${FRAC_GRID}" = "YES" ]; then
  snowdepth_vn="snodl"
else
  snowdepth_vn="snwdph"
fi

###########################################################################
# Atmospheric DA analysis (FV3-JEDI)
###########################################################################
if [ "${JEDI_TYPE_FV3}" = "YES" ] && [ "${TYPE_ANAL_FCST}" != "ctest" ]; then
  mkdir -p anl
  mkdir -p bc
  mkdir -p berror
  mkdir -p bkg
  mkdir -p crtm
  mkdir -p diag
  mkdir -p obs

  # Background (restart) files
  if [ "${COLDSTART}" = "NO" ] && [ "${PDY}${cyc}" = "${DATE_FIRST_CYCLE:0:10}" ]; then
    data_dir="${WARMSTART_DIR}"
  else
    data_dir="${COMINrestart_mc1}"
  fi


  # Copy static data files
  cp -p ${FIXufsda}/DATA_jedi/fv3files/fmsmpp.nml ${DATA}/fv3jedi/.
  cp -p ${FIXufsda}/DATA_jedi/fv3files/field_table_ufs ${DATA}/fv3jedi/field_table
  cp -p ${FIXufsda}/DATA_jedi/fv3files/akbk${NPZ}.nc4 ${DATA}/fv3jedi/akbk.nc4

  # CRTM files
  ln -nsf ${FIXufsda}/DATA_crtm/* ${DATA}/crtm/.

  # Observation files
  obs_prefix="obs.${PDY}.${cycle}"  
  ## ascatw_ascat_metop-b
  ln -nsf "${COMINOUTobs}/${obs_prefix}.scatwnd.ascat_metop-b.nc" "${DATA}/obs"
  ## ATMS N20
  ln -nsf "${COMINOUTobs}/${obs_prefix}.atms_n20.nc" "${DATA}/obs"
  ln -nsf "${COMINOUTobs}/${obs_prefix}.atms_n20.satbias.nc" "${DATA}/obs"
  ln -nsf "${COMINOUTobs}/${obs_prefix}.atms_n20.satbias_cov.nc" "${DATA}/obs"
  ln -nsf "${COMINOUTobs}/${obs_prefix}.atms_n20.tlapse.txt" "${DATA}/obs"
  ## surface_ps
  ln -nsf "${COMINOUTobs}/${obs_prefix}.conventional_ps.nc" "${DATA}/obs"
  ## gnssrobndnbam_cosmic2
  ln -nsf "${COMINOUTobs}/${obs_prefix}.gnssro_cosmic2.nc" "${DATA}/obs"
  ## ompsnp_npp
  ln -nsf "${COMINOUTobs}/${obs_prefix}.ozone.ompsnp_npp.nc" "${DATA}/obs"
  ## ompstc_npp
  ln -nsf "${COMINOUTobs}/${obs_prefix}.ozone.ompstc_npp.nc" "${DATA}/obs"
  ## satwind_goes-16
  ln -nsf "${COMINOUTobs}/${obs_prefix}.satwnd.abi_goes-16.nc" "${DATA}/obs"

  # Set JEDI executable
  if [ "${JEDI_ALGORITHM}" = "3dvar" ]; then
    jedi_exe_fn="fv3jedi_var.x"
  else
    jedi_exe_fn="fv3jedi_${JEDI_ALGORITHM}.x"
  fi

  # Copy JEDI input yaml file
  jedi_nml_fn="jedi_${JEDI_ALGORITHM}_fv3_${PDY}${cyc}.yaml"
  if [ "${CUSTOM_JEDI_CONFIG_FLAG}" = "YES" ]; then
    cp -p "${CUSTOM_JEDI_CONFIG_PATH}/${CUSTOM_JEDI_CONFIG_PREFIX}_${PDY}${cyc}.yaml" ${jedi_nml_fn}
  else
    cp -p "${COMINOUT}/${jedi_nml_fn}" .
  fi

  # Run JEDI executable
  export pgm="${jedi_exe_fn}"
  . prep_step
  ${RUN_CMD} -n ${NPROCS_ANALYSIS} ${JEDI_BIN_PATH}/$pgm ${jedi_nml_fn} >>$pgmout 2>errfile
  export err=$?; err_chk
  cp errfile errfile_fv3jedi_x
  if [[ $err != 0 ]]; then
    err_exit "JEDI DA failed"
  fi



fi


###########################################################################
# SOCA analysis
###########################################################################
if [ "${JEDI_TYPE_SOCA}" = "YES" ] && [ "${TYPE_ANAL_FCST}" != "ctest" ]; then

  mkdir -p INPUT
  mkdir -p MOM6_OUTPUT
  mkdir -p obs
  mkdir -p diag
  fn_ocn_data="MOM.res.nc"
  bkg_data_fn_suffix="_soca_before_inc"
  new_bkg_data_fn_suffix="_soca_after_inc"

  # Restart file
  if [ "${COLDSTART}" = "NO" ] && [ "${PDY}${cyc}" = "${DATE_FIRST_CYCLE:0:10}" ]; then
    data_dir="${WARMSTART_DIR}"
  else
    data_dir="${COMINrestart_mc1}"
  fi
  r_fp="${data_dir}/${filedate}.MOM.res.nc"
  if [ -e "${r_fp}" ]; then
    cp -p "${r_fp}" MOM.res.nc
    cp -p MOM.res.nc ${fn_ocn_data}${bkg_data_fn_suffix}
  else
    err_exit "Copy failed: ${r_fp} file does not exist."
  fi

  # SOCA gridspec file
  soca_gridspec_fn="soca_gridspec_${MOM6_NIGLOBAL}x${MOM6_NJGLOBAL}x${MOM6_NK}.nc"
  ln -nsf "${COMINOUT}/${soca_gridspec_fn}" soca_gridspec.nc

  # MOM6-solo input.nml
  settings="\
  'yyyy': !!str ${YYYY}
  'mm': !!str ${MM}
  'dd': !!str ${DD}
  'hh': !!str ${HH}
  'mom_input_filename': "r"
" # End of settings variable
  fn_template="template.SOCA.input.nml"
  fp_template="${PARMufsda}/jedi/soca/${fn_template}"
  fn_namelist="input.nml"
  ${USHufsda}/fill_jinja_template.py -u "${settings}" -t "${fp_template}" -o "${fn_namelist}"

  # MOM_input
  cp -p "${COMINOUT}/MOM_input_${PDY}${cyc}" INPUT/MOM_input

  # Fileds metadata files
  cp -p "${PARMufsda}/jedi/fieldmetadata/fv3jedi_fieldmetadata_soca.yaml" "fields_metadata.yaml"

  # Diffusion parameter files
  soca_diff_cor_hz1_fn="diffusion_cor1_hz_rossby"
  soca_diff_cor_hz2_fn="diffusion_cor1_hz_600km"
  soca_diff_cor_vt_fn="diffusion_cor1_vt_6lvls"
  ln -nsf "${COMINOUT}/${soca_diff_cor_hz1_fn}_${PDY}${cyc}.nc" ${soca_diff_cor_hz1_fn}.nc
  ln -nsf "${COMINOUT}/${soca_diff_cor_hz2_fn}_${PDY}${cyc}.nc" ${soca_diff_cor_hz2_fn}.nc
  ln -nsf "${COMINOUT}/${soca_diff_cor_vt_fn}_${PDY}${cyc}.nc" ${soca_diff_cor_vt_fn}.nc

  # godas sst file
  cp -p "${FIXufsda}/DATA_fix/MOM6/godas_sst_bgerr.nc" .

  # Observation alias file
  cp -p "${PARMufsda}/jedi/soca/obsop_name_map.yaml" .

  # Observation files
  ln -nsf "${FIXufsda}/DATA_obs/soca/adt_ssh_${PDY}${cyc}.nc" obs/adt_ssh.nc
  ln -nsf "${FIXufsda}/DATA_obs/soca/prof_insitu_${PDY}${cyc}.nc" obs/prof_insitu.nc
  ln -nsf "${FIXufsda}/DATA_obs/soca/sss_salinity_${PDY}${cyc}.nc" obs/sss_salinity.nc
  ln -nsf "${FIXufsda}/DATA_obs/soca/sst_satellite_${PDY}${cyc}.nc" obs/sst_satellite.nc

  # Set JEDI executable
  if [ "${JEDI_ALGORITHM}" = "3dvar" ]; then
    jedi_exe_fn="soca_var.x"
  else
    jedi_exe_fn="soca_${JEDI_ALGORITHM}.x"
  fi

  # Copy JEDI input yaml file
  jedi_nml_fn="jedi_${JEDI_ALGORITHM}_soca_${PDY}${cyc}.yaml"
  if [ "${CUSTOM_JEDI_CONFIG_FLAG}" = "YES" ]; then
    cp -p "${CUSTOM_JEDI_CONFIG_PATH}/${CUSTOM_JEDI_CONFIG_PREFIX}_${PDY}${cyc}.yaml" ${jedi_nml_fn}
  else
    cp -p "${COMINOUT}/${jedi_nml_fn}" .
  fi

  # Run JEDI executable
  export pgm="${jedi_exe_fn}"
  . prep_step
  ${RUN_CMD} -n ${NPROCS_ANALYSIS} ${JEDI_BIN_PATH}/$pgm ${jedi_nml_fn} >>$pgmout 2>errfile
  export err=$?; err_chk
  cp errfile errfile_fv3jedi_x
  if [[ $err != 0 ]]; then
    err_exit "JEDI DA failed"
  fi

  # Copy JEDI output file to COMINOUT
  fn_ocn_out="ocn.${JEDI_ALGORITHM}.an.${YYYY}-${MM}-${DD}T${HH}:00:00Z.nc"
  cp -p ${fn_ocn_out} ${COMINOUT}

  ## Replace variables of background files with those of JEDI output files
  cat > bkg_var_replace.yaml << EOF
bkg_data_fn_suffix: '${bkg_data_fn_suffix}'
fn_data_base: '${fn_ocn_data}'
jedi_out_fn_prefix: '${fn_ocn_out}'
jedi_out_fn_suffix: ''
JEDI_TYPE_SOCA: '${JEDI_TYPE_SOCA}'
new_bkg_data_fn_suffix: '${new_bkg_data_fn_suffix}'
num_tiles: 0
PY_LOG_LEVEL: '${PY_LOG_LEVEL}'
work_dir: '${DATA}'
EOF
  ${USHufsda}/bkg_var_replace.py
  if [ $? -ne 0 ]; then
    err_exit "Background varriable replacement failed"
  fi

  # Copy observation files to COMINOUTobs
  obs_fns=( "adt_ssh" "prof_insitu" "sss_salinity" "sst_satellite" )
  for ifn in "${obs_fns[@]}" ; do
    ifp="${DATA}/obs/${ifn}.nc"
    if [ -e "${ifp}" ]; then
      cp -p ${ifp} "${COMINOUTobs}/obs.${PDY}.${cycle}.${ifn}.nc"
    fi
  done

  # Copy H(x) output to COMINOUThofx
  cp -p diag/* ${COMINOUThofx}

  # Copy output to COMINOUT
  if [ "${TYPE_ANAL_FCST}" = "anal-only" ]; then
    cominout_dir="${COMINOUTrestart}"
    out_fdate="${filedate_next}"
  else
    cominout_dir="${COMINOUT}"
    out_fdate="${filedate}"
  fi
  cp -p "${fn_ocn_data}${new_bkg_data_fn_suffix}" "${cominout_dir}/${out_fdate}.${fn_ocn_data}"

fi


###########################################################################
# Snow / Soil-moisture DA analysis
###########################################################################
if [ -n "${list_jedi_land}" ] && [ "${TYPE_ANAL_FCST}" != "ctest" ]; then
  # Copy sfc_data files from RESTART/WARMSTART into work directory
  for itile in {1..6}
  do
    sfc_fn="${filedate}.sfc_data.tile${itile}.nc"
    if [ -f ${COMINrestart_mc1}/${sfc_fn} ]; then
      cp -p ${COMINrestart_mc1}/${sfc_fn} .
    elif [ -f ${WARMSTART_DIR}/${sfc_fn} ]; then
      cp -p ${WARMSTART_DIR}/${sfc_fn} .
    else
      err_exit "Initial sfc_data files do not exist"
    fi
    ## copy sfc_data file for comparison
    cp -p ${sfc_fn} "${sfc_fn}_ini"
  done
  
  # Copy obserbation files to work directory
  mkdir -p ${DATA}/obs
  obs_prefix="obs.${PDY}.${cycle}"
  if [ "${OBS_SNOW_GHCN}" = "YES" ]; then
    ln -nsf "${COMINOUTobs}/${obs_prefix}.ghcn_snow.nc" "${DATA}/obs"
  fi
  if [ "${OBS_SNOW_IMS}" = "YES" ]; then
    ln -nsf "${COMINOUTobs}/${obs_prefix}.ims_snow.tm00.nc" "${DATA}/obs"
  fi
  if [ "${OBS_SNOW_SFCSNO}" = "YES" ]; then
    ln -nsf "${COMINOUTobs}/${obs_prefix}.sfcsno.tm00.bufr_d" "${DATA}/obs"
    ln -nsf "${PARMufsda}/jedi/bufr_sfcsno_mapping.yaml" "${DATA}/obs"
  fi
  if [ "${OBS_SWC_SMAP}" = "YES" ]; then
    ln -nsf "${COMINOUTobs}/${obs_prefix}.smap_combined.nc" "${DATA}/obs"
  fi
  if [ "${OBS_SWC_SMOPS}" = "YES" ]; then
    ln -nsf "${COMINOUTobs}/${obs_prefix}.smops.nc" "${DATA}/obs"
  fi
  
  # Update coupler.res file
  settings="\
  'yyyp': !!str ${YYYYp}
  'mp': !!str ${MMp}
  'dp': !!str ${DDp}
  'hp': !!str ${HHp}
  'yyyy': !!str ${YYYY}
  'mm': !!str ${MM}
  'dd': !!str ${DD}
  'hh': !!str ${HH}
" # End of settings variable

  fp_template="${PARMufsda}/templates/template.coupler.res"
  fn_namelist="${DATA}/${filedate}.coupler.res"
  ${USHufsda}/fill_jinja_template.py -u "${settings}" -t "${fp_template}" -o "${fn_namelist}"
  
  # Copy static data files
  mkdir -p ${DATA}/Data/fv3files
  cp -p ${FIXufsda}/DATA_jedi/fv3files/fmsmpp.nml ${DATA}/Data/fv3files/.
  cp -p ${FIXufsda}/DATA_jedi/fv3files/field_table_ufs ${DATA}/Data/fv3files/field_table
  cp -p ${FIXufsda}/DATA_jedi/fv3files/akbk${NPZ}.nc4 ${DATA}/Data/fv3files/akbk.nc4
  
  ln -nsf ${orog_path}/${orog_fn_base}.tile* .
  
  # Link snow shadow level nicas data file
  mkdir -p ${DATA}/berror
  ln -nsf ${FIXufsda}/DATA_fix/JEDI/snow_bump_nicas_250km_shadowlevels_nicas.nc ${DATA}/berror/.
  
  # Run JEDI Analyses
  list_jedi_types=(${list_jedi_land})
  echo "List of JEDI analyses for land: ${list_jedi_types[@]}"
  for jedi_type in "${list_jedi_types[@]}"; do
    echo "JEDI analysis for ${jedi_type}"
    # Intermediate/Output directories
    dir_list=("${DATA}/diags" "${DATA}/anl" "${DATA}/bkg" "${DATA}/test")
    for dir in "${dir_list[@]}"; do
      if [ -d "${dir}" ]; then
        echo "Removing existing directory: $dir"
        rm -rf $dir
      fi
      echo "Creating directory: $dir"
      mkdir -p $dir
    done
  
    # Set up background
    if [ "${JEDI_ALGORITHM}" = "3dvar" ]; then
      for itile in {1..6}
      do
        sfc_fn="${filedate}.sfc_data.tile${itile}.nc"
        sfc_bkg_fn="${filedate}.sfc_data.tile${itile}.nc"
        cp -p ${sfc_fn} "${DATA}/bkg/${sfc_bkg_fn}"
        ln -nsf "${orog_path}/${orog_fn_base}.tile${itile}.nc" "${DATA}/bkg/."
      done
      cp -p ${filedate}.coupler.res ${DATA}/bkg
  
      # Set JEDI executable
      jedi_exe_fn="fv3jedi_var.x"
  
    elif [ "${JEDI_ALGORITHM}" = "letkf-oi" ]; then
      if [ "${jedi_type}" = "snow" ]; then
        for ens in {1..2}
        do
          mkdir -p $DATA/mem${ens}
          cp -p ${filedate}.sfc_data.tile*.nc ${DATA}/mem${ens}
          cp -p ${filedate}.coupler.res ${DATA}/mem${ens}
          ln -nsf ${orog_path}/${orog_fn_base}.tile*.nc ${DATA}/mem${ens}
        done
  
        ${USHufsda}/letkf_create_ens.py $filedate $snowdepth_vn 30
        if [[ $? != 0 ]]; then
          err_exit "letkf-oi create failed"
        fi
      else
        ln -nsf ${orog_path}/${orog_fn_base}.tile*.nc ${DATA}
      fi
      # Set JEDI executable
      jedi_exe_fn="fv3jedi_letkf.x"
    fi
  
    # JEDI field metadata file
    if [ "${jedi_type}" = "snow" ]; then
      if [ "${FRAC_GRID}" = "YES" ]; then
        fn_fmeta_template="fv3jedi_fieldmetadata_restart_${jedi_type}.yaml"
      else
        fn_fmeta_template="fv3jedi_fieldmetadata_restart_${jedi_type}_nofrac.yaml"
      fi
    elif [ "${jedi_type}" = "soil_moisture" ]; then
      fn_fmeta_template="fv3jedi_fieldmetadata_restart_${jedi_type}.yaml"
    fi
    fn_fmeta="fv3jedi_fieldmetadata_restart.yaml"
    cp -p "${PARMufsda}/jedi/fieldmetadata/${fn_fmeta_template}" ${fn_fmeta}
  
    # Copy JEDI input yaml file
    jedi_nml_fn="jedi_${JEDI_ALGORITHM}_${jedi_type}_${PDY}${cyc}.yaml"
    if [ "${CUSTOM_JEDI_CONFIG_FLAG}" = "YES" ]; then
      cp -p "${CUSTOM_JEDI_CONFIG_PATH}/${CUSTOM_JEDI_CONFIG_PREFIX}_${PDY}${cyc}.yaml" ${jedi_nml_fn}
    else
      cp -p "${COMINOUT}/${jedi_nml_fn}" .
    fi
  
    export pgm="${jedi_exe_fn}"
    . prep_step
    ${RUN_CMD} -n ${NPROCS_ANALYSIS} ${JEDI_BIN_PATH}/$pgm ${jedi_nml_fn} >>$pgmout 2>errfile
    export err=$?; err_chk
    cp errfile errfile_fv3jedi_x
    if [[ $err != 0 ]]; then
      err_exit "JEDI DA failed"
    fi
  
    # save intermediate sfc_data files before applying increment
    for itile in {1..6}
    do
      sfc_fn="${filedate}.sfc_data.tile${itile}.nc"
      cp -p ${sfc_fn} "${sfc_fn}_${jedi_type}_before_inc"
    done
  
    # Apply snow increment to UFS sfc_data files
    if [ "${jedi_type}" = "snow" ]; then
      ## Link inc file to DATA
      if [ "${JEDI_ALGORITHM}" = "3dvar" ]; then
        inc_fp_prefix="${DATA}/anl/snowinc.${filedate}.sfc_data"
      elif [ "${JEDI_ALGORITHM}" = "letkf-oi" ]; then
        inc_fp_prefix="${DATA}/${filedate}.snowinc.sfc_data"
      fi
      inc_fn_prefix="snowinc.${filedate}.sfc_data"
      for itile in {1..6}
      do
        cp -p "${inc_fp_prefix}.tile${itile}.nc" "${DATA}/${inc_fn_prefix}.tile${itile}.nc"
      done
  
      if [ "${FRAC_GRID}" = "YES" ]; then
        frac_grid=".true."
      else
        frac_grid=".false."
      fi
  
      cat << EOF > apply_incr_nml
&noahmp_snow
 date_str = "${YYYY}${MM}${DD}",
 hour_str = "${HH}",
 res = ${RES},
 frac_grid = ${frac_grid},
 rst_path = "${DATA}",
 inc_path = "${DATA}",
 orog_path = "${orog_path}",
 otype = "${orog_fn_base}"
/
EOF

      export pgm="apply_incr.exe"
      . prep_step
      ## (n=6): this is fixed, at one task per tile (with minor code change). 
      ${RUN_CMD} -n 6 ${EXECufsda}/$pgm >>$pgmout 2>errfile
      export err=$?; err_chk
      cp errfile errfile_apply_incr
      if [[ $err != 0 ]]; then
        err_exit "apply snow increment failed"
      fi
  
      ## Save intermediate sfc_data files after applying increment
      for itile in {1..6}
      do
        sfc_fn="${filedate}.sfc_data.tile${itile}.nc"
        cp -p ${sfc_fn} "${sfc_fn}_${jedi_type}_after_inc"
      done
  
    elif [ "${jedi_type}" = "soil_moisture" ]; then
      ## Link inc file to DATA
      if [ "${JEDI_ALGORITHM}" = "3dvar" ]; then
        inc_fp_prefix="${DATA}/anl/smcinc.${filedate}.sfc_data"
      elif [ "${JEDI_ALGORITHM}" = "letkf-oi" ]; then
        inc_fp_prefix="${DATA}/${filedate}.smcinc.sfc_data"
      fi
      inc_fn_prefix="smcinc.${filedate}.sfc_data"
      for itile in {1..6}
      do
        cp -p "${inc_fp_prefix}.tile${itile}.nc" "${DATA}/${inc_fn_prefix}.tile${itile}.nc"
      done
  
      ## Replace smc of sfc_data with that of JEDI output files
      bkg_data_fn_suffix=".nc_${jedi_type}_before_inc"
      fn_data_base="${filedate}.sfc_data.tile"
      jedi_out_fn_prefix="jedi_smc."
      jedi_out_fn_suffix=".nc"
      new_bkg_data_fn_suffix=".nc_${jedi_type}_replaced"
      cat > bkg_var_replace.yaml << EOF
bkg_data_fn_suffix: '${bkg_data_fn_suffix}'
fn_data_base: '${fn_data_base}'
jedi_out_fn_prefix: '${jedi_out_fn_prefix}'
jedi_out_fn_suffix: '${jedi_out_fn_suffix}'
JEDI_TYPE_SOCA: '${JEDI_TYPE_SOCA}'
new_bkg_data_fn_suffix: '${new_bkg_data_fn_suffix}'
num_tiles: 6
PY_LOG_LEVEL: '${PY_LOG_LEVEL}'
work_dir: '${DATA}'
EOF
      ${USHufsda}/bkg_var_replace.py
      if [ $? -ne 0 ]; then
        err_exit "sfc_data var replacement failed"
      fi
  
      ## Save intermediate sfc_data files after applying increment
      for itile in {1..6}
      do
        sfc_fn="${fn_data_base}${itile}.nc"
        cp -p "${fn_data_base}${itile}${new_bkg_data_fn_suffix}" ${sfc_fn}
        cp -p ${sfc_fn} "${fn_data_base}${itile}.nc_${jedi_type}_after_inc"
      done
  
    fi
  
    # Copy the increment files to COMINOUT
    for itile in {1..6}
    do
      cp -p "${DATA}/${inc_fn_prefix}.tile${itile}.nc" ${COMINOUT}
    done  
  done
  
  ## Copy the final sfc_data files to COMINOUT / COMINOUTrestart
  if [ "${TYPE_ANAL_FCST}" = "anal-only" ]; then
    cominout_dir="${COMINOUTrestart}"
    out_fdate="${filedate_next}"
  else
    cominout_dir="${COMINOUT}"
    out_fdate="${filedate}"
  fi
  for itile in {1..6}
  do
    cp -p "${DATA}/${filedate}.sfc_data.tile${itile}.nc" "${cominout_dir}/${out_fdate}.sfc_data.tile${itile}.nc"
  done
  
  if [ -d diags ]; then
    cp -p diags/* ${COMINOUThofx}
    ln -nsf ${COMINOUThofx}/*.nc ${DATA_HOFX}
  fi

  ## Set file names for plotting
  fn_sfc_data="${filedate}.sfc_data.tile"
  fn_sfc_incr="${inc_fn_prefix}.tile"
fi


###########################################################################
# C-test of JEDI model component
###########################################################################
if [ "${TYPE_ANAL_FCST}" = "ctest" ]; then
  #########
  # SOCA
  #########
  if [ "${JEDI_TYPE_SOCA}" = "YES" ]; then
    ## Path to data set
    if [ "${JEDI_BUNDLE_GDAS}" = "gdas" ]; then
      path_soca_data="${JEDI_BIN_PATH}/../../sorc/soca/test"
    else
      path_soca_data="${JEDI_BIN_PATH}/../../jedi-bundle/soca/test"
    fi
    mkdir -p data_output
    mkdir -p testoutput
    mkdir -p data_generated

    ## Symlink data/input directories
    ln -nsf "${path_soca_data}/Data" "data_static"
    ln -nsf "${path_soca_data}/testinput" .
    ln -nsf "${path_soca_data}/testref" .

    ## Symlink data files for gridgen
    ln -nsf "data_static/workdir/diag_table" .
    ln -nsf "data_static/workdir/field_table" .

    ##################################################################
    ## Run "JEDI_ALGORITHM" and its pre-requisite tasks in sequence
    ##################################################################
    ## Set list of tasks and executable name for jedi c-test
    if [ "${JEDI_CTEST_NAME}" = "3dvar" ]; then
      list_soca_tasks=("gridgen" "setcorscales" "parameters_diffusion" "${JEDI_CTEST_NAME}")
      jedi_exe_soca_fn="soca_var.x"
    elif [ "${JEDI_CTEST_NAME}" = "3dvarfgat_pseudo" ]; then
      list_soca_tasks=("gridgen" "setcorscales" "parameters_diffusion" \
	               "forecast_mom6" "${JEDI_CTEST_NAME}")
      jedi_exe_soca_fn="soca_var.x"
    else
      list_soca_tasks=("${JEDI_CTEST_NAME}")
      jedi_exe_soca_fn="soca_${JEDI_ALGORITHM}.x"
    fi

    for isoca in "${list_soca_tasks[@]}"; do
      ### JEDI input yaml file
      jedi_nml_fn="${isoca}.yml"
      cp -p "${path_soca_data}/testinput/${jedi_nml_fn}" .
 
      ### Run JEDI executable
      if [ "${isoca}" = "forecast_mom6" ]; then
        export BIN_DIR="${JEDI_BIN_PATH}"
        export MPIEXE="${RUUN_CMD}"
        # To avoid file replacement
        [[ -e "input.nml" ]] && rm input.nml
        py_exe_path="${JEDI_BIN_PATH}/../../jedi-bundle/soca/test"
        ${py_exe_path}/mom6solo.py ${jedi_nml_fn}
        if [ $? -ne 0 ]; then
          err_exit "SOCA c-test FORECAST_MOM6 failed"
        fi
        [[ -e "input.nml" ]] && rm input.nml
      else
        if [ "${isoca}" = "${JEDI_CTEST_NAME}" ]; then
          jedi_exe_fn="${jedi_exe_soca_fn}"
        elif [ "${isoca}" = "parameters_diffusion" ]; then
          jedi_exe_fn="soca_error_covariance_toolbox.x"
        else
          jedi_exe_fn="soca_${isoca}.x"
        fi
        export pgm="${jedi_exe_fn}"
        . prep_step
        ${RUN_CMD} -n ${NPROCS_ANALYSIS} ${JEDI_BIN_PATH}/$pgm ${jedi_nml_fn} >>$pgmout 2>errfile
        export err=$?; err_chk
        cp errfile errfile_ctest_${isoca}
        if [[ $err != 0 ]]; then
          err_exit "JEDI SOCA C-test for ${isoca} failed"
        fi
      fi
      ### Copy output files
      mkdir -p "data_generated/${isoca}"
      cp -p data_output/* "data_generated/${isoca}"
      
      echo "========== SOCA task ${isoca} completed !!! =========="
    done

    # Copy observation files to COMINOUTobs
    obs_fns=( "sst" "sss" "adt" "prof" "icec" )
    for ifn in "${obs_fns[@]}" ; do
      ifp="${DATA}/data_static/obs/${ifn}.nc"
      if [ -e "${ifp}" ]; then
        cp -p ${ifp} "${COMINOUTobs}/obs.${PDY}.${cycle}.${ifn}.nc"
      fi
    done
  
    # Copy output to COMINOUT
    cp -rp data_generated/* ${COMINOUT}
    cp -p data_output/* ${COMINOUT}
  
    # Copy H(x) output to COMINOUT
    cp -p data_output/sst.nc "${COMINOUThofx}/diag.SeaSurfaceTemp_${PDY}${cyc}.nc"
    cp -p data_output/sss.nc "${COMINOUThofx}/diag.SeaSurfaceSalinity_${PDY}${cyc}.nc"
    cp -p data_output/adt.nc "${COMINOUThofx}/diag.ADT_${PDY}${cyc}.nc"
    cp -p data_output/prof_T.nc "${COMINOUThofx}/diag.InsituTemperature_${PDY}${cyc}.nc"
    cp -p data_output/prof_S.nc "${COMINOUThofx}/diag.InsituSalinity_${PDY}${cyc}.nc"
  
    # Set and symlink output/increment file names for plotting
    bkg_file_dir="data_static/72x35x25/restarts"
    anl_file_dir="data_output"
  
    fn_ocn_data="MOM.res.nc"
    fn_ocn_incr="MOM.incr.res.nc"
    if [ "${JEDI_CTEST_NAME}" = "3dvarfgat_pseudo" ]; then
      fn_ocn_data_after="ocn.${JEDI_CTEST_NAME}.an.${YYYY}-${MM}-${DD}T12:00:00Z.nc"
      fn_ocn_incr_orig="ocn.cor_rh.incr.${YYYY}-${MM}-${DD}T${HH}:00:00Z.nc"
    else
      fn_ocn_data_after="ocn.${JEDI_CTEST_NAME}.an.${YYYY}-${MM}-${DD}T${HH}:00:00Z.nc"
      fn_ocn_incr_orig="ocn.${JEDI_CTEST_NAME}.iter1.incr.${YYYY}-${MM}-${DD}T${HH}:00:00Z.nc"
    fi
    ln -nsf "${bkg_file_dir}/${fn_ocn_data}" "${fn_ocn_data}_soca_ctest_before_inc"
    ln -nsf "${anl_file_dir}/${fn_ocn_data_after}" "${fn_ocn_data}_soca_ctest_after_inc"
    ln -nsf "${anl_file_dir}/${fn_ocn_incr_orig}" ${fn_ocn_incr}
  
    if [ "${JEDI_CTEST_NAME}" = "3dvar" ]; then
      cp -p data_output/sst_coolskin.nc "${COMINOUThofx}/diag.CoolSkin_${PDY}${cyc}.nc"
      cp -p data_output/icec.nc "${COMINOUThofx}/diag.SeaIceFraction_${PDY}${cyc}.nc"
  
      fn_sfc_data="sfc.res.nc"
      fn_sfc_incr="sfc.incr.res.nc"
      fn_sfc_data_after="sfc.${JEDI_CTEST_NAME}.an.${YYYY}-${MM}-${DD}T${HH}:00:00Z.nc"
      fn_sfc_incr_orig="sfc.${JEDI_CTEST_NAME}.iter1.incr.${YYYY}-${MM}-${DD}T${HH}:00:00Z.nc"
      fn_ice_data="cice.res.nc"
      fn_ice_incr="cice.incr.res.nc"
      fn_ice_data_after="ice.${JEDI_CTEST_NAME}.an.${YYYY}-${MM}-${DD}T${HH}:00:00Z.nc"
      fn_ice_incr_orig="ice.${JEDI_CTEST_NAME}.iter1.incr.${YYYY}-${MM}-${DD}T${HH}:00:00Z.nc"
      ln -nsf "${bkg_file_dir}/${fn_sfc_data}" "${fn_sfc_data}_soca_ctest_before_inc"
      ln -nsf "${anl_file_dir}/${fn_sfc_data_after}" "${fn_sfc_data}_soca_ctest_after_inc"
      ln -nsf "${anl_file_dir}/${fn_sfc_incr_orig}" ${fn_sfc_incr}
      ln -nsf "${bkg_file_dir}/${fn_ice_data}" "${fn_ice_data}_soca_ctest_before_inc"
      ln -nsf "${anl_file_dir}/${fn_ice_data_after}" "${fn_ice_data}_soca_ctest_after_inc"
      ln -nsf "${anl_file_dir}/${fn_ice_incr_orig}" ${fn_ice_incr}
    fi
  fi
  #############
  # FV3-JEDI
  ############
  if [ "${JEDI_TYPE_FV3}" = "YES" ]; then
    ## Path to data set
    path_fv3_data="${JEDI_BIN_PATH}/../../jedi-bundle/fv3-jedi-data/testinput_tier_1"
    path_fv3_test="${JEDI_BIN_PATH}/../../jedi-bundle/fv3-jedi/test"
    ln -nsf "${path_fv3_test}/testinput" .

    mkdir -p ${DATA}/Data
    mkdir -p ${DATA}/Data/analysis
    mkdir -p ${DATA}/Data/bump
    mkdir -p ${DATA}/Data/fv3files
    mkdir -p ${DATA}/Data/hofx
    mkdir -p ${DATA}/Data/obs/testinput_tier_1
    mkdir -p ${DATA}/testoutput

    cd ${DATA}/Data
    ## Symlink data/input directories
    ln -nsf ${path_fv3_test}/Data/fv3files/* ${DATA}/Data/fv3files/.
    ln -nsf "${path_fv3_test}/Data/gsibec" ${DATA}/Data/.
    ln -nsf ${path_fv3_data}/inputs/fv3files/* ${DATA}/Data/fv3files/.
    ln -nsf "${path_fv3_data}/inputs" .
    ln -nsf ${path_fv3_data}/obs/* ${DATA}/Data/obs/testinput_tier_1/.
    cd ${DATA}

    if [ "${JEDI_CTEST_NAME}" = "3dvar_geos_cf" ]; then
      list_ctest_tasks=( "bumpparameters_nicas_geos_cf" "${JEDI_CTEST_NAME}")
      jedi_exe_fv3_fn="fv3jedi_var.x"
    elif [ "${JEDI_CTEST_NAME}" = "3dvar_gfs_0obs" ]; then
      list_ctest_tasks=( "convertstate_gfs" "${JEDI_CTEST_NAME}")
      jedi_exe_fv3_fn="fv3jedi_var.x"
    fi

    for itest in "${list_ctest_tasks[@]}"; do
      ln -nsf "${path_fv3_test}/testoutput/${itest}.ref" ${DATA}/testoutput/.
      ### JEDI input yaml file
      jedi_nml_fn="${itest}.yaml"
      cp -p "${path_fv3_test}/testinput/${jedi_nml_fn}" .

      if [ "${itest}" = "${JEDI_CTEST_NAME}" ]; then
        jedi_exe_fn="${jedi_exe_fv3_fn}"
      elif [ "${itest}" = "convertstate_gfs" ]; then
	jedi_exe_fn="fv3jedi_convertstate.x"
      elif [ "${itest}" = "bumpparameters_nicas_geos_cf" ] || [ "${itest}" = "staticb_cor_aero" ]; then
        jedi_exe_fn="fv3jedi_error_covariance_toolbox.x"
      else
        jedi_exe_fn="fv3jedi_${itest}.x"
      fi
      export pgm="${jedi_exe_fn}"
      . prep_step
      ${RUN_CMD} -n ${NPROCS_ANALYSIS} ${JEDI_BIN_PATH}/$pgm ${jedi_nml_fn} >>$pgmout 2>errfile
      export err=$?; err_chk
      cp errfile errfile_ctest_${itest}
      if [[ $err != 0 ]]; then
        err_exit "JEDI FV3-JEDI C-test for ${itest} failed"
      fi
      echo "========== FV3-JEDI task ${itest} completed !!! =========="
    done

    # Copy output to COMINOUT
    if [ "${JEDI_CTEST_NAME}" = "3dvar_geos_cf" ]; then
      ## observation
      cp -p "${DATA}/Data/obs/testinput_tier_1/tropomi_no2_tropo_2020090318_m.nc4" "${COMINOUTobs}/obs.${PDY}.${cycle}.tropomi_no2.nc"
      ## H(x) result
      cp -p "${DATA}/Data/hofx/tropomi_no2_hofx_geos_2020090318_m.nc" "${COMINOUThofx}/diag.NO2_${PDY}${cyc}.nc"
      ## Analysis result
      cp -p ${DATA}/Data/analysis/* ${COMINOUT}
      ## plot off: no increment file
      DO_PLOT_COMP_JEDI_INCR="NO"
    fi
  fi
fi


###########################################################################
# Comparison plot of background and output by JEDI increment
###########################################################################
DO_PLOT_COMP_JEDI_INCR="${DO_PLOT_COMP_JEDI_INCR:-YES}"
if [ "${DO_PLOT_COMP_JEDI_INCR}" = "YES" ]; then
  out_fn_base_prefix="ufsda_comp_"
  # zlevel_number is valid only for 3-D fields such as stc/smc/slc
  zlevel_number="1"

  cat > plot_analysis_comp_increment.yaml <<EOF
cartopy_ne_path: '${FIXufsda}/NaturalEarth'
fn_ice_data: '${fn_ice_data}'
fn_ice_incr: '${fn_ice_incr}'
fn_ocn_data: '${fn_ocn_data}'
fn_ocn_incr: '${fn_ocn_incr}'
fn_sfc_data: '${fn_sfc_data}'
fn_sfc_incr: '${fn_sfc_incr}'
JEDI_ALGORITHM: '${JEDI_ALGORITHM}'
JEDI_TYPE_SNOW: '${JEDI_TYPE_SNOW}'
JEDI_TYPE_SOCA: '${JEDI_TYPE_SOCA}'
JEDI_TYPE_SOIL_MOISTURE: '${JEDI_TYPE_SOIL_MOISTURE}'
orog_path: '${orog_path}'
orog_fn_base: '${orog_fn_base}'
out_fn_base_prefix: '${out_fn_base_prefix}'
PDY: '${PDY}'
PY_LOG_LEVEL: '${PY_LOG_LEVEL}'
snowdepth_vn: '${snowdepth_vn}'
TYPE_ANAL_FCST: '${TYPE_ANAL_FCST}'
work_dir: '${DATA}'
zlevel_number: '${zlevel_number}'
EOF

  ${USHufsda}/plot_analysis_comp_increment.py
  if [ $? -ne 0 ]; then
    err_exit "JEDI increment comparison plot failed"
  fi

  # Copy result file to COMINOUT
  cp -p ${out_fn_base_prefix}* ${COMINOUTplot}
fi

