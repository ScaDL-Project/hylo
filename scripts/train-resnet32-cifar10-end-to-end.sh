#!/bin/bash

# Wait for prolog to finish
echo "Wait 3s..."
sleep 3
echo "done"

PRELOAD="singularity exec --bind $SCRATCH/hylo:$HOME,$SCRATCH/imagenet --nv artifact_init.sif "

# Args of training script
CMD="main-dist-classification.py --freq 13 --dataset cifar10 --data-dir $SCRATCH/cifar10 --batch-size 128 --model resnet32 --epochs 100 --warmup-epochs 5 --milestone 35 75 90 --lr 1.8 --lr-decay 0.3 --damping 1.5 --target-damping 0.1 --damping-decay-epochs 90 --weight-decay 0.00045 --checkpoint-freq 90 --adaptive 10 35 40 --log-dir resnet32-cifar10-end-to-end $@"

# Distributed system configuration
if [[ -z "${NODEFILE}" ]]; then
    if [[ -n "${SLURM_NODELIST}" ]]; then
        NODEFILE=/tmp/cifar10_slurm_nodelist
        scontrol show hostnames $SLURM_NODELIST > $NODEFILE
    elif [[ -n "${COBALT_NODEFILE}" ]]; then
        NODEFILE=$COBALT_NODEFILE
    fi
fi
if [[ -z "${NODEFILE}" ]]; then
    RANKS=$HOSTNAME
    NNODES=1
else
    MAIN_RANK=$(head -n 1 $NODEFILE)
    RANKS=$(tr '\n' ' ' < $NODEFILE)
    NNODES=$(< $NODEFILE wc -l)
fi

# Torch distributed launcher
LAUNCHER="python -m torch.distributed.launch "
LAUNCHER+="--nnodes=$NNODES --nproc_per_node=8"

FULL_CMD="$PRELOAD $LAUNCHER $CMD"
echo "Training command: $FULL_CMD"

# Launch the pytorch processes on each worker (use ssh for remote nodes)
RANK=0
for NODE in $RANKS; do
    FULL_CMD+=" --url tcp://$MAIN_RANK:1234"
    echo "node idx cmd: $FULL_CMD"
    if [[ "$NODE" == "$HOSTNAME" ]]; then
        echo "Launching rank $RANK on local node $NODE"
        eval $FULL_CMD &
    else
        echo "Launching rank $RANK on remote node $NODE"
        ssh $NODE "cd $PWD; $FULL_CMD" &
    fi
    RANK=$((RANK+1))
done

wait
