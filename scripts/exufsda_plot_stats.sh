#!/usr/bin/env bash

set -xue

# Set the default values of plotting flags
do_plot_obs="NO"
do_plot_stats="NO"
do_plot_time_history="NO"
do_plot_fcst_out_fv3="NO"
do_plot_fcst_out_mom6="NO"
do_plot_fcst_out_cice="NO"
do_plot_fcst_restart_fv3="NO"
do_plot_fcst_restart_mom6="NO"
do_plot_fcst_restart_cice="NO"
if [ "${TYPE_ANAL_FCST}" = "fcst-1st" ]; then
  if [ "${PDY}${cyc}" = "${DATE_FIRST_CYCLE:0:10}" ]; then
    do_plot_fcst_out_fv3="YES"
    do_plot_fcst_out_mom6="YES"
    do_plot_fcst_out_cice="YES"
    do_plot_fcst_restart_fv3="YES"
    do_plot_fcst_restart_mom6="YES"
    do_plot_fcst_restart_cice="YES"
  else
    do_plot_obs="YES"
    do_plot_stats="YES"
    do_plot_time_history="YES"
  fi
elif [ "${TYPE_ANAL_FCST}" = "anal-only" ]; then
  do_plot_obs="YES"
  do_plot_stats="YES"
  do_plot_time_history="YES"
  if [ "${JEDI_TYPE_SNOW}" = "YES" ] || [ "${JEDI_TYPE_SOIL_MOISTURE}" = "YES" ]; then
    do_plot_fcst_restart_fv3="YES"
  fi
  if [ "${JEDI_TYPE_SOCA}" = "YES" ]; then
    do_plot_fcst_restart_mom6="YES"
  fi
elif [ "${TYPE_ANAL_FCST}" = "fcst-only" ]; then
  do_plot_fcst_out_fv3="YES"
  do_plot_fcst_out_mom6="YES"
  do_plot_fcst_out_cice="YES"
  do_plot_fcst_restart_fv3="YES"
  do_plot_fcst_restart_mom6="YES"
  do_plot_fcst_restart_cice="YES"
elif [ "${TYPE_ANAL_FCST}" = "ctest" ]; then
  if [ "${JEDI_TYPE_SOCA}" = "YES" ]; then
    do_plot_obs="YES"
    do_plot_stats="YES"
  elif [ "${JEDI_TYPE_FV3}" = "YES" ]; then
    do_plot_obs="YES"
    do_plot_stats="YES"
  fi
else
  if [ "${COLDSTART}" = "YES" ] && [ "${PDY}${cyc}" = "${DATE_FIRST_CYCLE:0:10}" ]; then
    do_plot_fcst_out_fv3="YES"
    do_plot_fcst_out_mom6="YES"
    do_plot_fcst_out_cice="YES"
    do_plot_fcst_restart_fv3="YES"
    do_plot_fcst_restart_mom6="YES"
    do_plot_fcst_restart_cice="YES"
  else
    do_plot_obs="YES"
    do_plot_stats="YES"
    do_plot_time_history="YES"
    do_plot_fcst_out_fv3="YES"
    do_plot_fcst_out_mom6="YES"
    do_plot_fcst_out_cice="YES"
    do_plot_fcst_restart_fv3="YES"
    do_plot_fcst_restart_mom6="YES"
    do_plot_fcst_restart_cice="YES"
  fi
fi
# Turn off component and restart plots for specific APPs
if [ "${APP}" = "NG-GODAS" ]; then
  do_plot_fcst_out_fv3="NO"
  do_plot_fcst_restart_fv3="NO"
elif [ "${APP}" = "ATML" ] || [ "${APP}" = "ATM" ]; then
  do_plot_fcst_out_mom6="NO"
  do_plot_fcst_out_cice="NO"
  do_plot_fcst_restart_mom6="NO"
  do_plot_fcst_restart_cice="NO"
fi
# Trun off fcst out plot for other grid options
if [ "${OUTPUT_GRID}" != "cubed_sphere_grid" ]; then
  do_plot_fcst_out_fv3="NO"
fi

DO_PLOT_OBS="${DO_PLOT_OBS:-${do_plot_obs}}"
DO_PLOT_STATS="${DO_PLOT_STATS:-${do_plot_stats}}"
DO_PLOT_TIME_HISTORY="${DO_PLOT_TIME_HISTORY:-${do_plot_time_history}}"
DO_PLOT_FCST_OUT_FV3="${DO_PLOT_FCST_OUT_FV3:-${do_plot_fcst_out_fv3}}"
DO_PLOT_FCST_OUT_MOM6="${DO_PLOT_FCST_OUT_MOM6:-${do_plot_fcst_out_mom6}}"
DO_PLOT_FCST_OUT_CICE="${DO_PLOT_FCST_OUT_CICE:-${do_plot_fcst_out_cice}}"
DO_PLOT_FCST_RESTART_FV3="${DO_PLOT_FCST_RESTART_FV3:-${do_plot_fcst_restart_fv3}}"
DO_PLOT_FCST_RESTART_MOM6="${DO_PLOT_FCST_RESTART_MOM6:-${do_plot_fcst_restart_mom6}}"
DO_PLOT_FCST_RESTART_CICE="${DO_PLOT_FCST_RESTART_CICE:-${do_plot_fcst_restart_cice}}"

