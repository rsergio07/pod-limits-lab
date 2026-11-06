# pod-limits-lab

Break a service twice with the wrong resource settings, find the evidence, and fix each failure the right way.

**Video walkthrough:** on the [Reliability Bench](https://www.youtube.com/@reliabilitybench) YouTube channel

## What you will learn

- What requests and limits actually do
- How to prove an OOMKill
- Why CPU throttling looks like a slow app
- How to read throttling metrics

**SLO:** 99% of checkouts finish in under 500ms.

## Requirements

Docker with 4 CPUs and 8 GiB of memory, plus `git`, `make`, `kind`, `kubectl`, `helm`, `jq` and `curl`. Open source only, and it runs locally. The first run downloads several images.

Tested on one setup: macOS arm64, Colima 0.10.3 (4 CPUs, 8 GiB, `vz`), kind 0.33.0 with Kubernetes 1.37, Helm 4.3.1 and kube-prometheus-stack 92.18.0. On Colima, first run:

```bash
colima ssh -- sudo sysctl -w fs.inotify.max_user_instances=1024 fs.inotify.max_user_watches=1048576
```

## The lab

Clone the repository, then run every command from its root.

```bash
git clone https://github.com/rsergio07/pod-limits-lab.git pod-limits-lab
cd pod-limits-lab
```

### Step 1: Check your machine

Every line should say `ok`.

```bash
make preflight
```

### Step 2: Create the cluster

The private `.kubeconfig` keeps this lab away from your other clusters. Run the `export` again in any new terminal.

```bash
kind create cluster --config cluster/kind.yaml --kubeconfig .kubeconfig
export KUBECONFIG=$PWD/.kubeconfig
kubectl get nodes
```

### Step 3: Build the app and load it into the cluster

kind nodes have their own container runtime, so the image must be loaded into them.

```bash
docker build -t shop:lab app
kind load docker-image shop:lab --name lab
```

### Step 4: Install monitoring

This installs Prometheus and Grafana with only what the lab needs.

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack --version 92.18.0 -n monitoring --create-namespace -f deploy/monitoring-values.yaml --wait --timeout 8m
```

### Step 5: Deploy the shop

Grafana is at <http://localhost:30300/d/lab> with no login.

```bash
kubectl apply -f deploy/dashboard.yaml
kubectl apply -f deploy/shop.yaml
kubectl -n shop rollout status deployment/storefront --timeout=2m
kubectl -n shop get pods
```

### Step 6: Measure the baseline

Wait for traffic to build up.

```bash
# Wait 90 seconds
./scripts/verdict.sh 60
./scripts/throttle.sh
```

### Step 7: Ship a memory leak

Storefront now keeps 60 MiB per minute, and its memory limit is 64 MiB.

```bash
kubectl -n shop set env deployment/storefront LEAK_MB_PER_MIN=60
# Wait 100 seconds
kubectl -n shop get pods -l app=storefront
./scripts/verdict.sh 60
```

### Step 8: Prove it was an OOMKill

`Last State` shows the reason and exit code 137.

```bash
kubectl -n shop describe pods -l app=storefront | grep -A4 "Last State" | head -12
```

### Step 9: Fix the leak

Raising the limit would only delay the crash, so remove the leak.

```bash
kubectl -n shop set env deployment/storefront LEAK_MB_PER_MIN=0
kubectl -n shop rollout status deployment/storefront --timeout=2m
# Wait 60 seconds
./scripts/verdict.sh 30
```

### Step 10: Set a CPU limit that is too low

Each pod needs about 80 millicores. This limit allows 50.

```bash
kubectl -n shop set resources deployment/storefront --limits=cpu=50m
kubectl -n shop rollout status deployment/storefront --timeout=2m
# Wait 90 seconds
kubectl -n shop get pods -l app=storefront
./scripts/verdict.sh 60
./scripts/throttle.sh
```

### Step 11: Fix the CPU limit

Give each pod more room than it uses.

```bash
kubectl -n shop set resources deployment/storefront --limits=cpu=500m
kubectl -n shop rollout status deployment/storefront --timeout=2m
# Wait 75 seconds
./scripts/verdict.sh 60
./scripts/throttle.sh
```

### Step 12: Clean up

```bash
kind delete cluster --name lab --kubeconfig .kubeconfig
```

## Note on the CPU work

`CPU_WORK` is measured by the clock, so it does not get longer while a pod is throttled. A truly CPU bound app would be hurt more than this lab shows.

## Challenges

Predict the result before each run.

1. Remove the CPU limit and compare latency.
2. Find the lowest CPU limit that keeps the SLO.
3. Change the leak rate and predict when the pod dies.

## Safety

The lab never changes your default Kubernetes context. Grafana allows anonymous viewing and its ports are for local use. Do not expose them.

## License

MIT
