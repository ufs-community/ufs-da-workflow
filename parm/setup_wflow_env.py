#!/usr/bin/env python3

###################################################################### CHJ #####
#
# Setting up workflow environemnt
#
###################################################################### CHJ #####

import argparse
import logging
import os
import sys
import socket
import shutil
import yaml
import math
from datetime import datetime, timedelta
from pathlib import Path

dirpath = os.path.dirname(os.path.abspath(__file__))
sys.path.append(os.path.join(dirpath, '../ush'))

from fill_jinja_template import fill_jinja_template
from uwtools.api.rocoto import realize


# Main part (will be called at the end) ============================= CHJ ======
def setup_wflow_env(machine):
    machine = machine.lower()
    logging.debug(f''' Machine (platform) name: {machine} ''')
    # Set directory paths
    parm_dir = os.getcwd()
    logging.info(f''' Current directory (PARMdir): {parm_dir} ''')
    home_dir = os.path.dirname(parm_dir)
    logging.info(f''' Home directory (HOMEdir): {home_dir} ''')

    # Read default yaml files and config.yaml and generate configuration dictionary
    config_parm = read_default_and_user_configs(machine,parm_dir)

    # Add new parameters based on given parameters
    config_parm = add_new_parm_base(home_dir,config_parm)

    # Add new parameters for HPC
    config_parm = add_new_parm_hpc(machine,config_parm)

    # Add new parameters for JEDI
    config_parm = add_new_parm_jedi(home_dir,config_parm)

    # Add new parameters for ufs-model
    config_parm = add_new_parm_ufs_model(config_parm)

    # Check if parameters are valid
    config_parm = check_valid_parm(home_dir,config_parm)

    # Remove keys from config_parm
    flat = {}
    for key, content in config_parm.items():
        flat.update(content)
    config_parm_str = yaml.dump(flat, sort_keys=True, default_flow_style=False)
    logging.debug(f''' FINAL configuration: {config_parm_str}''')

    # Create job cards and task-specific environment variable files
    create_jobcard_envvar(home_dir,parm_dir,config_parm,config_parm_str)

    # Create workflow-manager dependent files
    workflow_manager = config_parm["parm"]["WORKFLOW_MANAGER"]
    ## Rocoto
    if workflow_manager == "rocoto":
        create_xml_extra(parm_dir,config_parm,config_parm_str)
    ## ecFlow
    elif workflow_manager == "ecflow":
        create_ecflow_files(home_dir,config_parm)

    # Create symbolic links for com/log/tmp directories
    create_symlinks_dirs(parm_dir,config_parm)


# ==================================================================== CHJ =====
def read_default_and_user_configs(machine, parm_dir):
    # list of YAML files in config_default dir
    config_default_path = os.path.join(parm_dir,"config_default")
    prefix = "default."
    suffix = ".yaml"
    config_files = []
    for fn in os.listdir(config_default_path):
        if fn.startswith(prefix) and fn.endswith(suffix) \
           and os.path.isfile(os.path.join(config_default_path,fn)):
            config_name = fn[len(prefix):-len(suffix)]
            config_files.append(config_name)
    config_files = sorted(config_files)
    logging.info(f''' Config default YAML files: {config_files}''')

    config_parm = {}
    for icf in config_files:
        fn = f'''{prefix}{icf}{suffix}'''
        with open(os.path.join(config_default_path,fn), "r") as f:
            data = yaml.safe_load(f) or {}
        # Replace None sections with empty dict
        for k, v in data.items():
            if v is None:
                data[k] = {}
        merge_dicts(config_parm, data)

    # Set machine-specific parameters
    machine_config = set_machine_parm(machine)
    # Merge default and machine-specific parameters
    merge_dicts(config_parm,machine_config)
  
    # Read config.yaml and update configuration
    yaml_file = "config.yaml"
    try:
        with open(yaml_file, 'r') as f:
            yaml_data = yaml.safe_load(f) or {}
        # Replace None sections with empty dict
        for k, v in yaml_data.items():
            if v is None:
                yaml_data[k] = {}        
        f.close()
        logging.debug(f''' Input YAML file:, {yaml_data} ''')
    except FileNotFoundError:
        logging.error(f''' FATAL ERROR: Input YAML file {yaml_file} does not exist! ''')

    merge_dicts(config_parm,yaml_data)
    
    # Update some parameters
    config_parm["parm"]["MACHINE"] = machine

    return config_parm


# ==================================================================== CHJ =====
def add_new_parm_base(home_dir,config_parm):
    ptmp = config_parm["path"]["PTMP"]
    warmstart_dir = config_parm["path"]["WARMSTART_DIR"]
    app = config_parm["parm"]["APP"]
    date_cycle_freq_hr = config_parm["parm"]["DATE_CYCLE_FREQ_HR"]
    date_first_cycle = config_parm["parm"]["DATE_FIRST_CYCLE"]
    date_last_cycle = config_parm["parm"]["DATE_LAST_CYCLE"]
    exp_case_name = config_parm["parm"]["EXP_CASE_NAME"]
    run = config_parm["parm"]["RUN"]

    exp_basedir = os.path.dirname(home_dir)
    logging.info(f''' Experimental base directory (exp_basedir): {exp_basedir} ''')

    # Create an experimental case directory
    if exp_case_name is None or exp_case_name == "None":
        exp_case_name = f'''{app}_{run}'''
        config_parm["parm"]["EXP_CASE_NAME"] = exp_case_name

    # Path to experimenal case
    exp_case_path = os.path.join(exp_basedir, "exp_case", exp_case_name) 
    os.makedirs(exp_case_path)
    logging.info(f''' Experimental case directory {exp_case_path} has been created.''')

    # Calculate date for the second cycle
    if date_first_cycle == date_last_cycle:
        date_second_cycle = None
    else:
        next_date = datetime.strptime(str(date_first_cycle), "%Y%m%d%H") + timedelta(hours=date_cycle_freq_hr)
        date_second_cycle = next_date.strftime("%Y%m%d%H")

    # Directory containing file for warm-start
    fix_dir = os.path.join(home_dir, 'fix')
    if warmstart_dir is None or warmstart_dir == "None":
        warmstart_dir = os.path.join(fix_dir, "DATA_restart")
    print(fix_dir,warmstart_dir)

    # Set PTMP: PTMP/envir = OPSROOT for NOAA NCO EE2 compliance
    if ptmp is None or ptmp == "None":
        ptmp = os.path.join(exp_basedir, "ptmp")

    # Add parameters
    config_parm["parm"]["date_second_cycle"] = date_second_cycle
    config_parm["parm"]["res_p1"] = config_parm["parm"]["RES"] + 1
    config_parm["path"]["exp_basedir"] = exp_basedir
    config_parm["path"]["exp_case_path"] = exp_case_path
    config_parm["path"]["HOMEufsda"] = home_dir
    config_parm["path"]["PTMP"] = ptmp
    config_parm["path"]["WARMSTART_DIR"] = warmstart_dir

    return config_parm


