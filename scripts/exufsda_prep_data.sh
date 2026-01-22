#!/usr/bin/env bash

set -xue

ulimit -s unlimited; ulimit -a;

# Set date and time
YYYY=${PDY:0:4}
MM=${PDY:4:2}
DD=${PDY:6:2}
HH=${cyc}
HHsec=$(( HH * 3600 ))
HHsec_5d=$(printf "%05d" "${HHsec}")

next_date=$($NDATE ${DATE_CYCLE_FREQ_HR} $PDY$cyc)
nYYYY=${next_date:0:4}
nMM=${next_date:4:2}
nDD=${next_date:6:2}
nHH=${next_date:8:2}
nHHsec=$(( nHH * 3600 ))
nHHsec_5d=$(printf "%05d" "${nHHsec}")

pdate=$($NDATE -${DATE_CYCLE_FREQ_HR} $PDY$cyc)
YYYYp=${pdate:0:4}
MMp=${pdate:4:2}
DDp=${pdate:6:2}
HHp=${pdate:8:2}
PDYmc1=${pdate:0:8}
COMINrestart_mc1="${COMROOT}/${NET}/${model_ver}/${RUN}.${PDYmc1}/RESTART"

filedate="${PDY}.${cyc}0000"

# For JEDI time window
cycle_freq_hr_half=$(( DATE_CYCLE_FREQ_HR / 2 ))
date_hf=$($NDATE -${cycle_freq_hr_half} $PDY$cyc)
yyyy_hf=${date_hf:0:4}
mm_hf=${date_hf:4:2}
dd_hf=${date_hf:6:2}
hh_hf=${date_hf:8:2}

#
#####################################################################
# PART I.
echo "========== PART I: Input Files =========="
#####################################################################
# COMMON: Input namelist / yaml files used by multiple tasks
#####################################################################
#
## cold/warm-start dependent variables
if [ "${COLDSTART}" = "YES" ] && [ "${PDY}${cyc}" = "${DATE_FIRST_CYCLE:0:10}" ]; then
  # input.nml
  external_ic=".true."
  make_nh=".true."
  mom_input_filename="n"
  mountain=".false."
  na_init="1"
  nggps_ic=".true."
  nstf_name="2,1,0,0,0"
  warm_start=".false."

  # ufs.configure
  allcomp_start_type="startup" 
  
  # ice_in
  ice_runtype="initial"
  ice_use_restart_time=".false."
else 
  # input.nml
  external_ic=".false."
  make_nh=".false."
  mom_input_filename="r"
  mountain=".true." 
  na_init="0"
  nggps_ic=".false."
  nstf_name="2,0,0,0,0"
  warm_start=".true."

  # ufs.configure
  allcomp_start_type="continue"

  # ice_in
  ice_runtype="continue"
  ice_use_restart_time=".true."
fi

## built-in increment option dependent variables in input.nml
if [ "${HISTORY_FILE_ON_NATIVE_GRID}" == ".true." ]; then
  ignore_rst_cksum=".false."
  increment_file_on_native_grid=".true."
  read_increment=".true."
  res_latlon_dynamics="jedi_increment.atm" 
else
  ignore_rst_cksum=".true."
  increment_file_on_native_grid=".false."
  read_increment=".false."
  res_latlon_dynamics="!quote"
fi

## Application dependent variables
datm_data_type_upper=$(echo ${DATM_DATA_TYPE} | tr '[a-z]' '[A-Z]')
if [ "${APP}" = "S2SWA" ]; then
  ### ufs.configure
  allcomp_case_name="ufs.cpld"
  cmeps_coupling_mode="ufs.frac"
  cmeps_mapuv_with_cart3d="true"
  wav_mesh_wav="mesh.global_270k.nc"
  ### model_configure
  use_saved_routehandles=".true."
elif [ "${APP}" = "S2SWAL" ]; then
  ### ufs.configure
  allcomp_case_name="ufs.cpld"
  cmeps_coupling_mode="ufs.frac"
  cmeps_mapuv_with_cart3d="true"
  wav_mesh_wav="mesh.${OCN_MESH_RES}.nc"
  ### model_configure
  use_saved_routehandles=".false."
elif [ "${APP}" = "NG-GODAS" ]; then
  ### ufs.configure
  allcomp_case_name="DATM_${datm_data_type_upper}"
  cmeps_coupling_mode="ufs.nfrac.aoflux"
  cmeps_mapuv_with_cart3d="false"
  wav_mesh_wav="mesh.global_270k.nc"
  ### model_configure
  use_saved_routehandles="N/A"
elif [ "${APP}" = "ATM" ]; then
  ### ufs.configure
  allcomp_case_name="N/A"
  cmeps_coupling_mode="N/A"
  cmeps_mapuv_with_cart3d="N/A"
  wav_mesh_wav="N/A"
  ### model_configure
  use_saved_routehandles=".false."
else
  ### ufs.configure
  allcomp_case_name="N/A"
  cmeps_coupling_mode="N/A"
  cmeps_mapuv_with_cart3d="N/A"
  wav_mesh_wav="N/A"
  ### model_configure
  use_saved_routehandles=".false."
fi

########################################
## UFS weather model input: input.nml
########################################
if [ "${CUSTOM_UFS_INPUT_NML_FLAG}" = "YES" ]; then
  input_nml_fp="${CUSTOM_UFS_INPUT_NML_PATH}/${CUSTOM_UFS_INPUT_NML_FN}"
  if [ -e "${input_nml_fp}" ]; then
    rsync -avh ${input_nml_fp} "input.nml"
    rsync -avh ${input_nml_fp} "${COMINOUT}/input.nml_${PDY}${cyc}"
  else
    err_exit "UFS input.nml file (${input_nml_fp}) does not exist." 
  fi
else
  if [ "${APP}" = "NG-GODAS" ]; then
    fn_template="template.${APP}.input.nml"
  elif [ "${APP}" = "ATM" ]; then
    if [ "${JEDI_TYPE_FV3}" = "YES" ]; then
      fn_template="template.${APP}.input.nml.${CCPP_SUITE}_fv3jedi"
    else
      fn_template="template.${APP}.input.nml.${CCPP_SUITE}"
    fi
  else
    fn_template="template.${APP}.input.nml.${CCPP_SUITE}"
  fi
  ### To avoid error from "set -u" when input variable is none like ('res_latlon_dynamics:'),
  ### set the safe parameter expansion like ${res_latlon_dynamics-}. This is because
  ### with "set -u", bash treats it as res_latlon_dynamics: unbound variable.
  settings="\
  'ATM_IO_LAYOUT_X': ${ATM_IO_LAYOUT_X}
  'ATM_IO_LAYOUT_Y': ${ATM_IO_LAYOUT_Y}
  'ATM_LAYOUT_X': ${ATM_LAYOUT_X}
  'ATM_LAYOUT_Y': ${ATM_LAYOUT_Y}
  'CCPP_SUITE': ${CCPP_SUITE}
  'external_ic': '${external_ic}'
  'ignore_rst_cksum': '${ignore_rst_cksum}'
  'increment_file_on_native_grid': '${increment_file_on_native_grid}'
  'make_nh': '${make_nh}'
  'mom_input_filename': ${mom_input_filename}
  'mountain': '${mountain}'
  'na_init': ${na_init}
  'nggps_ic': '${nggps_ic}'
  'nstf_name': '${nstf_name}'
  'NPZ': ${NPZ}
  'read_increment': '${read_increment}'
  'res_latlon_dynamics': ${res_latlon_dynamics-}
  'res_p1': ${res_p1}
  'warm_start': '${warm_start}'
