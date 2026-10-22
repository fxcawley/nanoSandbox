# nanoSandbox

A small nanoGPT execution sandbox and Kubernetes deployment notes.
The checked-in implementation is the
[Colab companion](notebooks/colab_nanoGPT_companion.ipynb), plus a GitHub issue
administration script. There are no checked-in container images, Kubernetes
manifests, or measured distributed-training results.

## Runnable notebook

The notebook prepares Tiny Shakespeare, runs a two-layer CPU smoke test, and
contains an optional two-process DDP example. That example requires two distinct
visible GPUs. It skips on a single-GPU VM and explicitly makes gradient
accumulation divisible by the DDP world size.

The corrected cells use ordinary notebook Python for subprocess calls. They do
not combine a one-line `!python` escape with an unsupported multiline heredoc.
The setup retains Colab's installed PyTorch build rather than downgrading it
inside a running kernel.

The CPU smoke configuration is intentionally small. It verifies loading data and
performing training/evaluation steps; it is not a throughput or model-quality
benchmark.

## Deployment design

The intended server has three physical NVIDIA A10 GPUs on one Linux node. Two
possible layouts are one pod with three workers, or three one-GPU pods with a
headless service for rendezvous. The design calls for shared dataset/checkpoint
storage and TCP communication. The corresponding manifests are not in this
checkout, so those deployments cannot be reproduced from the public material.

The earlier README included installation commands for files absent from this
repository. Those commands have been removed. No MIG partitioning, RDMA
performance, precision-mode comparison, or communication bottleneck measurement
is established by the checked-in material.

[Open the notebook in Colab](https://colab.research.google.com/github/fxcawley/nanoSandbox/blob/master/notebooks/colab_nanoGPT_companion.ipynb).