# ==================================================================== CHJ =====
def add_new_parm_hpc(machine,config_parm):
    # Calculate HPC parameter values
    jedi_type_soca = config_parm["flag"]["JEDI_TYPE_SOCA"]
    app = config_parm["parm"]["APP"]
    atm_layout_x = config_parm["parm"]["ATM_LAYOUT_X"]
    atm_layout_y = config_parm["parm"]["ATM_LAYOUT_Y"]
    atm_io_layout_x = config_parm["parm"]["ATM_IO_LAYOUT_X"]
    atm_io_layout_y = config_parm["parm"]["ATM_IO_LAYOUT_Y"]
    max_cores_per_node = config_parm["parm"]["MAX_CORES_PER_NODE"]
    nprocs_analysis = config_parm["parm"]["NPROCS_ANALYSIS"]
    nprocs_datm = config_parm["parm"]["NPROCS_DATM"]
    nprocs_fcst_ic = config_parm["parm"]["NPROCS_FCST_IC"]
    nprocs_ice = config_parm["parm"]["NPROCS_ICE"]
    nprocs_ocn = config_parm["parm"]["NPROCS_OCN"]
    nprocs_plot_stats = config_parm["parm"]["NPROCS_PLOT_STATS"]
    nprocs_prep_data = config_parm["parm"]["NPROCS_PREP_DATA"]
    nprocs_wav = config_parm["parm"]["NPROCS_WAV"]

    if app == "S2SWA":
        nprocs_forecast_med = 6*(atm_layout_x*atm_layout_y)
        nprocs_forecast_atm = nprocs_forecast_med + 6*(atm_io_layout_x*atm_io_layout_y)
        nprocs_forecast = nprocs_forecast_atm + nprocs_ocn + nprocs_ice + nprocs_wav
    elif app == "S2SWAL":
        nprocs_forecast_med = 6*(atm_layout_x*atm_layout_y)
        nprocs_forecast_atm = nprocs_forecast_med + 6*(atm_io_layout_x*atm_io_layout_y)
        nprocs_forecast = nprocs_forecast_atm + nprocs_ocn + nprocs_ice + nprocs_wav + nprocs_forecast_med
    elif app == "NG-GODAS":
        nprocs_forecast_atm = nprocs_datm
        nprocs_forecast_med = nprocs_forecast_atm
        nprocs_forecast = nprocs_forecast_atm + nprocs_ocn + nprocs_ice
    elif app == "ATM":
        nprocs_forecast_atm = 6*(atm_layout_x*atm_layout_y + atm_io_layout_x*atm_io_layout_y)
        nprocs_forecast_med = nprocs_forecast_atm
        nprocs_forecast = nprocs_forecast_atm

    # for analysis task
    if nprocs_analysis <= max_cores_per_node:
        nnodes_analysis = 1
        nprocs_per_node_analysis = nprocs_analysis
    else:
        nnodes_analysis = math.ceil(nprocs_analysis/max_cores_per_node)
        nprocs_per_node_analysis = math.ceil(nprocs_analysis/nnodes_analysis)

    # for fcst_ic task
    if nprocs_fcst_ic <= max_cores_per_node:
        nnodes_fcst_ic = 1
        nprocs_per_node_fcst_ic = nprocs_fcst_ic
    else:
        nnodes_fcst_ic = math.ceil(nprocs_fcst_ic/max_cores_per_node)
        nprocs_per_node_fcst_ic = math.ceil(nprocs_fcst_ic/nnodes_fcst_ic)

    # for forecast task
    if nprocs_forecast <= max_cores_per_node:
        nnodes_forecast = 1
        nprocs_per_node_forecast = nprocs_forecast
    else:
        nnodes_forecast = math.ceil(nprocs_forecast/max_cores_per_node)
        nprocs_per_node_forecast = math.ceil(nprocs_forecast/nnodes_forecast)

    # for plot_stats
    if nprocs_plot_stats <= max_cores_per_node:
        nnodes_plot_stats = 1
        nprocs_per_node_plot_stats = nprocs_plot_stats
    else:
        nnodes_plot_stats = math.ceil(nprocs_plot_stats/max_cores_per_node)
        nprocs_per_node_plot_stats = math.ceil(nprocs_plot_stats/nnodes_plot_stats)

    # for prep_data task
    if jedi_type_soca == "YES" and nprocs_prep_data < 12:
        logging.warning(f''' NPROCS_PREP_DATA < 12 => changed to 12 because setcorscales uses 12 !!!''')
        nprocs_prep_data = 12

    if nprocs_prep_data <= max_cores_per_node:
        nnodes_prep_data = 1
        nprocs_per_node_prep_data = nprocs_prep_data
    else:
        nnodes_prep_data = math.ceil(nprocs_prep_data/max_cores_per_node)
        nprocs_per_node_prep_data = math.ceil(nprocs_prep_data/nnodes_prep_data)

    # Slurm memory flag: some platforms do not support the memory flag in slurm
    mem_not_req = [ "gaeac6", "orion" ]
    if machine in mem_not_req:
        memory_flag = False
    else:
        memory_flag = True

    config_parm["parm"]["memory_flag"] = memory_flag
    config_parm["parm"]["nnodes_analysis"] = nnodes_analysis
    config_parm["parm"]["nnodes_fcst_ic"] = nnodes_fcst_ic
    config_parm["parm"]["nnodes_forecast"] = nnodes_forecast
    config_parm["parm"]["nnodes_plot_stats"] = nnodes_plot_stats
    config_parm["parm"]["nnodes_prep_data"] = nnodes_prep_data
    config_parm["parm"]["nprocs_forecast"] = nprocs_forecast
    config_parm["parm"]["nprocs_forecast_atm"] = nprocs_forecast_atm
    config_parm["parm"]["nprocs_forecast_med"] = nprocs_forecast_med
    config_parm["parm"]["nprocs_per_node_analysis"] = nprocs_per_node_analysis
    config_parm["parm"]["nprocs_per_node_fcst_ic"] = nprocs_per_node_fcst_ic
    config_parm["parm"]["nprocs_per_node_forecast"] = nprocs_per_node_forecast
    config_parm["parm"]["nprocs_per_node_plot_stats"] = nprocs_per_node_plot_stats
    config_parm["parm"]["nprocs_per_node_prep_data"] = nprocs_per_node_prep_data
    config_parm["parm"]["NPROCS_PREP_DATA"] = nprocs_prep_data

    return config_parm