" # End of settings variable
  fp_template="${PARMufsda}/templates/${fn_template}"
  fn_namelist="input.nml"
  ${USHufsda}/fill_jinja_template.py -u "${settings}" -t "${fp_template}" -o "${fn_namelist}"
  rsync -avh ${fn_namelist} "${COMINOUT}/${fn_namelist}_${PDY}${cyc}"
fi

############################################
## UFS weather model input: ufs.configure
############################################
nprocs_atm_m1=$(( nprocs_forecast_atm - 1 ))
nprocs_med_m1=$(( nprocs_forecast_med - 1 ))
nprocs_atm_ocn=$(( nprocs_forecast_atm + NPROCS_OCN ))
nprocs_atm_ocn_m1=$(( nprocs_atm_ocn - 1 ))
nprocs_atm_ocn_ice=$(( nprocs_atm_ocn + NPROCS_ICE ))
nprocs_atm_ocn_ice_m1=$(( nprocs_atm_ocn_ice - 1 ))
nprocs_atm_ocn_ice_wav=$(( nprocs_atm_ocn_ice + NPROCS_WAV ))
nprocs_atm_ocn_ice_wav_m1=$(( nprocs_atm_ocn_ice_wav - 1 ))
nprocs_forecast_m1=$(( nprocs_forecast - 1 ))
datm_mesh_fn="mesh.datm.${datm_nx_global}x${datm_ny_global}.nc"
output_fh_lnd_sec=$(( OUTPUT_FH_LND * 3600 ))

settings="\
  'APP': ${APP}
  'DT_ATMOS': ${DT_ATMOS}
  'DT_RUNSEQ': ${DT_RUNSEQ}
  'ALLCOMP_RESTART_N': ${ALLCOMP_RESTART_N}
  'allcomp_case_name': ${allcomp_case_name}
  'allcomp_start_type': ${allcomp_start_type}
  'allcomp_stop_n': ${FCST_HRS}
  'atm_mesh_atm': ${datm_mesh_fn}
  'atm_model': ${atm_model}
  'atm_stop_n': ${FCST_HRS}
  'atm_petlist_bounds_n1': 0
  'atm_petlist_bounds_n2': ${nprocs_atm_m1}
  'chm_model': ${chm_model}
  'chm_petlist_bounds_n1': 0
  'chm_petlist_bounds_n2': ${nprocs_med_m1}
  'cmeps_coupling_mode': ${cmeps_coupling_mode}
  'cmeps_mapuv_with_cart3d': ${cmeps_mapuv_with_cart3d}
  'ice_mesh_ice': mesh.${OCN_MESH_RES}.nc
  'ice_model': ${ice_model}
  'ice_petlist_bounds_n1': ${nprocs_atm_ocn}
  'ice_petlist_bounds_n2': ${nprocs_atm_ocn_ice_m1}
  'ice_stop_n': ${FCST_HRS}
  'lnd_layout_x': ${ATM_LAYOUT_X}
  'lnd_layout_y': ${ATM_LAYOUT_Y}
  'lnd_model': ${lnd_model}
  'lnd_petlist_bounds_n1': ${nprocs_atm_ocn_ice_wav}
  'lnd_petlist_bounds_n2': ${nprocs_forecast_m1}
  'med_petlist_bounds_n1': 0
  'med_petlist_bounds_n2': ${nprocs_med_m1}
  'ocn_mesh_ocn': mesh.${OCN_MESH_RES}.nc
  'ocn_model': ${ocn_model}
  'ocn_petlist_bounds_n1': ${nprocs_forecast_atm}
  'ocn_petlist_bounds_n2': ${nprocs_atm_ocn_m1}
  'output_fh_lnd_sec': ${output_fh_lnd_sec}
  'OUTPUT_FH_MOM6': ${OUTPUT_FH_MOM6}
  'RES': ${RES}
  'wav_mesh_wav': ${wav_mesh_wav}
  'wav_model': ${wav_model}
  'wav_petlist_bounds_n1': ${nprocs_atm_ocn_ice}
  'wav_petlist_bounds_n2': ${nprocs_atm_ocn_ice_wav_m1}
" # End of settings variable
fp_template="${PARMufsda}/templates/template.ufs.configure"
fn_namelist="ufs.configure"
${USHufsda}/fill_jinja_template.py -u "${settings}" -t "${fp_template}" -o "${fn_namelist}"
rsync -avh ${fn_namelist} "${COMINOUT}/${fn_namelist}_${PDY}${cyc}"

##############################################
## UFS weather model input: model_configure
##############################################
settings="\
  'yyyy': !!str ${YYYY}
  'mm': !!str ${MM}
  'dd': !!str ${DD}
  'hh': !!str ${HH}
  'APP': ${APP}
  'DT_ATMOS': ${DT_ATMOS}
  'FCST_HRS': ${FCST_HRS}
  'FHROT': ${FHROT}
  'HISTORY_FILE_ON_NATIVE_GRID': ${HISTORY_FILE_ON_NATIVE_GRID}
  'ICHUNK2D': ${ICHUNK2D}
  'ICHUNK3D': ${ICHUNK3D}
  'IMO': ${IMO}
  'JCHUNK2D': ${JCHUNK2D}
  'JCHUNK3D': ${JCHUNK3D}
  'JMO': ${JMO}
  'KCHUNK3D': ${KCHUNK3D}
  'OUTPUT_FH': ${OUTPUT_FH}
  'OUTPUT_GRID': ${OUTPUT_GRID}
  'QUILTING_RESTART': ${QUILTING_RESTART}
  'RESTART_INTERVAL': ${RESTART_INTERVAL}
  'use_saved_routehandles': ${use_saved_routehandles}
  'ZSTANDARD_LEVEL': ${ZSTANDARD_LEVEL}
  'WRITE_GROUPS': ${WRITE_GROUPS}
  'WRITE_TASKS_PER_GROUP': ${WRITE_TASKS_PER_GROUP}
