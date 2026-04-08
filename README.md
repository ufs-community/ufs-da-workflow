# ufs-da-workflow
UFS DA (Data Assimilation) Workflow: UFS Weather Model + JCSDA JEDI
- Available coupling configurations in UFS Weather Model:
 1. S2SWA: ATM (FV3+CCPP) + OCN (MOM6) + ICE (CICE) + WAV (WW3) + CHM (GOCART)
 2. S2SWAL: ATM (FV3+CCPP) + OCN (MOM6) + ICE (CICE) + WAV (WW3) + CHM (GOCART) + LND (Noah-MP)
 3. NG-GODAS: ATM (DATM) + OCN (MOM6) + ICE (CICE)
 4. ATML: ATM (FV3+CCPP) + LND (Noah-MP)
 5. ATM: ATM (FV3+CCPP) stand-alone

## Quick Start Guide

1. Clone the `develop` branch of the authoritative repository:
```
git clone -b develop --recursive https://github.com/ufs-community/ufs-da-workflow
```

2. Move to the `sorc` directory:
```
cd ufs-da-workflow/sorc
```

3. Run the build script:
- Workflow components: YES, JEDI-bundle: NO
```
./app_build.sh -a=[APP]
```
where `[APP]` is `S2SWA`, `S2SWAL`, `NG-GODAS`, `ATML`, or `ATM`.

- Workflow components: YES, JEDI-bundle: YES
```
./app_build.sh -a=[APP] --jedi=bundle
```

- Workflow components: NO, JEDI-bundle: YES
```
./app_build.sh --jedi=bundle-only
```

- Workflow components: YES, GDAS App: YES
```
./app_build.sh -a=[APP] --jedi=gdas
```

- Workflow components: NO, GDAS App: YES
```
./app_build.sh --jedi=gdas-only
```

4. Load the python environment to set up the workflow:
```
cd ..
module use modulefiles
module load wflow_[workflow_manager]_[machine] 
```
where `[workflow_manager]` is `ecflow`, `rocoto`, or `none`, and `[machine]` is `gaeac6`, `hercules`, `orion`, `ursa`, or `derecho`.

5. Copy a sample configuration and modify it as needed:
```
cd parm
cp config_samples/config.[sample_case].yaml config.yaml
vim config.yaml
```
Change the parameter values such as `ACCOUNT` as needed.

6. Set up the workflow in the case-specific experiment directory:
```
./setup_wflow_env.py
```

7. Launch the workflow tasks:
- WORKFLOW_MANAGER: ecflow
```
cd ../../exp_case/ecf_server
./start_server.sh
cd ../[EXP_CASE_NAME]/ecf
./begin_suite.sh
ecflow_ui &
```
where `[EXP_CASE_NAME]` is specified in the configuration file `config.yaml`.

- WORKFLOW_MANAGER: rocoto
```
cd ../../exp_case/[EXP_CASE_NAME]
./automate_launch_script.py -i [time interval in seconds]
```
where the default value of `[time interval in seconds]` is 30. This means that the launch script `launch_rocoto_wflow.sh` is submitted every 30 seconds.

8. Check the result and log files:
- `com_dir`: symlink to the directory containing the result files
- `log_dir`: symlink to the directory containing the log files
- `tmp_dir`: symlink to the directory containing the working directories