# ==================================================================== CHJ =====
def add_new_parm_jedi(home_dir,config_parm):
    jedi_type_snow = config_parm["flag"]["JEDI_TYPE_SNOW"]
    jedi_type_soca = config_parm["flag"]["JEDI_TYPE_SOCA"]
    jedi_type_soil_moisture = config_parm["flag"]["JEDI_TYPE_SOIL_MOISTURE"]
    custom_jedi_config_path = config_parm["path"]["CUSTOM_JEDI_CONFIG_PATH"]
    exp_basedir = config_parm["path"]["exp_basedir"]
    jedi_bin_path = config_parm["path"]["JEDI_BIN_PATH"]
    jedi_iodaconv_path = config_parm["path"]["JEDI_IODACONV_PATH"]
    jedi_bundle_gdas = config_parm["parm"]["JEDI_BUNDLE_GDAS"]
    jedi_py_ver = config_parm["parm"]["JEDI_PY_VER"]

    fix_dir = os.path.join(home_dir, 'fix')

    list_jedi_land = ""
    if jedi_type_snow == "YES":
        if not list_jedi_land:
            list_jedi_land = "snow"
        else:
            list_jedi_land = f"{list_jedi_land} snow"
    
    if jedi_type_soil_moisture == "YES":
        if not list_jedi_land:
            list_jedi_land = "soil_moisture"
        else:
            list_jedi_land = f"{list_jedi_land} soil_moisture"

    # Set machine-dependent paths if not specified in config.yaml
    if jedi_bin_path is None or jedi_bin_path == "None":
        if jedi_bundle_gdas == "gdas":
            jedi_dir_name = "GDASApp"
        else:
            jedi_dir_name = "jedi"
        jedi_bin_path = os.path.join(exp_basedir, jedi_dir_name, "build", "bin")

    if jedi_iodaconv_path is None or jedi_iodaconv_path == "None":
        jedi_iodaconv_path = os.path.join(jedi_bin_path, "../lib", jedi_py_ver)

    if custom_jedi_config_path is None or custom_jedi_config_path == "None":
        custom_jedi_config_path = os.path.join(fix_dir, "DATA_jedi", "custom_yaml")

    config_parm["parm"]["list_jedi_land"] = list_jedi_land
    config_parm["path"]["CUSTOM_JEDI_CONFIG_PATH"] = custom_jedi_config_path
    config_parm["path"]["JEDI_BIN_PATH"] = jedi_bin_path
    config_parm["path"]["JEDI_IODACONV_PATH"] = jedi_iodaconv_path

    return config_parm