" # End of settings variable
fp_template="${PARMufsda}/templates/template.model_configure"
fn_namelist="model_configure"
${USHufsda}/fill_jinja_template.py -u "${settings}" -t "${fp_template}" -o "${fn_namelist}"
rsync -avh ${fn_namelist} "${COMINOUT}/${fn_namelist}_${PDY}${cyc}"

#########################################
## UFS weather model input: diag table
#########################################
settings="\
  'yyyymmdd': !!str ${PDY}
  'yyyy': !!str ${YYYY}
  'mm': !!str ${MM}
  'dd': !!str ${DD}
  'hh': !!str ${cyc}
  'atm_model': ${atm_model}
  'ocn_model': ${ocn_model}
  'OUTPUT_FH_MOM6': ${OUTPUT_FH_MOM6}
  'RES': ${RES}
" # End of settings variable
fp_template="${PARMufsda}/templates/template.diag_table"
fn_namelist="diag_table"
${USHufsda}/fill_jinja_template.py -u "${settings}" -t "${fp_template}" -o "${fn_namelist}"
rsync -avh ${fn_namelist} "${COMINOUT}/${fn_namelist}_${PDY}${cyc}"

#################################
## FV3 input file: field_table
#################################
if [ "${atm_model}" = "fv3" ]; then
  settings="\
  'APP': ${APP}
  'atm_model': ${atm_model}
  'chm_model': ${chm_model}
" # End of settings variable
  fp_template="${PARMufsda}/templates/template.field_table"
  fn_namelist="field_table"
  ${USHufsda}/fill_jinja_template.py -u "${settings}" -t "${fp_template}" -o "${fn_namelist}"
  rsync -avh ${fn_namelist} "${COMINOUT}/${fn_namelist}_${PDY}${cyc}"
fi

################################
## MOM6 input file: MOM_input
################################
if [ "${ocn_model}" = "mom6" ]; then
  if [ "${APP}" = "S2SWA" ] || [ "${APP}" = "S2SWAL" ]; then
    mom6_use_waves="True"
  else
    mom6_use_waves="False"
  fi
  settings="\
'DT_MOM6': ${DT_MOM6}
'MOM6_DT_THERM': ${MOM6_DT_THERM}
'MOM6_NIGLOBAL': ${MOM6_NIGLOBAL}
'MOM6_NJGLOBAL': ${MOM6_NJGLOBAL}
'MOM6_NK': ${MOM6_NK}
'mom6_use_waves': ${mom6_use_waves}
" # End of settings variable
  fp_template="${PARMufsda}/templates/template.MOM_input"
  fn_namelist="MOM_input"
  ${USHufsda}/fill_jinja_template.py -u "${settings}" -t "${fp_template}" -o "${fn_namelist}"
  rsync -avh ${fn_namelist} "${COMINOUT}/${fn_namelist}_${PDY}${cyc}"
fi

#############################
## CICE input file: ice_in
#############################
if [ "${ice_model}" = "cice6" ]; then
  settings="\
'yyyymmdd': !!str ${PDY}
'yyyy': !!str ${YYYY}
'yyyy_last': !!str ${nYYYY}
'yyyy_align': !!str ${YYYY}
'mm': !!str ${MM}
'dd': !!str ${DD}
'hh_sec': !!str ${HHsec_5d}
'DT_ATMOS': ${DT_ATMOS}
'MOM6_NIGLOBAL': ${MOM6_NIGLOBAL}
'MOM6_NJGLOBAL': ${MOM6_NJGLOBAL}
'NPROCS_ICE': ${NPROCS_ICE}
'ice_runtype': ${ice_runtype}
'ice_use_restart_time': ${ice_use_restart_time}
'OUTPUT_FH_CICE': ${OUTPUT_FH_CICE}
" # End of settings variable
  fp_template="${PARMufsda}/templates/template.ice_in"
  fn_namelist="ice_in"
  ${USHufsda}/fill_jinja_template.py -u "${settings}" -t "${fp_template}" -o "${fn_namelist}"
  rsync -avh ${fn_namelist} "${COMINOUT}/${fn_namelist}_${PDY}${cyc}"
fi
echo "=========== Input Namelist Files COMPLETE !!! ================="


#
#####################################################################
# PART II.
echo "========== PART II: JEDI Configuration =========="
#####################################################################
# JEDI configuration files
#####################################################################
#
if [[ ( "${TYPE_ANAL_FCST}" == "both" || "${TYPE_ANAL_FCST}" == "anal-only" ||
       	"${TYPE_ANAL_FCST}" == "fcst-1st" )  && "${CUSTOM_JEDI_CONFIG_FLAG}" != "YES" ]]; then
  ###################################
  ## Atmosphere: FV3-JEDI analysis
  ###################################
  if [ "${JEDI_TYPE_FV3}" = "YES" ]; then
    jedi_nml_fn="jedi_${JEDI_ALGORITHM}_fv3_${PDY}${cyc}.yaml"
    jedi_inc_nml_fn="jedi_${JEDI_ALGORITHM}_fv3inc_${PDY}${cyc}.yaml"
    if [ "${CUSTOM_JEDI_CONFIG_FLAG}" = "TEMPLATE" ]; then
      fv3_timewindow_begin_iso="${yyyy_hf}-${mm_hf}-${dd_hf}T${hh_hf}:00:00Z"
      fv3_background_date_iso="${YYYY}-${MM}-${DD}T${HH}:00:00Z"
      settings="\
  'cdate': !!str ${PDY}${cyc}
  'fv3_background_date_iso': !!str ${fv3_background_date_iso}
  'fv3_background_filenames_atm': cubed_sphere_grid_atm.nc  
  'fv3_background_filenames_sfc': cubed_sphere_grid_sfc.nc
  'fv3_geo_layout_x': 4
  'fv3_geo_layout_y': 4
  'fv3_geo_npx': ${res_p1}
  'fv3_geo_npy': ${res_p1}
  'fv3_geo_npz': ${NPZ}
  'fv3_timewindow_begin_iso': !!str ${fv3_timewindow_begin_iso}
  'fv3_timewindow_length': PT${DATE_CYCLE_FREQ_HR}H
  'pdate': !!str ${pdate}
