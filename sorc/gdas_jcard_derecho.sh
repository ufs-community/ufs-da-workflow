#PBS -S /bin/bash
#PBS -A nral0032
#PBS -N gdas_build
#PBS -o gdas_build.log
#PBS -j oe
#PBS -q main
#PBS -l walltime=00:45:00
#PBS -l select=1:ncpus=8:mpiprocs=8
#PBS -l place=vscatter

export BUILD_JOBS="8"
export WORKFLOW_BUILD="ON"
export WORKFLOW_TESTS="OFF"

cd {{ HOME_DIR }}/sorc/GDASApp.cd
./build.sh -f -t derecho -w {{ HOME_DIR }}