# ==================================================================== CHJ =====
def add_new_parm_ufs_model(config_parm):
    allcomp_restart_n = config_parm["parm"]["ALLCOMP_RESTART_N"]
    app = config_parm["parm"]["APP"]
    datm_data_type = config_parm["parm"]["DATM_DATA_TYPE"]
    dt_mom6 = config_parm["parm"]["DT_MOM6"]
    mom6_dt_therm = config_parm["parm"]["MOM6_DT_THERM"]
    output_fh = config_parm["parm"]["OUTPUT_FH"]
    output_fh_cice = config_parm["parm"]["OUTPUT_FH_CICE"]
    output_fh_lnd = config_parm["parm"]["OUTPUT_FH_LND"]
    output_fh_mom6 = config_parm["parm"]["OUTPUT_FH_MOM6"]
    output_fh_ww3 = config_parm["parm"]["OUTPUT_FH_WW3"]
    restart_interval = config_parm["parm"]["RESTART_INTERVAL"]

    # Set model components
    if app == "S2SWA":
        atm_model = "fv3"
        chm_model = ""
        ice_model = "cice6"
        lnd_model = ""
        ocn_model = "mom6"
        wav_model = "ww3"
    elif app == "S2SWAL":
        atm_model = "fv3"
        chm_model = "gocart"
        ice_model = "cice6"
        lnd_model = "noahmp"
        ocn_model = "mom6"
        wav_model = "ww3"
    elif app == "NG-GODAS":
        atm_model = "datm"
        chm_model = ""
        ice_model = "cice6"
        lnd_model = ""
        ocn_model = "mom6"
        wav_model = ""
    elif app == "ATM":
        atm_model = "fv3"
        chm_model = ""
        ice_model = ""
        lnd_model = ""
        ocn_model = ""
        wav_model = ""
    else:
        atm_model = ""
        chm_model = ""
        ice_model = ""
        lnd_model = ""
        ocn_model = ""
        wav_model = ""

    # Set DATM domain size
    if datm_data_type == "gfs":
        datm_nx_global = 3072
        datm_ny_global = 1536
    elif datm_data_type == "gefs":
        datm_nx_global = 1536
        datm_ny_global = 768
    elif datm_data_type == "cfsr":
        datm_nx_global = 1760
        datm_ny_global = 880

    # MOM6
    if mom6_dt_therm is None or mom6_dt_therm == "None":
        mom6_dt_therm = 2*dt_mom6

    # OUTPUT_FH_CICE: output frequency of CICE
    output_fh_list = list(map(int, output_fh.split()))
    if output_fh_cice is None or output_fh_cice == "None":
        if output_fh_list[1] == -1:
            output_fh_cice = output_fh_list[0]
        else:
            output_fh_cice = 6
            logging.warning(f''' OUTPUT_FH_CICE is not specified in config.yaml and OUTPU_FH[1] != -1; OUTPUT_FH_CICE is set to "{output_fh_cice}" by default.''')

    # OUTPUT_FH_LND: output frequency of LND
    if output_fh_lnd is None or output_fh_lnd == "None":
        output_fh_lnd = 6
        logging.warning(f''' OUTPUT_FH_LND is not specified in config.yaml; OUTPUT_FH_LND is set to "{output_fh_lnd}" by default.''')

    # OUTPUT_FH_MOM6: output frequency of MOM6
    if output_fh_mom6 is None or output_fh_mom6 == "None":
        if output_fh_list[1] == -1:
            if output_fh_list[0] % 2 == 0:
                output_fh_mom6 = output_fh_list[0]
            else:
                output_fh_mom6 = 6
                logging.warning(f''' OUTPUT_FH_MOM6 is not specified in config.yaml and OUTPU_FH[0] is not an even number; OUTPUT_FH_MOM6 is set to "{output_fh_mom6}" by default.''')
        else:
            output_fh_mom6 = 6
            logging.warning(f''' OUTPUT_FH_MOM6 is not specified in config.yaml and OUTPU_FH[1] != -1; OUTPUT_FH_MOM6 is set to "{output_fh_mom6}" by default.''')
    else:
        if output_fh_mom6 % 2 != 0:
            logging.error(f''' FATAL ERROR: OUTPUT_FH_MOM6 is set to "{output_fh_mom6}" in config.yaml, but it is not an even number.''')
            sys.exit(1)

    # OUTPUT_FH_WW3: output frequency of WW3 ("in hours"), note that this will be converted to seconds in script
    if output_fh_ww3 is None or output_fh_ww3 == "None":
        if output_fh_list[1] == -1:
            output_fh_ww3 = output_fh_list[0]
        else:
            output_fh_ww3 = 6
            logging.warning(f''' OUTPUT_FH_WW3 is not specified in config.yaml and OUTPU_FH[1] != -1; OUTPUT_FH_WW3 is set to "{output_fh_ww3} hours" by default.''')

    # ALLCOMP_RESTART_N: output frequency of mediator (CMEPS) restart files
    restart_interval_list = list(map(int, restart_interval.split()))
    if allcomp_restart_n is None or allcomp_restart_n == "None":
        if restart_interval_list[1] == -1:
            allcomp_restart_n = restart_interval_list[0]
        else:
            allcomp_restart_n = 12
            logging.warning(f''' ALLCOMP_RESTART_N is not specified in config.yaml and RESTART_INTERVAL[1] != -1; ALLCOMP_RESTART_N is set to "{allcomp_restart_n}" by default.''')

    config_parm["parm"]["ALLCOMP_RESTART_N"] = allcomp_restart_n
    config_parm["parm"]["atm_model"] = atm_model
    config_parm["parm"]["chm_model"] = chm_model
    config_parm["parm"]["datm_nx_global"] = datm_nx_global
    config_parm["parm"]["datm_ny_global"] = datm_ny_global
    config_parm["parm"]["ice_model"] = ice_model
    config_parm["parm"]["lnd_model"] = lnd_model
    config_parm["parm"]["MOM6_DT_THERM"] = mom6_dt_therm
    config_parm["parm"]["ocn_model"] = ocn_model
    config_parm["parm"]["OUTPUT_FH_CICE"] = output_fh_cice
    config_parm["parm"]["OUTPUT_FH_LND"] = output_fh_lnd
    config_parm["parm"]["OUTPUT_FH_MOM6"] = output_fh_mom6
    config_parm["parm"]["OUTPUT_FH_WW3"] = output_fh_ww3
    config_parm["parm"]["wav_model"] = wav_model

    return config_parm


# ==================================================================== CHJ =====
def check_valid_parm(home_dir,config_parm):
    # Check whether exec dir is empty
    exec_dir = os.path.join(home_dir, 'exec')
    exec_path = Path(exec_dir)
    fix_dir = os.path.join(home_dir, 'fix')
    fix_path = Path(fix_dir)
    if not exec_path.exists():
        logging.error(f''' exec directory "{exec_path}" does NOT exist. You might skip the build step !!!''')
        sys.exit(1)        
    else:
        visible_files = [p for p in fix_path.iterdir() if not p.name.startswith(".")]
        if not visible_files:
            logging.error(f''' fix directory "{fix_path}" is EMPTY. Please check the link in the build script !!!''')
            sys.exit(1)

    # Check lowercase/uppercase
    datm_data_type_orig = config_parm["parm"]["DATM_DATA_TYPE"]
    datm_data_type = datm_data_type_orig.lower()
    config_parm["parm"]["DATM_DATA_TYPE"] = datm_data_type

    type_anal_fcst_orig = config_parm["parm"]["TYPE_ANAL_FCST"]
    type_anal_fcst_options = ["both", "anal-only", "fcst-only", "fcst-1st", "ctest"]
    err_msg = f''' FATAL ERROR: NOT available 'TYPE_ANAL_FCST': {type_anal_fcst_orig}, options = {type_anal_fcst_options} !!!'''
    if isinstance(type_anal_fcst_orig, bool):
        logging.error(err_msg)
        sys.exit(1)
    elif not type_anal_fcst_orig.islower():
        type_anal_fcst = type_anal_fcst_orig.lower()
        logging.info(f''' 'TYPE_ANAL_FCST: {type_anal_fcst_orig}': converted to lowercase! ''')
    else:
        type_anal_fcst = type_anal_fcst_orig
    config_parm["parm"]["TYPE_ANAL_FCST"] = type_anal_fcst

    if type_anal_fcst not in type_anal_fcst_options:
        logging.error(err_msg)
        sys.exit(1)

    # Check for unsupported conditions
    jedi_type_snow = config_parm["flag"]["JEDI_TYPE_SNOW"]
    jedi_type_soca = config_parm["flag"]["JEDI_TYPE_SOCA"]
    jedi_type_soil_moisture = config_parm["flag"]["JEDI_TYPE_SOIL_MOISTURE"]
    obs_snow_ghcn = config_parm["flag"]["OBS_SNOW_GHCN"]
    obs_snow_ims = config_parm["flag"]["OBS_SNOW_IMS"]
    obs_snow_sfcsno = config_parm["flag"]["OBS_SNOW_SFCSNO"]
    obs_swc_smap = config_parm["flag"]["OBS_SWC_SMAP"]
    obs_swc_smops = config_parm["flag"]["OBS_SWC_SMOPS"]
    if obs_snow_ghcn == "YES" and obs_snow_ims == "YES":
        logging.error("FATAL ERROR: Both OBS_SNOW_GHCN and OBS_SNOW_IMS are selected, but this is not supported by JCB!!!", exc_info=True)
        sys.exit(1)
    elif obs_swc_smap == "YES" and obs_swc_smops == "YES":
        logging.error("FATAL ERROR: Both OBS_SWC_SMAP and OBS_SWC_SMOPS are selected, but this is not supported!!!", exc_info=True)
        sys.exit(1)

    if type_anal_fcst == "both" or type_anal_fcst == "anal-only":
        if jedi_type_snow == "NO" and jedi_type_soil_moisture == "NO" and jedi_type_soca == "NO":
            logging.error(f'''FATAL ERROR: All JEDI_TYPE flags are off. Please check the flags for JEDI_TYPE.''')
            sys.exit(1)

        if jedi_type_snow == "YES" and \
           (obs_snow_ghcn == "NO" and obs_snow_ims == "NO" and obs_snow_sfcsno == "NO"):
            logging.error(f'''FATAL ERROR: JEDI_TYPE_SNOW = "YES", but all snow observation options are off !!!''')
            sys.exit(1)
        elif jedi_type_snow == "NO" and \
           (obs_snow_ghcn == "YES" or obs_snow_ims == "YES" or obs_snow_sfcsno == "YES"):
            logging.error(f'''FATAL ERROR: JEDI_TYPE_SNOW = "NO", but snow observations are on: GHCN ({obs_snow_ghcn}), IMS (${obs_snow_ims}), SFCSNO (${obs_snow_sfcsno}) !!!''')
            sys.exit(1)
    
        if jedi_type_soil_moisture == "YES" and (obs_swc_smap == "NO" and obs_swc_smops == "NO"):
            logging.error(f'''FATAL ERROR: JEDI_TYPE_SOIL_MOISTURE = "YES", but all soil moisture observation options are off !!!''')
            sys.exit(1)
        elif jedi_type_soil_moisture == "NO" and (obs_swc_smap == "YES" or obs_swc_smops == "YES"):
            logging.error(f'''FATAL ERROR: JEDI_TYPE_SOIL_MOISTURE = "NO", but soil moisture observations are on: SMAP ({obs_swc_smap}) and SMOPS ({obs_swc_smops})!!!''')
            sys.exit(1)
  
    # Print out final configuration to experimental case dir
    exp_case_path = config_parm["path"]["exp_case_path"]
    with open(os.path.join(exp_case_path,"config_final.yaml"), "w") as f:
        yaml.dump(config_parm, f, sort_keys=True, default_flow_style=False)

    return config_parm