" # End of settings variable

      ### For analysis
      fn_template="template.jedi_3dvar_fv3.yaml"
      fp_template="${PARMufsda}/jedi/fv3/${fn_template}"
      ${USHufsda}/fill_jinja_template.py -u "${settings}" -t "${fp_template}" -o "${jedi_nml_fn}"

      ### For increment
      fn_template="template.jedi_3dvar_fv3inc.yaml"
      fp_template="${PARMufsda}/jedi/fv3/${fn_template}"
      ${USHufsda}/fill_jinja_template.py -u "${settings}" -t "${fp_template}" -o "${jedi_inc_nml_fn}"
    else
    ### JCB: UNDER DEVELOPMENT ###
      err_exit "JCB for fv3-jedi is not available !!!"
    fi
  fi

  ###########################
  ## Marine: SOCA analysis
  ###########################
  if [ "${JEDI_TYPE_SOCA}" = "YES" ]; then
    jedi_nml_fn="jedi_${JEDI_ALGORITHM}_soca_${PDY}${cyc}.yaml"
    if [ "${CUSTOM_JEDI_CONFIG_FLAG}" = "TEMPLATE" ]; then
      soca_timewindow_begin_iso="${yyyy_hf}-${mm_hf}-${dd_hf}T${hh_hf}:00:00Z"
      soca_background_date_iso="${YYYY}-${MM}-${DD}T${HH}:00:00Z"
      settings="\
  'cdate': !!str ${PDY}${cyc}
  'soca_timewindow_begin_iso': !!str ${soca_timewindow_begin_iso}
  'soca_background_date_iso': !!str ${soca_background_date_iso}
" # End of settings variable
      fn_template="template.jedi_3dvar_soca.yaml"
      fp_template="${PARMufsda}/jedi/soca/${fn_template}"
      ${USHufsda}/fill_jinja_template.py -u "${settings}" -t "${fp_template}" -o "${jedi_nml_fn}"
    else
    ### JCB: UNDER DEVELOPMENT ###
      err_exit "JCB for SOCA is not available !!!"

      template_fp="${PARMufsda}/jedi/jcb-base_soca.yaml.j2"
      jcb_base_fn="jcb-base_soca.yaml"
      jcb_base_fp="${DATA}/${jcb_base_fn}"
      ${USHufsda}/fill_jinja_template.py -u "${settings}" -t "${template_fp}" -o "${jcb_base_fp}"
      # Run JCB
      ${USHufsda}/jcb_setup.py -i "${jcb_base_fn}" -o "${jedi_nml_fn}" -a "${JEDI_ALGORITHM}" -t "soca" -g "NO" -l "${PY_LOG_LEVEL}"
      if [ $? -ne 0 ]; then
        err_exit "Generation of JEDI YAML file for SOCA by JCB failed !!!"
      fi
    fi
    cp -p ${jedi_nml_fn} ${COMINOUT}
  fi

  #########################################
  ## Land: Snow / Soil-moisture analysis
  #########################################
  if [ -n "${list_jedi_land}" ]; then
    # JCB parameters
    driver_do_posterior_observer="false"
    driver_do_test_prints="false"
    driver_save_posterior_ensemble="false"
    driver_save_posterior_mean_increment="true"
    driver_update_obs_config_with_geometry_info="false"
    final_diagnostics_departures="anlmob"
    inflation_mult="1.0"
    inflation_rtpp="0.0"
    inflation_rtps="0.0"
    local_ensemble_da_solver="${JEDI_ALGORITHM^^}"
    land_background_time_fv3="${filedate}"
    land_background_time_iso="${YYYY}-${MM}-${DD}T${HH}:00:00Z"
    land_fv3jedi_files_path="Data/fv3files"
    land_window_begin="${yyyy_hf}-${mm_hf}-${dd_hf}T${hh_hf}:00:00Z"
    land_window_length="PT${DATE_CYCLE_FREQ_HR}H"
    
    # Algorithm-specific values
    if [ "${JEDI_ALGORITHM}" = "letkf-oi" ]; then
      jedi_algorithm_mod="local_ensemble_da"
      local_ensemble_da_solver="Deterministic LETKF"
    else
      jedi_algorithm_mod="${JEDI_ALGORITHM}"
    fi
    
    # Variable name of snow depth
    if [ "${FRAC_GRID}" = "YES" ]; then
      snowdepth_vn="snodl"
    else
      snowdepth_vn="snwdph"
    fi
     
    # Run JCB to create JEDI input yaml files
    list_jedi_types=(${list_jedi_land})
    echo "List of JEDI analyses: ${list_jedi_types[@]}"
    for jedi_type in "${list_jedi_types[@]}"; do
      echo "JEDI analysis for ${jedi_type}"
      if [ "${jedi_type}" = "snow" ]; then
        driver_save_posterior_mean="false"
        inc_fn_prefix="snowinc" 
      elif [ "${jedi_type}" = "soil_moisture" ]; then
        driver_save_posterior_mean="true"
        inc_fn_prefix="smcinc"
      else
        driver_save_posterior_mean="false"
        inc_fn_prefix="inc"
      fi
    
      # update jcb-base yaml file
      settings="\
  'FIXufsda': ${FIXufsda}
  'JEDI_ALGORITHM': ${JEDI_ALGORITHM}
  'jedi_algorithm_mod': ${jedi_algorithm_mod}
  'PARMufsda': ${PARMufsda}
  'RES': ${RES}
  'driver_do_posterior_observer': ${driver_do_posterior_observer}
  'driver_do_test_prints': ${driver_do_test_prints}
  'driver_save_posterior_ensemble': ${driver_save_posterior_ensemble}
  'driver_save_posterior_mean': ${driver_save_posterior_mean}
  'driver_save_posterior_mean_increment': ${driver_save_posterior_mean_increment}
  'driver_update_obs_config_with_geometry_info': ${driver_update_obs_config_with_geometry_info}
  'final_diagnostics_departures': ${final_diagnostics_departures}
  'inc_fn_prefix': ${inc_fn_prefix}
  'inflation_mult': ${inflation_mult}
  'inflation_rtpp': ${inflation_rtpp}
  'inflation_rtps': ${inflation_rtps}
  'jedi_type': ${jedi_type}
  'local_ensemble_da_solver': ${local_ensemble_da_solver}
  'land_window_begin': !!str ${land_window_begin}
  'land_window_length': ${land_window_length}
  'land_final_inc_file_path': ./
  'land_fv3jedi_files_path': ${land_fv3jedi_files_path}
  'land_layout_x': 1
  'land_layout_y': 1
  'land_npx_anl': ${res_p1}
  'land_npy_anl': ${res_p1}
  'land_npz_anl': ${NPZ}
  'land_npx_ges': ${res_p1}
  'land_npy_ges': ${res_p1}
  'land_npz_ges': ${NPZ}
  'land_background_path': bkg
  'land_background_time_fv3': !!str ${land_background_time_fv3}
  'land_background_time_iso': !!str ${land_background_time_iso}
  'land_bump_data_dir': berror
  'land_obsdatain_path': obs
  'land_obsdatain_prefix': "obs.${PDY}.${cycle}."
  'land_obsdataout_path': diags
  'land_obsdataout_prefix': "diag."
  'land_obsdataout_suffix': "_${PDY}${cyc}.nc"
  'land_orog_files_path': "${FIXufsda}/DATA_fix/FV3/Tiled/C${RES}"
  'land_orog_prefix': "C${RES}.${OCN_MESH_RES}"
  'snowdepth_vn': ${snowdepth_vn}
  'OBS_GHCN_SNOW': '${OBS_GHCN_SNOW}'
  'OBS_IMS_SNOW': '${OBS_IMS_SNOW}'
  'OBS_SFCSNO': '${OBS_SFCSNO}'
  'OBS_SMAP': '${OBS_SMAP}'
  'OBS_SMOPS': '${OBS_SMOPS}'
