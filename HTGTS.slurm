#!/bin/bash -l
#SBATCH --job-name=htgts_ikzf1
#SBATCH --output=logs/htgts_ikzf1.%j.out
#SBATCH --error=logs/htgts_ikzf1.%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=1-00:00:00
#SBATCH --partition=compute
#SBATCH --account=lab_dovat

set -euo pipefail

mkdir -p logs   # relative to submission dir, needed for #SBATCH --output/--error paths above

echo "Job started on $(hostname) at $(date)"
echo "Job ID: $SLURM_JOB_ID"

# ---- Environment setup ----
# Conda's activate.d scripts (e.g. binutils_linux-64) reference variables that
# may be unset, which trips "set -u" above. Relax it just for activation, then restore.
set +u
source ~/miniconda3/etc/profile.d/conda.sh
conda activate htgs_env
set -u

# Make sure system perl module is NOT loaded (caused Text::CSV failure earlier)
module unload perl 2>/dev/null || true

# Pipeline paths
export PIPELINE_DIR=/gpfs/Scratch/DovatLab/2025_9_LAM_HTGTS/YDLAM/transloc_pipeline
export PATH=$PIPELINE_DIR/bin:$PATH

# Genome reference env vars (already confirmed working)
export GENOME_DB=/gpfs/Scratch/DovatLab/2025_9_LAM_HTGTS/YDLAM/Hg38
export BOWTIE2_INDEXES=/gpfs/Scratch/DovatLab/2025_9_LAM_HTGTS/YDLAM/Hg38

# Run paths
DATADIR=/gpfs/Scratch/DovatLab/2025_9_LAM_HTGTS/YDLAM
RUNDIR=/gpfs/Home/bxp5423/YDLAM/rerun_20260706

echo "Using perl: $(which perl)"
perl -v | head -2
echo "GENOME_DB=$GENOME_DB"
echo "BOWTIE2_INDEXES=$BOWTIE2_INDEXES"

# ---- Sanity checks before launching (fail fast rather than mid-run) ----
test -f "$RUNDIR/metadata_run.tsv" || { echo "ERROR: metadata_run.tsv not found"; exit 1; }
test -d "$RUNDIR/preprocess" || { echo "ERROR: preprocess/ not found — did Step 4 complete?"; exit 1; }

mkdir -p "$RUNDIR/results" "$RUNDIR/logs"

# ---- Run the wrapper ----
# --threads here = number of LIBRARIES run simultaneously, not bowtie2 threads per library.
# With 8 cpus-per-task allocated above, we run 2 libraries at a time, each getting
# 4 internal threads via TranslocPipeline.pl's own --pipeline-opt "--threads 4".
# (2 libs x 4 threads = 8 cpus, matches --cpus-per-task above)
TranslocWrapper.pl "$RUNDIR/metadata_run.tsv" "$RUNDIR/preprocess/" "$RUNDIR/results/" \
  --threads 2 \
  --pipeline-opt "--threads 4" \
  2>&1 | tee "$RUNDIR/logs/wrapper_${SLURM_JOB_ID}.log"

echo "Job finished at $(date)"

# ---- Quick post-run summary ----
echo "=== TLX file counts per library ==="
find "$RUNDIR/results" -name "*.tlx" -exec sh -c 'echo "{}: $(wc -l < "{}") lines"' \;