# ==================================================================== CHJ =====
def create_jobcard_envvar(home_dir,parm_dir,config_parm,config_parm_str):
    exp_case_path = config_parm["path"]["exp_case_path"]
    ptmp = config_parm["path"]["PTMP"]
    account = config_parm["parm"]["ACCOUNT"]
    envir = config_parm["parm"]["envir"]
    date_first_cycle = config_parm["parm"]["DATE_FIRST_CYCLE"]
    machine = config_parm["parm"]["MACHINE"]
    memory_flag = config_parm["parm"]["memory_flag"]
    native = config_parm["parm"]["NATIVE"]
    partition_queue = config_parm["parm"]["PARTITION_QUEUE"]
    qos = config_parm["parm"]["QOS"]
    sched = config_parm["parm"]["SCHED"]
    workflow_manager = config_parm["parm"]["WORKFLOW_MANAGER"]

    pdy_cdate = str(date_first_cycle)[:8]
    cyc_cdate = str(date_first_cycle)[-2:]

    env_fp = os.path.join(exp_case_path,"task_env")
    os.mkdir(env_fp)
    # list of tasks based on template files
    tenv_path = os.path.join(parm_dir,"templates/task_env")
    prefix = "template."
    suffix = ".env"
    tasks = []
    for fn in os.listdir(tenv_path):
        if fn.startswith(prefix) and fn.endswith(suffix) and os.path.isfile(os.path.join(tenv_path,fn)):
            task_name = fn[len(prefix):-len(suffix)]
            tasks.append(task_name)
    tasks = sorted(tasks)
    logging.info(f''' Task env files: {tasks}''')

    # Create task-specific env files from template
    for itask in tasks:
        fn_env_template = f'''{prefix}{itask}{suffix}'''
        fn_env = f'''{itask}{suffix}'''
        fp_env_template = os.path.join(tenv_path,fn_env_template)
        fp_env = os.path.join(env_fp,fn_env)
        try:
            fill_jinja_template([
                "-q",
                "-u", config_parm_str,
                "-t", fp_env_template,
                "-o", fp_env ])
        except:
            logging.error(f''' FATAL ERROR: Call to python script fill_jinja_template.py
                  to create a '{fp_env}' file from a jinja2 template failed.''')
            sys.exit(1)
        logging.info(f''' Task env file: {fn_env} created''')

    # Create job cards from template
    fn_jcard_template = "template.jobcard_task"
    fp_jcard_template = os.path.join(parm_dir,"templates",fn_jcard_template)
    if not os.path.exists(fp_jcard_template):
        logging.error(f'''Job card template {fp_jcard_template} does NOT exist''')
        sys.exit(1)

    if workflow_manager == "ecflow":
        ecf_suite_family_name = "ecf_scripts"
        jcard_fp = os.path.join(exp_case_path,"ecf",ecf_suite_family_name)
        jcard_suffix = ".ecf"
    else:
        jcard_fp = os.path.join(exp_case_path,"job_cards")
        jcard_suffix = ""
    os.makedirs(jcard_fp)

    ## HPC variable mapping for directives
    varmap_hpc = {
        "memory_per_node_analysis": config_parm["parm"]["MEMORY_PER_NODE_ANALYSIS"],
        "memory_per_node_fcst_ic": config_parm["parm"]["MEMORY_PER_NODE_FCST_IC"],
        "memory_per_node_forecast": config_parm["parm"]["MEMORY_PER_NODE_FORECAST"],
        "memory_per_node_plot_stats": config_parm["parm"]["MEMORY_PER_NODE_PLOT_STATS"],
        "memory_per_node_prep_data": config_parm["parm"]["MEMORY_PER_NODE_PREP_DATA"],
        "nnodes_analysis": config_parm["parm"]["nnodes_analysis"],
        "nnodes_fcst_ic": config_parm["parm"]["nnodes_fcst_ic"],
        "nnodes_forecast": config_parm["parm"]["nnodes_forecast"],
        "nnodes_plot_stats": config_parm["parm"]["nnodes_plot_stats"],
        "nnodes_prep_data": config_parm["parm"]["nnodes_prep_data"],
        "nprocs_per_node_analysis": config_parm["parm"]["nprocs_per_node_analysis"],
        "nprocs_per_node_fcst_ic": config_parm["parm"]["nprocs_per_node_fcst_ic"],
        "nprocs_per_node_forecast": config_parm["parm"]["nprocs_per_node_forecast"],
        "nprocs_per_node_plot_stats": config_parm["parm"]["nprocs_per_node_plot_stats"],
        "nprocs_per_node_prep_data": config_parm["parm"]["nprocs_per_node_prep_data"],
        "walltime_analysis": config_parm["parm"]["WALLTIME_ANALYSIS"],
        "walltime_fcst_ic": config_parm["parm"]["WALLTIME_FCST_IC"],
        "walltime_forecast": config_parm["parm"]["WALLTIME_FORECAST"],
        "walltime_plot_stats": config_parm["parm"]["WALLTIME_PLOT_STATS"],
        "walltime_prep_data": config_parm["parm"]["WALLTIME_PREP_DATA"],
    }
     
    ## Create job cards for tasks
    log_dir_path = os.path.join(ptmp,envir,"com/output/logs")
    os.makedirs(log_dir_path)
    for itask in tasks:
        memory_per_node_task = f'''memory_per_node_{itask}'''
        nnodes_task = f'''nnodes_{itask}'''
        nprocs_per_node_task = f'''nprocs_per_node_{itask}'''
        walltime_task = f'''walltime_{itask}'''
        if workflow_manager == "ecflow":
            output_fn = f'''{itask}_%ECF_DATE%%CYC%_%ECF_TRYNO%.log'''
        else:
            output_fn = f'''{itask}_{date_first_cycle}.log'''
        output_name = os.path.join(log_dir_path,output_fn)
        data_set = {
            "ACCOUNT": account,
            "cyc_cdate": cyc_cdate,
            "exp_case_path": exp_case_path,
            "HOMEufsda": home_dir,
            "MACHINE": machine,
            "memory_flag": memory_flag,
            "memory_per_node": varmap_hpc[memory_per_node_task],
            "NATIVE": native,
            "nnodes": varmap_hpc[nnodes_task],
            "nprocs_per_node": varmap_hpc[nprocs_per_node_task],
            "output_name": output_name,
            "partition_queue": partition_queue,
            "pdy_cdate": pdy_cdate,
            "qos": qos,
            "SCHED": sched,
            "task_name": itask,
            "walltime": varmap_hpc[walltime_task],
            "WORKFLOW_MANAGER": workflow_manager,
        }
        data_set_str = yaml.dump(data_set, sort_keys=True)
        logging.debug(f''' Data for {itask}: {data_set_str}''')
        fn_jcard = f'''jufsda_{itask}{jcard_suffix}'''
        fp_jcard = os.path.join(jcard_fp,fn_jcard)
        try:
            fill_jinja_template([
                "-q",
                "-u", data_set_str,
                "-t", fp_jcard_template,
                "-o", fp_jcard ])
        except:
            logging.error(f''' FATAL ERROR: Call to python script fill_jinja_template.py
                  to create a '{fp_jcard}' file from a jinja2 template failed.''')
            sys.exit(1)
        os.chmod(fp_jcard, 0o755)
        logging.info(f''' Job card for {itask} created''')