" # End of settings variable
    
      template_fp="${PARMufsda}/jedi/jcb-base_land.yaml.j2"
      jcb_base_fn="jcb-base_${jedi_type}.yaml"
      jcb_base_fp="${DATA}/${jcb_base_fn}"
      jcb_out_fn="jedi_${JEDI_ALGORITHM}_${jedi_type}_${PDY}${cyc}.yaml"
      ${USHufsda}/fill_jinja_template.py -u "${settings}" -t "${template_fp}" -o "${jcb_base_fp}"
      # Run JCB
      ${USHufsda}/jcb_setup.py -i "${jcb_base_fn}" -o "${jcb_out_fn}" -a "${JEDI_ALGORITHM}" -t "${jedi_type}" -g "${FRAC_GRID}" -l "${PY_LOG_LEVEL}" 
      if [ $? -ne 0 ]; then
        err_exit "Generation of JEDI YAML file for ${jedi_type} by JCB failed !!!"
      fi
      cp -p ${jcb_out_fn} ${COMINOUT}
    done
  fi
fi
echo "============= JEDI Coonfiguration COMPLETE !!! ======================"


#
#####################################################################
# PART III.
echo "========== PART III: SOCA pre-processing =========="
#####################################################################
# SOCA: gridgen / setcorscales / parameters_diffusion
#####################################################################
#
# note: only work with restart file (not ic file)
if [ "${COLDSTART}" = "YES" ] && [ "${PDY}${cyc}" == "${DATE_FIRST_CYCLE:0:10}" ]; then
  do_soca_prep="NO"
else
  do_soca_prep="YES"
fi

if [[ "${JEDI_TYPE_SOCA}" == "YES" && "${do_soca_prep}" = "YES" &&
    ( "${TYPE_ANAL_FCST}" == "both" || "${TYPE_ANAL_FCST}" == "anal-only" ||
      "${TYPE_ANAL_FCST}" == "fcst-1st" ) ]]; then
  mkdir -p soca_prep
  cd soca_prep
  mkdir -p INPUT
  mkdir -p MOM6_OUTPUT

  ## Fileds metadata files
  cp -p "${PARMufsda}/jedi/fieldmetadata/fv3jedi_fieldmetadata_soca.yaml" "fields_metadata.yaml"

  ## input.nml
  settings="\
  'yyyy': !!str ${YYYY}
  'mm': !!str ${MM}
  'dd': !!str ${DD}
  'hh': !!str ${HH}
  'mom_input_filename': ${mom_input_filename}
" # End of settings variable
  fn_template="template.SOCA.input.nml"
  fp_template="${PARMufsda}/jedi/soca/${fn_template}"
  fn_namelist="input.nml"
  ${USHufsda}/fill_jinja_template.py -u "${settings}" -t "${fp_template}" -o "${fn_namelist}"

  ## MOM6 input namelist file
  ln -nsf "${DATA}/MOM_input" INPUT/.

  ## Restart file
  if [ "${COLDSTART}" = "NO" ] && [ "${PDY}${cyc}" = "${DATE_FIRST_CYCLE:0:10}" ]; then
    data_dir="${WARMSTART_DIR}"
  else
    data_dir="${COMINrestart_mc1}"
  fi
  r_fp="${data_dir}/${filedate}.MOM.res.nc"
  if [ -e "${r_fp}" ]; then
    ln -nsf "${r_fp}" INPUT/MOM.res.nc
  else
    err_exit "Symlink failed: ${r_fp} file does not exist."
  fi

  #############
  ## gridgen 
  #############
  ## Make sure this should run in parallel, otherwise it will cause unexpected errors.

  path_mom6_fix_dir="${FIXufsda}/DATA_fix/MOM6"
  soca_gridspec_fn="soca_gridspec_${MOM6_NIGLOBAL}x${MOM6_NJGLOBAL}x${MOM6_NK}.nc"
  if [ -e "${path_mom6_fix_dir}/${soca_gridspec_fn}" ]; then
    cp -p "${path_mom6_fix_dir}/${soca_gridspec_fn}" "soca_gridspec.nc"
  elif [ -e "${DATA_SHARE}/${soca_gridspec_fn}" ]; then
    cp -p "${DATA_SHARE}/${soca_gridspec_fn}" "soca_gridspec.nc"
  else
    ### SOCA input yaml file
    jedi_nml_fn="gridgen.yaml"
    cp -p "${PARMufsda}/jedi/soca/${jedi_nml_fn}" .

    ### Rossby file
    ln -nsf "${path_mom6_fix_dir}/rossrad.nc" .

    ### diag_table
    ln -nsf "${DATA}/diag_table" .

    ### Fix files
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
        ln -nsf ${ifp} INPUT/.
      else
        err_exit "Symlink failed: ${ifp} does not exist."
      fi
    done
  
    ### Run soca_gridgen.x
    if [ "${JEDI_BUNDLE_GDAS}" = "gdas" ]; then
      jedi_exe_fn="gdas_soca_gridgen.x"
    else
      jedi_exe_fn="soca_gridgen.x"
    fi
    export pgm="${jedi_exe_fn}"
    . prep_step
    ${RUN_CMD} -n 2 ${JEDI_BIN_PATH}/$pgm ${jedi_nml_fn} >>$pgmout 2>errfile
    export err=$?; err_chk
    cp errfile errfile_gridgen
    if [[ $err != 0 ]]; then
      err_exit "JEDI SOCA gridgen failed"
    fi
  fi
  cp -p soca_gridspec.nc "${COMINOUT}/${soca_gridspec_fn}"
  if [ ! -e "${DATA_SHARE}/${soca_gridspec_fn}" ]; then
    ln -nsf "${COMINOUT}/${soca_gridspec_fn}" "${DATA_SHARE}/${soca_gridspec_fn}"
  fi

  ##################
  ## setcorscales
  ##################
  tmp_time_iso="0000-00-00T00:00:00Z"
  soca_cor_rh_fn_prefix="ocn.cor_rh.incr"
  soca_cor_rv_fn_prefix="ocn.cor_rv.incr"
  soca_cor_rh_fn="${soca_cor_rh_fn_prefix}_${MOM6_NIGLOBAL}x${MOM6_NJGLOBAL}x${MOM6_NK}.nc"
  soca_cor_rv_fn="${soca_cor_rv_fn_prefix}_${MOM6_NIGLOBAL}x${MOM6_NJGLOBAL}x${MOM6_NK}.nc"
  if [ -e "${path_mom6_fix_dir}/${soca_cor_rh_fn}" ] && \
     [ -e "${path_mom6_fix_dir}/${soca_cor_rv_fn}" ]; then
    cp -p "${path_mom6_fix_dir}/${soca_cor_rh_fn}" "${soca_cor_rh_fn_prefix}.nc"
    cp -p "${path_mom6_fix_dir}/${soca_cor_rv_fn}" "${soca_cor_rv_fn_prefix}.nc"
  elif [ -e "${DATA_SHARE}/${soca_cor_rh_fn}" ] && \
       [ -e "${DATA_SHARE}/${soca_cor_rv_fn}" ]; then
    cp -p "${DATA_SHARE}/${soca_cor_rh_fn}" "${soca_cor_rh_fn_prefix}.nc"
    cp -p "${DATA_SHARE}/${soca_cor_rv_fn}" "${soca_cor_rv_fn_prefix}.nc"
  else
    ### SOCA input yaml file
    jedi_nml_fn="setcorscales.yaml"
    cp -p "${PARMufsda}/jedi/soca/${jedi_nml_fn}" .

    ### Run soca_setcorscales.x
    if [ "${JEDI_BUNDLE_GDAS}" = "gdas" ]; then
      jedi_exe_fn="gdas_soca_setcorscales.x"
    else
      jedi_exe_fn="soca_setcorscales.x"
    fi
    export pgm="${jedi_exe_fn}"
    . prep_step
    ${RUN_CMD} -n 12 ${JEDI_BIN_PATH}/$pgm ${jedi_nml_fn} >>$pgmout 2>errfile
    export err=$?; err_chk
    cp errfile errfile_setcorscales
    if [[ $err != 0 ]]; then
      err_exit "JEDI SOCA setcorscales failed"
    fi
    cp -p "${soca_cor_rh_fn_prefix}.${tmp_time_iso}.nc" "${soca_cor_rh_fn_prefix}.nc"
    cp -p "${soca_cor_rv_fn_prefix}.${tmp_time_iso}.nc" "${soca_cor_rv_fn_prefix}.nc"
  fi
  cp -p "${soca_cor_rh_fn_prefix}.nc" "${COMINOUT}/${soca_cor_rh_fn}"
  cp -p "${soca_cor_rv_fn_prefix}.nc" "${COMINOUT}/${soca_cor_rv_fn}"
  if [ ! -e "${DATA_SHARE}/${soca_cor_rh_fn}" ]; then
    ln -nsf "${COMINOUT}/${soca_cor_rh_fn}" "${DATA_SHARE}/${soca_cor_rh_fn}"
  fi
  if [ ! -e "${DATA_SHARE}/${soca_cor_rv_fn}" ]; then
    ln -nsf "${COMINOUT}/${soca_cor_rv_fn}" "${DATA_SHARE}/${soca_cor_rv_fn}"
  fi

  ##########################
  ## parameters_diffusion
  ##########################

  ### SOCA input yaml file
  soca_background_basename="${DATA}/soca_prep/INPUT"
  soca_background_date_iso="${YYYY}-${MM}-${DD}T${HH}:00:00Z"
  soca_diff_cor_hz1_fn="diffusion_cor1_hz_rossby"
  soca_diff_cor_hz2_fn="diffusion_cor1_hz_600km"
  soca_diff_cor_vt_fn="diffusion_cor1_vt_6lvls"
  settings="\
  'soca_background_basename': ${soca_background_basename}
  'soca_background_date_iso': !!str ${soca_background_date_iso}
  'soca_diff_cor_hz1_fn': ${soca_diff_cor_hz1_fn}
  'soca_diff_cor_hz2_fn': ${soca_diff_cor_hz2_fn}
  'soca_diff_cor_vt_fn': ${soca_diff_cor_vt_fn}
