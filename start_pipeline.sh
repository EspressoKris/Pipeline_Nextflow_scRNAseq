#!/bin/bash
#SBATCH --job-name=nf_single_cell_pipeline
#SBATCH --output=Report-%x.%j.out
#SBATCH --error=Report-%x.%j.err
#SBATCH --time=144:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --partition=long
#SBATCH --mail-type=BEGIN,END,FAIL
#SBATCH --mail-user=kristian.gurashi@ndcls.ox.ac.uk

module load nextflow/25.04.7

PIPELINE_DIR="/project/ANGEL/shared/Pipeline"
LOCAL_DIR="/tmp/${USER}/nf_run_${SLURM_JOB_ID}"

mkdir -p ${LOCAL_DIR}
cd ${LOCAL_DIR}

nextflow run ${PIPELINE_DIR}/main.nf \
    -resume \
    -w ${PIPELINE_DIR}/work

# Copy .nextflow.log back for debugging
cp -f ${LOCAL_DIR}/.nextflow.log ${PIPELINE_DIR}/.nextflow.log 2>/dev/null

# Clean up local temp
rm -rf ${LOCAL_DIR}