# ==================================================================== CHJ =====
def create_ecflow_files(home_dir,config_parm):
    coldstart = config_parm["flag"]["COLDSTART"]
    ic_from_fix_dir = config_parm["flag"]["IC_FROM_FIX_DIR"]
    exp_basedir = config_parm["path"]["exp_basedir"]
    exp_case_path = config_parm["path"]["exp_case_path"]
    exp_case_name = config_parm["parm"]["EXP_CASE_NAME"]
    date_cycle_freq_hr = config_parm["parm"]["DATE_CYCLE_FREQ_HR"]
    date_first_cycle = config_parm["parm"]["DATE_FIRST_CYCLE"]
    date_last_cycle = config_parm["parm"]["DATE_LAST_CYCLE"]
    date_second_cycle = config_parm["parm"]["date_second_cycle"]
    sched = config_parm["parm"]["SCHED"]
    type_anal_fcst = config_parm["parm"]["TYPE_ANAL_FCST"]

    date_cycle_freq_day = date_cycle_freq_hr // 24
    yyyymmdd_first = str(date_first_cycle)[:8]
    hh_first = str(date_first_cycle)[-2:]
    if date_second_cycle is None or date_second_cycle == "None":
        yyyymmdd_second = date_second_cycle
    else:
        yyyymmdd_second = str(date_second_cycle)[:8]
    yyyymmdd_last = str(date_last_cycle)[:8]
    hh_last = str(date_last_cycle)[-2:]

    # ecFlow server directory
    exp_ecf_path = os.path.join(exp_basedir, "exp_case/ecf_server")
    if not os.path.exists(exp_ecf_path):
        os.makedirs(exp_ecf_path)
        # ecFlow server control scripts
        data_set = {
            "exp_case_name": exp_case_name,
            "exp_case_path": exp_case_path,
            "exp_ecf_path": exp_ecf_path,
        }
        data_set_str = yaml.dump(data_set, sort_keys=True)
        logging.debug(f''' Data for ecFlow server scripts: {data_set_str}''')
        ## start_server
        fn_ecf_template = "template.start_server.sh"
        fp_ecf_template = os.path.join(home_dir,"ecf",fn_ecf_template)
        fn_ecf = f'''start_server.sh'''
        fp_ecf = os.path.join(exp_ecf_path,fn_ecf)
        try:
            fill_jinja_template([
                "-q",
                "-u", data_set_str,
                "-t", fp_ecf_template,
                "-o", fp_ecf ])
        except:
            logging.error(f''' FATAL ERROR: Call to python script fill_jinja_template.py
                  to create a '{fp_ecf}' file from a jinja2 template failed.''')
            sys.exit(1)
        os.chmod(fp_ecf, 0o755)
        ## Copy stop_server script to exp_case_path
        source_fp = os.path.join(home_dir,"ecf/stop_server.sh")
        try:
            shutil.copy(source_fp,exp_ecf_path)
            logging.info(f'''File '{source_fp}' copied successfully to '{exp_ecf_path}'.''')
        except FileNotFoundError:
            logging.error(f'''FATAL ERROR: Source file '{source_fp}' not found.''')
        except Exception as e:
            logging.error(f'''FATAL ERROR: An error occurred: {e}''')
        ## Copy files in ecf/include to ecf_server
        source_dir = os.path.join(home_dir,"ecf/include")
        try:
            shutil.copytree(source_dir, exp_ecf_path, dirs_exist_ok=True)
            logging.info(f'''All files from '{source_dir}' copied to '{exp_ecf_path}' successfully.''')
        except shutil.Error as e:
            logging.error(f'''FATAL ERROR: Error copying directory: {e}''')

    # ecFlow case-specific files
    ## Definition file
    data_set = {
        "COLDSTART": coldstart,
        "date_cycle_freq_day": date_cycle_freq_day,
        "date_second_cycle": date_second_cycle,
        "exp_case_name": exp_case_name,
        "exp_case_path": exp_case_path,
        "hh_first": hh_first,
        "hh_last": hh_last,
        "IC_FROM_FIX_DIR": ic_from_fix_dir,
        "SCHED": sched,
        "TYPE_ANAL_FCST": type_anal_fcst,
        "yyyymmdd_first": yyyymmdd_first,
        "yyyymmdd_second": yyyymmdd_second,
        "yyyymmdd_last": yyyymmdd_last,
    }
    data_set_str = yaml.dump(data_set, sort_keys=True)
    logging.debug(f''' Data for ecFlow def file: {data_set_str}''')
    if type_anal_fcst == "fcst-only" and date_cycle_freq_hr < 24:
        fn_ecf_template = "template.ufsda.def_1d2c"
    else:
        fn_ecf_template = "template.ufsda.def"
    fp_ecf_template = os.path.join(home_dir,"ecf/defs",fn_ecf_template)
    fn_ecf = f'''{exp_case_name}.def'''
    fp_ecf = os.path.join(exp_case_path,"ecf",fn_ecf)
    try:
        fill_jinja_template([
            "-q",
            "-u", data_set_str,
            "-t", fp_ecf_template,
            "-o", fp_ecf ])
    except:
        logging.error(f''' FATAL ERROR: Call to python script fill_jinja_template.py
              to create a '{fp_ecf}' file from a jinja2 template failed.''')
        sys.exit(1)
    ## Suite begin script
    fn_ecf_template = "template.begin_suite.sh"
    fp_ecf_template = os.path.join(home_dir,"ecf",fn_ecf_template)
    fn_ecf = f'''begin_suite.sh'''
    fp_ecf = os.path.join(exp_case_path,"ecf",fn_ecf)
    try:
        fill_jinja_template([
            "-q",
            "-u", data_set_str,
            "-t", fp_ecf_template,
            "-o", fp_ecf ])
    except:
        logging.error(f''' FATAL ERROR: Call to python script fill_jinja_template.py
              to create a '{fp_ecf}' file from a jinja2 template failed.''')
        sys.exit(1)
    os.chmod(fp_ecf, 0o755)
    ## Suite control script
    fn_ecf_template = "template.control_suite.sh"
    fp_ecf_template = os.path.join(home_dir,"ecf",fn_ecf_template)
    fn_ecf = f'''control_suite.sh'''
    fp_ecf = os.path.join(exp_case_path,"ecf",fn_ecf)
    try:
        fill_jinja_template([
            "-q",
            "-u", data_set_str,
            "-t", fp_ecf_template,
            "-o", fp_ecf ])
    except:
        logging.error(f''' FATAL ERROR: Call to python script fill_jinja_template.py
              to create a '{fp_ecf}' file from a jinja2 template failed.''')
        sys.exit(1)
    os.chmod(fp_ecf, 0o755)