" # End of settings variable
  fn_template="template.parameters_diffusion.yaml"
  fp_template="${PARMufsda}/jedi/soca/${fn_template}"
  jedi_nml_fn="parameters_diffusion.yaml"
  ${USHufsda}/fill_jinja_template.py -u "${settings}" -t "${fp_template}" -o "${jedi_nml_fn}"

  ### Run soca_error_covariance_toolbox.x
  if [ "${JEDI_BUNDLE_GDAS}" = "gdas" ]; then
    jedi_exe_fn="gdas_soca_error_covariance_toolbox.x"
  else
    jedi_exe_fn="soca_error_covariance_toolbox.x"
  fi
  export pgm="${jedi_exe_fn}"
  . prep_step
  ${RUN_CMD} -n ${NPROCS_PREP_DATA} ${JEDI_BIN_PATH}/$pgm ${jedi_nml_fn} >>$pgmout 2>errfile
  export err=$?; err_chk
  cp errfile errfile_parameters_diffusion
  if [[ $err != 0 ]]; then
    err_exit "JEDI SOCA parameters_diffusion failed"
  fi
  cp -p "${soca_diff_cor_hz1_fn}.nc" "${COMINOUT}/${soca_diff_cor_hz1_fn}_${PDY}${cyc}.nc"
  cp -p "${soca_diff_cor_hz2_fn}.nc" "${COMINOUT}/${soca_diff_cor_hz2_fn}_${PDY}${cyc}.nc"
  cp -p "${soca_diff_cor_vt_fn}.nc" "${COMINOUT}/${soca_diff_cor_vt_fn}_${PDY}${cyc}.nc"

  #############
  cd ${DATA}
fi
echo "========== SOCA Pre-processing COMPLETE !!! =================="


#
#####################################################################
# PART IV.
echo "========== PART IV: Observation Files =========="
#####################################################################
# Observation Data Files
#####################################################################
#
#################################
# Atmospheric observation data
#################################
if [ "${JEDI_TYPE_FV3}" = "YES" ]; then
  list_fv3_obs=( "atms_n20" "conventional_ps" "gnssro_cosmic2" \
	         "ozone.ompsnp_npp" "ozone.smpstc_npp" \
		 "satwnd.abi_goes-16" "scatwnd.ascat_metop-b" )
  for ifn in "${sfc_fns[@]}" ; do
    obs_dp="${DCOMINobs}/fv3/${PDY}${cyc}"
    obs_out_prefix="obs.${PDY}.${cycle}"
    obs_out_fn="${obs_out_prefix}.${ifn}.nc"
    if [ -e "${obs_dp}/${obs_out_fn}" ]; then
      cp -p "${obs_dp}/${obs_out_fn}" ${COMINOUTobs}
      # extra files
      if [ "${ifn}" = "atms_n20" ]; then
        cp -p "${obs_dp}/${obs_out_prefix}.atms_n20.satbias.nc" ${COMINOUTobs}
        cp -p "${obs_dp}/${obs_out_prefix}.atms_n20.satbias_conv.nc" ${COMINOUTobs}
        cp -p "${obs_dp}/${obs_out_prefix}.atms_n20.tlapse.txt" ${COMINOUTobs}
      fi
    else
      # ioda-converting
      # Under development
      err_exit "under development"
    fi
  done
