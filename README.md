DistTrain: Kubernetes-native nanoGPT distributed training (single-node, 3x A10)

Overview

- This repo helps you learn distributed training with nanoGPT on a Kubernetes-native stack, using a single Linux node with 3x NVIDIA A10 GPUs.
- You will run two DDP topologies:
  - Single-Pod multi-GPU: one Pod, `nproc_per_node=3`.
  - Multi-Pod DDP: three Pods in a StatefulSet, `nnodes=3, nproc_per_node=1`, rendezvous via a headless Service.
- Uses hostPath PersistentVolume for datasets and checkpoints, and a ConfigMap for corporate proxy env.

Prerequisites (server)

- Linux (openSUSE), NVIDIA drivers working (`nvidia-smi` OK), CUDA 11.8 compatible.
- Root access to install k3s and GPU support.
- Docker installed.
- Outbound internet via corporate proxy (optional but recommended for image builds and dataset downloads).

Repo layout

- `docker/` – Image for nanoGPT + PyTorch (CUDA 11.8)
- `container/entrypoint.sh` – Sets `NODE_RANK` from StatefulSet ordinal for multi-Pod DDP
- `k8s/` – Namespaces, proxy ConfigMap, storage, Jobs, StatefulSet, Services
- `scripts/` – One-liners to install k3s + GPU support, build & load image, run workflows
- `docs/playbook.md` – Interview playbook (talk track, diagrams, pitfalls)

Quick start (run on the GPU server)

1) Install k3s and GPU support (GPU Operator, minimal config)

```
sudo -E bash scripts/01_install_k3s_gpu_operator.sh
```

2) Build the training image and load it into k3s (containerd)

```
bash scripts/02_build_and_load_image.sh
```

3) Apply namespace, proxy ConfigMap, and storage (hostPath PV/PVC)

```
kubectl apply -f k8s/00-namespace.yaml
kubectl -n disttrain apply -f k8s/01-proxy-config.yaml   # edit values first
kubectl -n disttrain apply -f k8s/storage/
```

4) Prepare the tiny-shakespeare dataset (Job writes to PVC)

```
kubectl -n disttrain apply -f k8s/jobs/20-download-tiny-shakespeare.yaml
kubectl -n disttrain wait --for=condition=complete job/download-tiny-shakespeare --timeout=10m
```

5) Single-Pod multi-GPU training (3 GPUs in one Pod)

```
kubectl -n disttrain apply -f k8s/jobs/30-train-singlepod.yaml
kubectl -n disttrain logs -f job/train-singlepod
```

6) Multi-Pod DDP training (3 Pods, 1 GPU each)

```
kubectl -n disttrain apply -f k8s/services/41-train-mp-headless.yaml
kubectl -n disttrain apply -f k8s/statefulset/40-train-multipod.yaml
kubectl -n disttrain rollout status sts/train-multipod
# View logs from each Pod
kubectl -n disttrain logs -f pod/train-multipod-0
kubectl -n disttrain logs -f pod/train-multipod-1
kubectl -n disttrain logs -f pod/train-multipod-2
```

7) Artifacts and TensorBoard

- All datasets, checkpoints, and logs are under the PVC mount (`/data`).
- To view locally without exposing services, copy artifacts off-cluster:

```
kubectl -n disttrain cp pod/train-multipod-0:/data /tmp/disttrain-data
```

Then run TensorBoard on the server or your workstation against the copied logdir:

```
tensorboard --logdir /tmp/disttrain-data/runs
```

Proxy configuration

- Edit `k8s/01-proxy-config.yaml` and set `HTTP_PROXY`, `HTTPS_PROXY`, and `NO_PROXY` appropriately (include `.svc,.cluster.local,127.0.0.1,localhost`).
- The training Pods mount these env vars from the ConfigMap so both dataset download and pip can work through the proxy.

Storage

- A static hostPath PV points at `/var/lib/disttrain` (create this directory on the host and ensure write perms).
- The PVC named `disttrain-pvc` binds to this PV and is mounted at `/data` inside Pods.

Notes

- NCCL settings default to TCP and disable Infiniband: `NCCL_IB_DISABLE=1`, `NCCL_SOCKET_IFNAME=eth0`.
- For single-node multi-Pod DDP, the rendezvous endpoint is a headless Service and rank is derived from StatefulSet ordinal.
- Image pull policy is `IfNotPresent`; images are loaded into containerd via `k3s ctr` import.

Cleanup

```
kubectl -n disttrain delete job/download-tiny-shakespeare --ignore-not-found
kubectl -n disttrain delete job/train-singlepod --ignore-not-found
kubectl -n disttrain delete sts/train-multipod --ignore-not-found
kubectl -n disttrain delete -f k8s/services/41-train-mp-headless.yaml --ignore-not-found
kubectl -n disttrain delete -f k8s/storage/ --ignore-not-found
kubectl delete ns disttrain --ignore-not-found
```

Troubleshooting (quick)

- GPU not visible in Pods: ensure GPU Operator is healthy (`nvidia-device-plugin-daemonset` Ready) and Pods request `nvidia.com/gpu`.
- Image not found in k3s: re-run `scripts/02_build_and_load_image.sh` to import into containerd.
- Rendezvous fails in multi-Pod: verify headless Service is created and Pods can resolve `train-mp-headless`.

Colab companion

- A single-VM Colab notebook is provided to quickly validate nanoGPT configs without Kubernetes.
- Open it in Colab: [Open in Colab](https://colab.research.google.com/github/fxcawley/nanoSandbox/blob/master/notebooks/colab_nanoGPT_companion.ipynb)