# ==================================================================== CHJ =====
def create_xml_extra(parm_dir,config_parm,config_parm_str):
    coldstart = config_parm["flag"]["COLDSTART"]
    exp_case_path = config_parm["path"]["exp_case_path"]
    date_first_cycle = config_parm["parm"]["DATE_FIRST_CYCLE"]

    # Create YAML file for Rocoto XML from template
    fn_yaml_rocoto_template = "template.rocoto_xml_file.yaml"
    fn_yaml_rocoto = "rocoto_xml_file.yaml"
    fp_yaml_rocoto_template = os.path.join(parm_dir, "templates", fn_yaml_rocoto_template)
    fp_yaml_rocoto = os.path.join(exp_case_path, fn_yaml_rocoto)
    logging.info(f''' Rocoto YAML template: {fp_yaml_rocoto_template}''')
    try:
        fill_jinja_template([
            "-q",
            "-u", config_parm_str,
            "-t", fp_yaml_rocoto_template,
            "-o", fp_yaml_rocoto ])
    except:
        logging.error(f''' FATAL ERROR: Call to python script fill_jinja_template.py 
              to create a '{fp_yaml_rocoto}' file from a jinja2 template failed.''')
        return False

    # Create Rocoto XML file
    fn_xml_rocoto = "ufsda_rocoto.xml"
    fp_xml_rocoto = os.path.join(exp_case_path, fn_xml_rocoto)
    realize(
        config = fp_yaml_rocoto,
        output_file = fp_xml_rocoto,
        )

    # Create rocoto launch file to exp_case directory
    fn_launch_template = "template.launch_rocoto_wflow.sh"
    fn_launch_script = "launch_rocoto_wflow.sh"
    fp_launch_template = os.path.join(parm_dir, "templates", fn_launch_template)
    fp_launch_script = os.path.join(exp_case_path, fn_launch_script)
    shutil.copyfile(fp_launch_template, fp_launch_script)
    with open(fp_launch_script, 'r') as file:
        fdata = file.read()
    fdata = fdata.replace('{{ parm_dir }}', parm_dir)
    fdata = fdata.replace('{{ fn_xml_rocoto }}', fn_xml_rocoto)
    fdata = fdata.replace('{{ exp_case_path }}', exp_case_path)
    with open(fp_launch_script, 'w') as file:
        file.write(fdata)
    os.chmod(fp_launch_script, 0o755)

    # Copy the automated launch script to exp_case directory
    fn_auto_launch_py = "automate_launch_script.py"
    fp_auto_script_orig = os.path.join(parm_dir, fn_auto_launch_py)
    fp_auto_script_expt = os.path.join(exp_case_path, fn_auto_launch_py)
    shutil.copyfile(fp_auto_script_orig, fp_auto_script_expt)
    os.chmod(fp_auto_script_expt, 0o755)

    # Create coldstart txt file for 1st cycle only for cold start
    if coldstart == "YES":
        fn_pass = f"task_skip_coldstart_{date_first_cycle}.txt"
        open(os.path.join(exp_case_path,fn_pass), 'a').close()

    # Create first cycle txt file to trigger 1st task in 1st cycle
    fn_pass = f"task_run_firstcyc_{date_first_cycle}.txt"
    open(os.path.join(exp_case_path,fn_pass), 'a').close()