# Set other dates
next_date=$($NDATE ${DATE_CYCLE_FREQ_HR} $PDY$cyc)

YYYY=${PDY:0:4}
MM=${PDY:4:2}
DD=${PDY:6:2}
HH=${cyc}

nYYYY=${next_date:0:4}
nMM=${next_date:4:2}
nDD=${next_date:6:2}
nHH=${next_date:8:2}

# Global parameters
orog_path="${FIXufsda}/DATA_fix/FV3/Tiled/C${RES}"
orog_fn_base="C${RES}.${OCN_MESH_RES}_oro_data"
if [ "${FRAC_GRID}" = "YES" ]; then
  snowdepth_vn="snodl"
else
  snowdepth_vn="snwdph"
fi

############################################################
# Observation File Plot
############################################################
if [ "${DO_PLOT_OBS}" = "YES" ]; then
  # Soft-link the observation files to DATA
  ln -nsf ${COMINOUTobs}/* .

  cat > plot_obs_file.yaml << EOF
cartopy_ne_path: '${FIXufsda}/NaturalEarth'
JEDI_TYPE_FV3: '${JEDI_TYPE_FV3}'
JEDI_TYPE_SOCA: '${JEDI_TYPE_SOCA}'
OBS_SNOW_GHCN: '${OBS_SNOW_GHCN}'
OBS_SNOW_IMS: '${OBS_SNOW_IMS}'
OBS_SWC_SMAP: '${OBS_SWC_SMAP}'
OBS_SWC_SMOPS: '${OBS_SWC_SMOPS}'
obs_prefix: 'obs.${PDY}.${cycle}'
PDY: '${PDY}'
PY_LOG_LEVEL: '${PY_LOG_LEVEL}'
TYPE_ANAL_FCST: '${TYPE_ANAL_FCST}'
work_dir: '${DATA}'
EOF

  ${USHufsda}/plot_obs_file.py
  if [ $? -ne 0 ]; then
    err_exit "Observation file plot failed"
  fi
  # Copy result file to COMINOUT
  cp -p *.png ${COMINOUTplot}
fi

##########################
# Stats Plot: H(x); OMB
##########################
if [ "${DO_PLOT_STATS}" = "YES" ]; then
  # Number of bins in histogram plot
  nbins=100

  # Symlink hofx (diag) files to work dir
  ln -nsf ${COMINOUThofx}/* ${DATA}

  cat > plot_hofx.yaml <<EOF
cartopy_ne_path: '${FIXufsda}/NaturalEarth'
cdate: '${YYYY}-${MM}-${DD}-${HH}'
cyc: '${cyc}'
hofx_data_path: '${DATA_HOFX}'
JEDI_ALGORITHM: '${JEDI_ALGORITHM}'
JEDI_TYPE_FV3: '${JEDI_TYPE_FV3}'
JEDI_TYPE_SOCA: '${JEDI_TYPE_SOCA}'
nbins: ${nbins}
OBS_SNOW_GHCN: '${OBS_SNOW_GHCN}'
OBS_SNOW_IMS: '${OBS_SNOW_IMS}'
OBS_SNOW_SFCSNO: '${OBS_SNOW_SFCSNO}'
OBS_SWC_SMAP: '${OBS_SWC_SMAP}'
OBS_SWC_SMOPS: '${OBS_SWC_SMOPS}'
PDY: '${PDY}'
PY_LOG_LEVEL: '${PY_LOG_LEVEL}'
TYPE_ANAL_FCST: '${TYPE_ANAL_FCST}'
work_dir: '${DATA}'
EOF
  
  ${USHufsda}/plot_hofx_stats.py
  if [ $? -ne 0 ]; then
    err_exit "Scatter/Histogram plots failed."
  fi
  
  # Copy result files to COMINOUT
  num_hofx=$(find . -maxdepth 1 -type f -name "hofx_omb*" | wc -l)
  if [ "${num_hofx}" -gt 0 ]; then
    cp -p "${DATA}/hofx_omb"* ${COMINOUTplot}
    cp -p "${DATA_HOFX}/hofx_omb_timehis"* ${COMINOUThofx}
  fi
fi

###########################
# Time-history Plot: OMB
###########################
if [ "${DO_PLOT_TIME_HISTORY}" = "YES" ]; then
  fn_data_anal_prefix="analysis_"
  fn_data_anal_suffix=".log"
  out_fn_base="ufsda_timehistory"

  cat > plot_timehistory.yaml <<EOF
fn_data_anal_prefix: '${fn_data_anal_prefix}'
fn_data_anal_suffix: '${fn_data_anal_suffix}'
hofx_data_path: '${DATA_HOFX}'
jedi_exe: '${JEDI_ALGORITHM}'
JEDI_ALGORITHM: '${JEDI_ALGORITHM}'
JEDI_TYPE_SOCA: '${JEDI_TYPE_SOCA}'
out_fn_base: '${out_fn_base}'
OBS_SNOW_GHCN: '${OBS_SNOW_GHCN}'
OBS_SNOW_IMS: '${OBS_SNOW_IMS}'
OBS_SNOW_SFCSNO: '${OBS_SNOW_SFCSNO}'
OBS_SWC_SMAP: '${OBS_SWC_SMAP}'
OBS_SWC_SMOPS: '${OBS_SWC_SMOPS}'
path_data: '${LOGDIR}'
PY_LOG_LEVEL: '${PY_LOG_LEVEL}'
TYPE_ANAL_FCST: '${TYPE_ANAL_FCST}'
work_dir: '${DATA}'
EOF

  ${USHufsda}/plot_analysis_timehistory.py
  if [ $? -ne 0 ]; then
    err_exit "Time-history plots failed."
  fi

  # Copy result files to COMINOUT
  num_his=$(find . -maxdepth 1 -type f -name "${out_fn_base}*" | wc -l)
  if [ "${num_his}" -gt 0 ]; then
    cp -p ${out_fn_base}* ${COMINOUTplot}
  fi
fi

####################################
# Plot forecast output tiles: FV3
####################################
if [ "${DO_PLOT_FCST_OUT_FV3}" = "YES" ]; then
  fn_base_prefix="${NET}.${cycle}"
  out_title_base="UFS-DA::OUT::FV3::${YYYY}-${MM}-${DD}-${HH}::"
  out_fn_base="ufsda_out_fv3_${YYYY}${MM}${DD}${HH}_"
  # zlevel_number is valid only for 3-D fields
  zlevel_number_atm="1"
  zlevel_number_sfc="1"

  cat > plot_forecast_out_fv3.yaml <<EOF
cartopy_ne_path: '${FIXufsda}/NaturalEarth'
colorbar_option: 'fixed'
FCST_HRS: ${FCST_HRS}
fn_base_prefix: '${fn_base_prefix}'
out_title_base: '${out_title_base}'
out_fn_base: '${out_fn_base}'
OUTPUT_FH: '${OUTPUT_FH}'
path_data: '${COMINOUT}'
plot_each_tile: 'NO'
PY_LOG_LEVEL: '${PY_LOG_LEVEL}'
RES: ${RES}
var_list_atm:
  - tmp
var_list_sfc:
  - snod
  - soilm
work_dir: '${DATA}'
zlevel_number_atm: '${zlevel_number_atm}'
zlevel_number_sfc: '${zlevel_number_sfc}'
EOF

  ${USHufsda}/plot_forecast_out_fv3.py
  if [ $? -ne 0 ]; then
    err_exit "Forecast FV3 output plots failed."
  fi

  # Copy result files to COMINOUT
  cp -p ${out_fn_base}* ${COMINOUTplot}
fi

####################################
# Plot forecast output file: MOM6
####################################
if [ "${DO_PLOT_FCST_OUT_MOM6}" = "YES" ]; then
  fn_base_prefix="${NET}.${cycle}.ocn.f"
  fn_base_suffix=".c${RES}.nc"
  out_title_base="UFS-DA::OUT::MOM6::${YYYY}-${MM}-${DD}-${HH}::"
  out_fn_base="ufsda_out_mom6_${YYYY}${MM}${DD}${HH}_"
  # zlevel_number is valid only for 3-D fields
  zlevel_number_ocn="1"

  cat > plot_forecast_out_mom6.yaml <<EOF
cartopy_ne_path: '${FIXufsda}/NaturalEarth'
colorbar_option: 'fixed'
FCST_HRS: ${FCST_HRS}
fn_base_prefix: '${fn_base_prefix}'
fn_base_suffix: '${fn_base_suffix}'
out_title_base: '${out_title_base}'
out_fn_base: '${out_fn_base}'
path_data: '${COMINOUT}'
PY_LOG_LEVEL: '${PY_LOG_LEVEL}'
var_list_ocn:
  - SSH
  - SSS
  - temp
work_dir: '${DATA}'
zlevel_number_ocn: '${zlevel_number_ocn}'
EOF

  ${USHufsda}/plot_forecast_out_mom6.py
  if [ $? -ne 0 ]; then
    err_exit "Forecast MOM6 output plots failed."
  fi

  # Copy result files to COMINOUT
  cp -p ${out_fn_base}* ${COMINOUTplot}
fi

####################################
# Plot forecast output file: CICE
####################################
if [ "${DO_PLOT_FCST_OUT_CICE}" = "YES" ]; then
  fn_base_prefix="${NET}.${cycle}.ice.f"
  fn_base_suffix=".c${RES}.nc"
  out_title_base="UFS-DA::OUT::CICE::${YYYY}-${MM}-${DD}-${HH}::"
  out_fn_base="ufsda_out_cice_${YYYY}${MM}${DD}${HH}_"

  cat > plot_forecast_out_cice.yaml <<EOF
cartopy_ne_path: '${FIXufsda}/NaturalEarth'
colorbar_option: 'fixed'
FCST_HRS: ${FCST_HRS}
fn_base_prefix: '${fn_base_prefix}'
fn_base_suffix: '${fn_base_suffix}'
out_title_base: '${out_title_base}'
out_fn_base: '${out_fn_base}'
path_data: '${COMINOUT}'
PY_LOG_LEVEL: '${PY_LOG_LEVEL}'
RES: ${RES}
var_list_ice:
  - hi_h
  - hs_h
work_dir: '${DATA}'
EOF

  ${USHufsda}/plot_forecast_out_cice.py
  if [ $? -ne 0 ]; then
    err_exit "Forecast CICE output plots failed."
  fi

  # Copy result files to COMINOUT
  cp -p ${out_fn_base}* ${COMINOUTplot}
fi

#####################################
# Plot forecast restart tiles: FV3
#####################################
if [ "${DO_PLOT_FCST_RESTART_FV3}" = "YES" ]; then
  fn_data_base="${nYYYY}${nMM}${nDD}.${nHH}0000.sfc_data.tile"
  out_title_base="UFS-DA::RESTART::FV3::${nYYYY}-${nMM}-${nDD}-${nHH}::"
  out_fn_base="ufsda_out_restart_fv3_${nYYYY}${nMM}${nDD}${nHH}_"
  # zlevel_number is valid only for 3-D fields such as stc/smc/slc
  zlevel_number="1"

  cat > plot_forecast_restart_fv3.yaml <<EOF
cartopy_ne_path: '${FIXufsda}/NaturalEarth'
colorbar_option: 'fixed'
fn_data_base: '${fn_data_base}'
orog_path: '${orog_path}'
orog_fn_base: '${orog_fn_base}'
out_title_base: '${out_title_base}'
out_fn_base: '${out_fn_base}'
path_data: '${COMINOUT}/RESTART'
plot_each_tile: 'NO'
PY_LOG_LEVEL: '${PY_LOG_LEVEL}'
var_list_restart:
  - ${snowdepth_vn}
  - smc
work_dir: '${DATA}'
zlevel_number: '${zlevel_number}'
EOF

  ${USHufsda}/plot_forecast_restart_fv3.py
  if [ $? -ne 0 ]; then
    err_exit "Forecast restart plots for FV3 failed."
  fi

  # Copy result files to COMINOUT
  cp -p ${out_fn_base}* ${COMINOUTplot}
fi

######################################
# Plot forecast restart tiles: MOM6
######################################
if [ "${DO_PLOT_FCST_RESTART_MOM6}" = "YES" ]; then
  fn_data="${nYYYY}${nMM}${nDD}.${nHH}0000.MOM.res.nc"
  out_title_base="UFS-DA::RESTART::MOM6::${nYYYY}-${nMM}-${nDD}-${nHH}::"
  out_fn_base="ufsda_out_restart_mom6_${nYYYY}${nMM}${nDD}${nHH}_"
  # zlevel_number is valid only for 3-D fields such as stc/smc/slc
  zlevel_number="1"

  cat > plot_forecast_restart_mom6.yaml <<EOF
cartopy_ne_path: '${FIXufsda}/NaturalEarth'
colorbar_option: 'fixed'
fn_data: '${fn_data}'
out_title_base: '${out_title_base}'
out_fn_base: '${out_fn_base}'
path_data: '${COMINOUT}/RESTART'
PY_LOG_LEVEL: '${PY_LOG_LEVEL}'
var_list_restart:
  - Salt
  - sfc
  - Temp
work_dir: '${DATA}'
zlevel_number: '${zlevel_number}'
EOF

  ${USHufsda}/plot_forecast_restart_mom6.py
  if [ $? -ne 0 ]; then
    err_exit "Forecast restart plots for MOM6 failed."
  fi

  # Copy result files to COMINOUT
  cp -p ${out_fn_base}* ${COMINOUTplot}
fi