fi

##########################
# Snow observation data
##########################
if [ "${JEDI_TYPE_SNOW}" = "YES" ]; then
  obs_out_fn_ghcn=""
  obs_out_fn_ims=""
  ## GHCN snow depth data
  if [ "${OBS_GHCN_SNOW}" = "YES" ]; then
    obs_fn="ghcn_snwd_ioda_${PDY}${cyc}.nc"
    obs_dp="${DCOMINobs}/ghcn/${YYYY}"
    obs_fp="${obs_dp}/${obs_fn}"
    obs_out_fn_ghcn="obs.${PDY}.${cycle}.ghcn_snow.nc"
  
    # Check if obs is available
    if [ -f "${obs_fp}" ]; then
      echo "GHCN observation file: ${obs_fp}"
      cp -p "${obs_fp}" "${obs_out_fn_ghcn}"
      cp -p "${obs_fp}" "${COMINOUTobs}/${obs_out_fn_ghcn}"
    elif [ -f "${obs_dp}/${obs_out_fn_ghcn}" ]; then
      echo "GHCN observation file: ${obs_dp}/${obs_out_fn_ghcn}"
      cp -p "${obs_dp}/${obs_out_fn_ghcn}" .
      cp -p "${obs_dp}/${obs_out_fn_ghcn}" "${COMINOUTobs}/${obs_out_fn_ghcn}"
    else
      input_ghcn_file="${DCOMINghcn}/${YYYYp}.csv"
      if [ ! -f "${input_ghcn_file}" ]; then
        echo "GHCN raw data path: ${DCOMINghcn}"
        echo "GHCN raw data file: ${YYYYp}.csv"
        err_exit "GHCN raw data file does not exist in designated path !!!"
      fi
      ghcn_station_file="${DCOMINghcn}/ghcnd-stations.txt"
  
      ${USHufsda}/ghcn_snod2ioda.py -i ${input_ghcn_file} -o ${obs_fn} -f ${ghcn_station_file} -d ${date_hf}
      if [ $? -ne 0 ]; then
        err_exit "Generation of GHCN obs file failed !!!"
      fi
      cp -p "${obs_fn}" "${COMINOUTobs}/${obs_out_fn_ghcn}"
    fi
  fi

  ## IMS snow data
  if [ "${OBS_IMS_SNOW}" = "YES" ]; then  
    # Check if pre-generated IMS obs file exists
    obs_fn="obs.${PDY}.${cycle}.ims_snow.tm00.nc"
    obs_dp="${DCOMINobs}/IMS/${PDY}"
    obs_fp="${obs_dp}/${obs_fn}"
    obs_out_fn_ims=${obs_fn}

    # Check if obs is available
    if [ -f "${obs_fp}" ]; then
      cp -p "${obs_fp}" .
      cp -p "${obs_fp}" "${COMINOUTobs}/${obs_out_fn_ims}"
    else
      # Set up input namelist for calcfIMS
      julian_day=$(date -d "${YYYY}-${MM}-${DD}" +%j)
      jdate="${YYYY}${julian_day}"
      orog_fn_base="C${RES}.${OCN_MESH_RES}_oro_data"
      if [ "${PDY}${cyc}" -lt "20141203" ]; then
        imsversion="1.2"
      else
        imsversion="1.3"
      fi
      imsres="4km"

      if [ "${FRAC_GRID}" = "YES" ]; then
        frac_grid=".true."
      else
        frac_grid=".false."
      fi

cat > fims.nml << EOF
&fIMS_nml
  idim = ${RES}, 
  jdim = ${RES},
  jdate = "${jdate}",
  otype = "${orog_fn_base}",
  yyyymmddhh = "${YYYY}${MM}${DD}.${HH}",
  lsm = 2,
  imsformat = 1,
  imsres = "${imsres}",
  imsversion = "${imsversion}",
  frac_grid = ${frac_grid},
  fcst_path = "${DATA}/",
  IMS_obs_path = "${DATA}/",
  IMS_ind_path = "${DATA}/"
/
EOF

      # Copy IMS raw ascii file
      ims_asc_fn="ims${jdate}_${imsres}_v${imsversion}.asc"
      if [ "${IC_DATA_MODEL}" = "gfs" ] || [ "${IC_DATA_MODEL}" = "GFS" ]; then
        fn_data_prefix="gfs"
        dcom_path="${COMINgfs}"
      elif [ "${IC_DATA_MODEL}" = "gdas" ] || [ "${IC_DATA_MODEL}" = "GDAS" ]; then
        fn_data_prefix="gdas"
        dcom_path="${COMINgdas}"
      fi
      # Since JEDI is supposed to run at 18H, cyc is fixed to 18
      input_data_dir="${dcom_path}/${fn_data_prefix}.${PDY}/18/atmos"
      cp -p "${input_data_dir}/${fn_data_prefix}.t18z.imssnow${RES}.asc" "${DATA}/${ims_asc_fn}"
      # Soft-link mapping file
      ln -nsf "${FIXufsda}/DATA_ims/IMS4km_to_FV3_mapping.C${RES}_oro_data.nc" .

      # Copy sfc_data files into work directory
      for itile in {1..6}
      do
        sfc_m0="${filedate}.sfc_data.tile${itile}.nc"
        if [ -f ${COMINrestart_mc1}/${sfc_m0} ]; then
          ln -nsf ${COMINrestart_mc1}/${sfc_m0} ${DATA}
        elif [ -f ${WARMSTART_DIR}/${sfc_m0} ]; then
          ln -nsf ${WARMSTART_DIR}/${sfc_m0} ${DATA}
        else
          err_exit "sfc_data files do not exist"
        fi
      done
  
      # Run calcfIMS.exe
      export pgm="calcfIMS.exe"
      . prep_step
      ${EXECufsda}/$pgm >>$pgmout 2>errfile
      export err=$?; err_chk
      cp errfile errfile_calcfIMS
      if [[ $err != 0 ]]; then
        err_exit "calcfIMS failed"
      fi

      # Convert to IODA format
      fims_out_fn="IMSscf.${PDY}.C${RES}_oro_data.nc"
      ${USHufsda}/imsfv3_scf2ioda.py -i ${fims_out_fn} -o ${obs_out_fn_ims}
      if [ $? -ne 0 ]; then
        err_exit "Generation of IMS obs file failed !!!"
      fi
      cp -p ${obs_out_fn_ims} "${COMINOUTobs}/${obs_out_fn_ims}"
    fi
  fi

  ## SFCSNO data
  if [ "${OBS_SFCSNO}" = "YES" ]; then
    sfcsno_fn_suffix="sfcsno.tm00.bufr_d"
    cp -p "${COMINgdas}/${PDY}/gdas.${cycle}.${sfcsno_fn_suffix}" "${COMINOUTobs}/obs.${PDY}.${cycle}.${sfcsno_fn_suffix}"
  fi