# ==================================================================== CHJ =====
def create_symlinks_dirs(parm_dir,config_parm):
    exp_case_path = config_parm["path"]["exp_case_path"]
    ptmp = config_parm["path"]["PTMP"]
    envir = config_parm["parm"]["envir"]
    model_ver = config_parm["parm"]["model_ver"]
    net = config_parm["parm"]["NET"]

    # Add links to log/tmp/com directories within exp_case directory
    log_dir_src = os.path.join(ptmp, envir, "com/output/logs")
    log_dir_dst = os.path.join(exp_case_path, "log_dir")
    tmp_dir_src = os.path.join(ptmp, envir, "tmp")
    tmp_dir_dst = os.path.join(exp_case_path, "tmp_dir")
    com_dir_src = os.path.join(ptmp, envir, "com", net, model_ver)
    com_dir_dst = os.path.join(exp_case_path, "com_dir")
    os.symlink(log_dir_src, log_dir_dst)
    os.symlink(tmp_dir_src, tmp_dir_dst)
    os.symlink(com_dir_src, com_dir_dst)


# Machine-specific values of configuration ========================== CHJ =====
def set_machine_parm(machine):
    lowercase_machine = machine.lower()
    match lowercase_machine:
        case "derecho":
            MAX_CORES_PER_NODE = 128
            NATIVE = None
            PARTITION_QUEUE = "main"
            QOS = None
            RUN_CMD = "aprun"
            SCHED = "pbspro"
        case "gaeac6":
            MAX_CORES_PER_NODE = 192
            NATIVE = '-M c6'
            PARTITION_QUEUE = "batch"
            QOS = "normal"
            RUN_CMD = "srun"
            SCHED = "slurm"
        case "hercules":
            MAX_CORES_PER_NODE = 80
            NATIVE = None
            PARTITION_QUEUE = "hercules"
            QOS = "batch"
            RUN_CMD = "srun"
            SCHED = "slurm"
        case "orion":
            MAX_CORES_PER_NODE = 40
            NATIVE = None
            PARTITION_QUEUE = "orion"
            QOS = "batch"
            RUN_CMD = "srun"
            SCHED = "slurm"
        case "ursa":
            MAX_CORES_PER_NODE = 192
            NATIVE = None
            PARTITION_QUEUE = "u1-compute"
            QOS = "batch"
            RUN_CMD = "srun"
            SCHED = "slurm"
        case _:
            sys.exit(f"FATAL ERROR: this machine/platform '{lowercase_machine}' is NOT supported yet !!!")

    machine_config = {
        'parm':{
            "MAX_CORES_PER_NODE": MAX_CORES_PER_NODE,
            "NATIVE": NATIVE,
            "PARTITION_QUEUE": PARTITION_QUEUE,
            "QOS": QOS,
            "RUN_CMD": RUN_CMD,
            "SCHED": SCHED,
        }
    }

    return machine_config


# Merge dictionaries ================================================ CHJ =====
def merge_dicts(a, b):
    """Recursively merge dictionary b into dictionary a."""
    for key, value in b.items():
        if (
            key in a
            and isinstance(a[key], dict)
            and isinstance(value, dict)
        ):
            merge_dicts(a[key], value)
        else:
            a[key] = value
    return a


# Parse arguments =================================================== CHJ =====
def parse_args(argv):
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(description="Generate case-specific workflow environment.")

    parser.add_argument(
            "-p", "--platform",
            dest="MACHINE",
            help="Platform (machine) name.",
            )
    parser.add_argument(
            "-l", "--loglevel",
            dest="PY_LOG_LEVEL",
            default="INFO",
            help="Python logging option only for this script. For other scripts, set it in config.yaml",
            )

    return parser.parse_args(argv)


# Detect platform (machine) ========================================= CHJ =====
def detect_platform():
    if os.path.isdir("/scratch3/NAGAPE"):
        machine = "ursa"
    elif os.path.isdir("/work/noaa"):
        machine = socket.gethostname().split('-')[0]  # orion/hercules
    elif os.path.isdir("/ncrc"):
        machine_number = socket.gethostname()[4]
        machine = f"gaeac{machine_number}"
    elif os.path.isdir("/glade"):
        machine = "derecho"
    else:
        sys.exit(f''' FATAL ERROR: Machine (platform) is not detected. Please set it with -p argument!!!''')

    logging.info(f''' Machine (platform) detected: {machine}''')

    return machine


# Main call ========================================================= CHJ =====
if __name__=='__main__':
    args = parse_args(sys.argv[1:])
    log_level_str = args.PY_LOG_LEVEL.upper()
    try:
        log_level = getattr(logging, log_level_str)
    except AttributeError:
        log_level_str = "INFO"
        log_level = logging.INFO
        print(f''' WARNING: Invalid log level "{args.PY_LOG_LEVEL.upper()}", set to INFO.''')
    print(f''' Python Log Level= str: {log_level_str}, attr: {log_level}''')
    logging.basicConfig(format='%(levelname)s::%(pathname)s::L%(lineno)d::%(message)s', level=log_level)
    MACHINE=args.MACHINE
    if MACHINE is None:
        MACHINE = detect_platform()
   
    setup_wflow_env(MACHINE)