fi

###################################
# Soil-moisture observation data
###################################
if [ "${JEDI_TYPE_SOIL_MOISTURE}" = "YES" ]; then
  # SMAP data
  obs_out_fn_smap=""
  if [ "${OBS_SMAP}" = "YES" ]; then
    obs_fn="obs.${PDY}.${cycle}.smap_combined.nc"
    obs_dp="${DCOMINobs}/SMAP/${YYYY}${MM}"
    obs_fp="${obs_dp}/${obs_fn}"
    obs_out_fn_smap="${obs_fn}"

    # Check if obs is available
    if [ -f "${obs_fp}" ]; then
      echo "SMAP observation file: ${obs_fp}"
      cp -p "${obs_fp}" "${obs_out_fn_smap}"
      cp -p "${obs_fp}" "${COMINOUTobs}/${obs_out_fn_smap}"
    else
      # Create smap_raw_data directory
      smap_raw_dir="${DATA}/smap_raw_data"
      fn_smap_prefix="SMAP_L2_SM_P_E"
      fn_smap_suffix=".h5"
      mkdir -p ${smap_raw_dir}

      # Specify time window for SMAP raw data (default: +-5 hours -> total 11 hours)
      SMAP_RAW_WINDOW_SPAN_HALF="${SMAP_RAW_WINDOW_SPAN_HALF:-0}"

      # IODA-converting
      if [ "${SMAP_RAW_WINDOW_SPAN_HALF}" -eq 0 ]; then
        ihr_smap_raw_dir="${DCOMINsmap}/${PDY}"

        found=false
        for file in "${ihr_smap_raw_dir}"/*; do
          filename=$(basename "${file}")
          if [ -f "${file}" ] && [[ "${filename}" == ${fn_smap_prefix}*"${PDY}T${cyc}"*${fn_smap_suffix} ]]; then
            ln -nsf "${file}" ${smap_raw_dir}
            echo "SMAP raw data file for ${PDY}${cyc} found in ${ihr_smap_raw_dir}."
	    smap_ioda_in_fn=${filename}
            found=true
	    break
          fi
        done  
        if ! $found; then
          err_exit "No matching file for ${PDY}${cyc} found in ${ihr_smap_raw_dir}!"
        fi
	# Run ioda converting script
        ${USHufsda}/smap_ssm2ioda.py -i "${smap_raw_dir}/${smap_ioda_in_fn}" -o ${obs_out_fn_smap} --maskMissing
        if [ $? -ne 0 ]; then
          err_exit "Generation of SMAP obs file failed !!!"
        fi
      else
        hftime_smap=$($NDATE -${SMAP_RAW_WINDOW_SPAN_HALF} $PDY$cyc)
        pdy_hf=${hftime_smap:0:8}
  
        # soft-link SMAP raw data files into smap_raw_data directory
        for ihr in $(seq -${SMAP_RAW_WINDOW_SPAN_HALF} ${SMAP_RAW_WINDOW_SPAN_HALF}); do
          ihr_date=$($NDATE $ihr $PDY$cyc)
          ihr_pdy=${ihr_date:0:8}
          ihr_cyc=${ihr_date:8:2}
          ihr_smap_raw_dir="${DCOMINsmap}/${ihr_pdy}"
  
          found=false
          for file in "${ihr_smap_raw_dir}"/*; do
            filename=$(basename "${file}")
            if [ -f "${file}" ] && [[ "${filename}" == ${fn_smap_prefix}*"${ihr_pdy}T${ihr_cyc}"*${fn_smap_suffix} ]]; then
              ln -nsf "${file}" ${smap_raw_dir}
              echo "SMAP raw data file for ${ihr_date} found in ${ihr_smap_raw_dir}."
              found=true
            fi
          done        
          if ! $found; then
            err_exit "No matching file for ${ihr_date} found in ${ihr_smap_raw_dir}!"
          fi
        done
  
        # Create input yaml file
        cat > smap_ioda_concat.yaml << EOF
fn_smap_prefix: '${fn_smap_prefix}'
fn_smap_suffix: '${fn_smap_suffix}'
obs_out_fn_smap: '${obs_out_fn_smap}'
pdy_hf: '${pdy_hf}'
smap_raw_dir: '${smap_raw_dir}'
work_dir: '${DATA}'
PDY: '${PDY}'
cyc: '${cyc}'
PY_LOG_LEVEL: '${PY_LOG_LEVEL}'
USHufsda: '${USHufsda}'
EOF

        # Run the ioda converting script for SMAP and concatenate the netcdf files
        ${USHufsda}/smap_ioda_concat_files.py
        if [ $? -ne 0 ]; then
          err_exit "Generation of SMAP_ioda obs file failed !!!"
        fi
      fi
      cp -p "${obs_out_fn_smap}" "${COMINOUTobs}/${obs_out_fn_smap}"
    fi
  fi

  # SMOPS data
  if [ "${OBS_SMOPS}" = "YES" ]; then
    obs_fn="obs.${PDY}.${cycle}.smops.nc"
    obs_dp="${DCOMINobs}/SMOPS/${YYYY}${MM}"
    obs_fp="${obs_dp}/${obs_fn}"
    obs_out_fn_smops="${obs_fn}"

    # Check if obs is available
    if [ -f "${obs_fp}" ]; then
      echo "SMOPS observation file: ${obs_fp}"
      cp -p "${obs_fp}" "${obs_out_fn_smops}"
      cp -p "${obs_fp}" "${COMINOUTobs}/${obs_out_fn_smops}"
    else
      # Soft-link SMOPS raw data file to DATA directory
      fn_smops_prefix="SMOPS-CDR_v2r0_s${PDY}"
      fn_smops_raw=$(ls "${DCOMINsmops}/${fn_smops_prefix}"*)
      smops_ioda_in_fn="${fn_smops_prefix}.nc"
      if [ -n "${fn_smops_raw}" ]; then
        ln -nsf ${fn_smops_raw} ${smops_ioda_in_fn}
      else
        err_exit "SMOPS raw data file does not exist in ${DCOMINsmops} !!!"
      fi

      # Run ioda converting script
      ${USHufsda}/smops_ssm2ioda.py -i ${smops_ioda_in_fn} -o ${obs_out_fn_smops}
      if [ $? -ne 0 ]; then
        err_exit "Generation of SMOPS obs file failed !!!"
      fi
      cp -p "${obs_out_fn_smops}" "${COMINOUTobs}/${obs_out_fn_smops}"
    fi
  fi
fi
echo "============ Observation Files COMPLETE !!! ================"

