# 🚀 Istio Service Mesh — Complete Learning Notes
### Beginner to Expert Journey | Istio 1.29.0 | kind Cluster | WSL2/Ubuntu

> **Author:** V (Senior Java Engineer)  
> **Environment:** Windows 10 + WSL2 + Docker Desktop + kind (1 control-plane + 3 workers)  
> **Cluster:** vid-kind-cluster | kubectl v1.34.1 | Kubernetes v1.32.2  
> **Date:** February–April 2026

---

## 📋 Table of Contents

- [Phase 1 — Foundations](#phase-1--foundations)
  - [1.1 What is a Service Mesh & Why Istio?](#11-what-is-a-service-mesh--why-istio)
  - [1.2 Istio Architecture — Control Plane vs Data Plane](#12-istio-architecture--control-plane-vs-data-plane)
  - [1.3 Installing Istio 1.29.0 on kind](#13-installing-istio-1290-on-kind)
  - [1.4 First Sidecar-Injected Deployment — Bookinfo](#14-first-sidecar-injected-deployment--bookinfo)
- [Phase 2 — Traffic Management](#phase-2--traffic-management)
  - [2.1 VirtualService & DestinationRule](#21-virtualservice--destinationrule)
  - [2.2 Canary Releases — Weight-Based Traffic Splitting](#22-canary-releases--weight-based-traffic-splitting)
  - [2.3 Header-Based Routing — Dark Launches](#23-header-based-routing--dark-launches)
  - [2.4 Retries & Timeouts](#24-retries--timeouts)
  - [2.5 Circuit Breaker](#25-circuit-breaker)
- [Phase 3 — Observability](#phase-3--observability)
  - [3.1 Kiali — Service Mesh Topology](#31-kiali--service-mesh-topology)
  - [3.2 Jaeger — Distributed Tracing](#32-jaeger--distributed-tracing)
  - [3.3 Prometheus — Metrics Collection](#33-prometheus--metrics-collection)
  - [3.4 Grafana — Metrics Dashboards](#34-grafana--metrics-dashboards)
- [Phase 4 — Security](#phase-4--security)
  - [4.1 mTLS Deep Dive & SPIFFE Certificates](#41-mtls-deep-dive--spiffe-certificates)
  - [4.2 PeerAuthentication — STRICT Mode](#42-peerauthentication--strict-mode)
  - [4.3 AuthorizationPolicy — Zero-Trust Access Control](#43-authorizationpolicy--zero-trust-access-control)
- [Appendix](#appendix)
  - [A.1 Key Commands Reference](#a1-key-commands-reference)
  - [A.2 Common Gotchas & Fixes](#a2-common-gotchas--fixes)
  - [A.3 Istio CRDs Reference](#a3-istio-crds-reference)
  - [A.4 xDS Protocol Reference](#a4-xds-protocol-reference)

---

# Phase 1 — Foundations

## 1.1 What is a Service Mesh & Why Istio?

### The Problem

In a microservices world, every team solves the same problems **inside their application code**:

| Problem | Without Mesh |
|---|---|
| Retries on failure | Duplicated in every service, every language |
| Service-to-service encryption | Manual TLS setup per service |
| Distributed tracing | Custom instrumentation in every service |
| Canary deployments | Complex application-level logic |
| Access control | Bespoke auth in every service |

This logic gets **duplicated in every service, in every language**. It's a maintenance nightmare.

### The Solution — Move it to the Infrastructure

A service mesh moves all of that **out of your application** into the **infrastructure layer**. Your app code stays clean — it just makes plain HTTP/gRPC calls. The mesh handles everything else **transparently**.

### How Istio Does It — The Sidecar Pattern

Istio injects an **Envoy proxy sidecar** alongside every pod. All traffic is intercepted via `iptables` rules — the application never knows Envoy is there.

```
┌─────────────────────────────────────┐
│              Your Pod               │
│                                     │
│  ┌─────────────┐  ┌──────────────┐  │
│  │  Your App   │  │  Envoy       │  │
│  │  Container  │◄─►  Sidecar     │  │
│  │  (port 8080)│  │  Proxy       │  │
│  └─────────────┘  └──────┬───────┘  │
└─────────────────────────┼───────────┘
                           │
                    All traffic flows
                    through Envoy
                           │
              ┌────────────▼────────────┐
              │    istiod (Control Plane)│
              │  - Pushes config (xDS)  │
              │  - Issues SPIFFE certs  │
              │  - Service discovery    │
              └─────────────────────────┘
```

### Istio Capabilities at a Glance

| Capability | Mechanism |
|---|---|
| Traffic routing | VirtualService / DestinationRule pushed to Envoy |
| mTLS encryption | istiod issues certs, Envoy handles TLS handshake |
| Distributed tracing | Envoy adds trace headers automatically |
| Metrics | Envoy emits Prometheus metrics per request |
| Access control | AuthorizationPolicy evaluated by Envoy |

---

## 1.2 Istio Architecture — Control Plane vs Data Plane

```
┌─────────────────────────────────────────────────────────────┐
│                    CONTROL PLANE                            │
│                                                             │
│    ┌──────────────────────────────────────────────┐        │
│    │                  istiod                       │        │
│    │  ┌──────────┐  ┌──────────┐  ┌────────────┐  │        │
│    │  │  Pilot   │  │  Citadel │  │  Galley    │  │        │
│    │  │ (xDS API)│  │  (CA)    │  │  (Config)  │  │        │
│    │  └──────────┘  └──────────┘  └────────────┘  │        │
│    └──────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────────┘
                           │ xDS (CDS/LDS/EDS/RDS)
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                     DATA PLANE                              │
│                                                             │
│  [Envoy] ←→ [Envoy] ←→ [Envoy] ←→ [IngressGateway Envoy]  │
│  pod-A       pod-B       pod-C       (edge proxy)           │
└─────────────────────────────────────────────────────────────┘
```

### Component Roles

| Component | Role | Count |
|---|---|---|
| `istiod` | Control plane brain — config push, CA, service discovery | 1 |
| Envoy sidecar | Data plane — carries traffic, enforces policy | 1 per pod |
| IngressGateway | Edge Envoy — entry point from outside cluster | 1+ |
| EgressGateway | Edge Envoy — controlled exit from cluster | 1+ |

### The xDS Protocol — How istiod Talks to Envoy

All config is pushed via the **xDS API** — a gRPC streaming protocol:

| API | Full Name | What it configures |
|---|---|---|
| **CDS** | Cluster Discovery Service | Upstream destinations (where to send traffic) |
| **LDS** | Listener Discovery Service | Ports to intercept and listen on |
| **EDS** | Endpoint Discovery Service | Actual pod IPs behind each service |
| **RDS** | Route Discovery Service | HTTP routing rules (path/header matching) |

```bash
# See all proxies and their sync state
istioctl proxy-status

# Output from our cluster:
# NAME                          CLUSTER    ISTIOD              VERSION  SUBSCRIBED TYPES
# productpage-v1-xxx.default    Kubernetes istiod-xxx-lkfb9    1.29.0   4 (CDS,LDS,EDS,RDS)
# reviews-v1-xxx.default        Kubernetes istiod-xxx-lkfb9    1.29.0   4 (CDS,LDS,EDS,RDS)
# istio-ingressgateway-xxx      Kubernetes istiod-xxx-lkfb9    1.29.0   3 (CDS,LDS,EDS)
```

> 💡 **Key Insight:** Gateways only subscribe to 3 xDS APIs (no RDS) because they handle raw TCP/TLS at the edge, not internal HTTP routing.

> 💡 **Key Insight:** All proxies showing `SYNCED` means istiod has successfully pushed identical config to every Envoy in your mesh. This is the heartbeat of Istio.

---

## 1.3 Installing Istio 1.29.0 on kind

### Environment Verified

```
OS:       Windows 10 + WSL2 + Ubuntu
Cluster:  kind (vid-kind-cluster)
Nodes:    1 control-plane + 3 workers
RAM:      40 GB (well above Istio's ~2 GB requirement)
Disk:     ~20 GB free (tight — be mindful of cleanup)

kubectl Client: v1.34.1
Kubernetes:     v1.32.2
```

### Step 1 — Download istioctl

```bash
curl -L https://istio.io/downloadIstio | sh -
# Downloaded: istio-1.29.0

export PATH="$HOME/istio-1.29.0/bin:$PATH"
echo 'export PATH="$HOME/istio-1.29.0/bin:$PATH"' >> ~/.bashrc

istioctl version
# client version: 1.29.0
```

### Step 2 — Pre-flight Check

```bash
istioctl x precheck
# ✔ No issues found when checking the cluster. Istio is safe to install or upgrade!
```

### Step 3 — Install with Demo Profile

```bash
istioctl install --set profile=demo -y

# Output:
# ✔ Istio core installed ⛵️
# ✔ Istiod installed 🧠
# ✔ Egress gateways installed 🛫
# ✔ Ingress gateways installed 🛬
# ✔ Installation complete
```

### Istio Profile Comparison

| Profile | Use Case | What's installed |
|---|---|---|
| `minimal` | CI/CD, resource-constrained | Control plane only |
| `demo` | Learning, development | Everything + addons |
| `default` | Production baseline | Balanced |
| `production` | Hardened production | Resource-tuned |

### Step 4 — Verify Installation

```bash
kubectl get pods -n istio-system
# NAME                                    READY   STATUS
# istio-egressgateway-575f9dbdc9-m4fl8    1/1     Running
# istio-ingressgateway-6f4dfc5c45-rvtsw   1/1     Running
# istiod-d45c5cbbb-lkfb9                  1/1     Running

kubectl get svc -n istio-system
# istio-ingressgateway   LoadBalancer   10.96.1.131   <pending>   ...
# istiod                 ClusterIP      10.96.140.95  <none>      ...
```

> ⚠️ **kind Gotcha:** `EXTERNAL-IP: <pending>` is normal on kind — no cloud load balancer. Use `kubectl port-forward` as workaround.

### Step 5 — Enable Sidecar Injection

```bash
kubectl label namespace default istio-injection=enabled
kubectl get namespace default --show-labels
# LABELS: istio-injection=enabled,kubernetes.io/metadata.name=default
```

This registers a **Mutating Webhook Admission Controller**. Every pod created in the `default` namespace gets Envoy injected automatically.

### The 14 Istio CRDs Installed

```bash
kubectl get crd | grep istio.io | awk '{print $1}'

# Networking (Traffic Management):
authorizationpolicies.security.istio.io     # access control
destinationrules.networking.istio.io        # subsets, CB, TLS
envoyfilters.networking.istio.io            # raw Envoy config
gateways.networking.istio.io                # ingress/egress config
peerauthentications.security.istio.io       # mTLS policy
proxyconfigs.networking.istio.io            # per-pod proxy tuning
requestauthentications.security.istio.io    # JWT validation
serviceentries.networking.istio.io          # external services
sidecars.networking.istio.io                # sidecar scope
telemetries.telemetry.istio.io              # observability config
virtualservices.networking.istio.io         # routing rules
wasmplugins.extensions.istio.io             # WASM plugins
workloadentries.networking.istio.io         # VM workloads
workloadgroups.networking.istio.io          # VM workload groups
```

---

## 1.4 First Sidecar-Injected Deployment — Bookinfo

### The Application Architecture

Bookinfo is Istio's demo app — 4 microservices in different languages, intentionally designed to demonstrate mesh features:

```
                    ┌─────────────┐
         User ─────►│ productpage │  (Python)
                    └──────┬──────┘
                           │
               ┌───────────┼───────────┐
               ▼           ▼           ▼
           ┌───────┐  ┌─────────┐  ┌────────┐
           │details│  │ reviews │  │ratings │
           │(Ruby) │  │  (Java) │  │ (Node) │
           └───────┘  └─────────┘  └────────┘
                           │
                    3 versions:
                    v1 → no stars
                    v2 → black stars  ← calls ratings
                    v3 → red stars    ← calls ratings
```

> 💡 **Design Choice:** reviews having 3 versions is intentional — used for canary deployments and traffic splitting demos throughout the course.

### Deploy and Verify

```bash
kubectl apply -f ~/istio-1.29.0/samples/bookinfo/platform/kube/bookinfo.yaml

kubectl get pods
# NAME                              READY   STATUS
# details-v1-766844796b-swgzf       2/2     Running  ← 2/2 = app + Envoy sidecar!
# productpage-v1-54bb874995-2tqjf   2/2     Running
# ratings-v1-5dc79b6bcd-8zpsf       2/2     Running
# reviews-v1-598b896c9d-9t2fq       2/2     Running
# reviews-v2-556d6457d-5vjmc        2/2     Running
# reviews-v3-564544b4d6-dz29t       2/2     Running
```

> ✅ **Proof of mesh working:** `2/2` in READY column means your app container + Envoy sidecar are both running.

### Inspect the Sidecar Injection

```bash
kubectl describe pod -l app=productpage | grep -A5 "istio-proxy\|istio-init"

# istio-init:    # Sets up iptables — runs first, then exits
#   Image: docker.io/istio/proxyv2:1.29.0

# istio-proxy:   # Envoy sidecar — runs alongside your app forever
#   Image: docker.io/istio/proxyv2:1.29.0
#   Port:  15090/TCP (http-envoy-prom)  ← Prometheus metrics
```

### What Envoy Knows About the Mesh

```bash
# See all upstream clusters Envoy knows about
istioctl proxy-config cluster deploy/productpage-v1

# SERVICE FQDN                              PORT  SUBSET  DIRECTION  TYPE
# reviews.default.svc.cluster.local         9080  -       outbound   EDS
# ratings.default.svc.cluster.local         9080  -       outbound   EDS
# details.default.svc.cluster.local         9080  -       outbound   EDS
# BlackHoleCluster                          -     -       -          STATIC  ← drops traffic
# PassthroughCluster                        -     -       -          STATIC  ← bypasses Envoy
# xds-grpc                                  -     -       -          STATIC  ← channel to istiod
```

### Key Ports Explained

```bash
istioctl proxy-config listener deploy/productpage-v1

# PORT   MATCH                    DESTINATION
# 15001  ALL                      PassthroughCluster  ← master outbound trap
# 15006  Trans: tls; Addr: *:9080 Cluster: inbound|9080||  ← master inbound trap
# 15006  Trans: raw_buffer        Cluster: inbound|9080||  ← plain HTTP inbound
# 9080   App: http/1.1,h2c        Route: 9080         ← L7 HTTP routing
# 15090  ALL                      /stats/prometheus*  ← Envoy metrics
# 15021  ALL                      /healthz/ready*     ← health check
```

### The Complete Traffic Flow

```
Your App makes HTTP call to reviews:9080
    │
    ▼ iptables redirects ALL outbound to port 15001
Envoy outbound listener (15001)
    │
    ▼ matches listener for port 9080
Route table lookup for 9080
    │
    ▼ selects cluster: reviews.default.svc.cluster.local|9080
EDS lookup: get actual pod IPs for reviews
    │
    ▼ sends request to reviews pod IP
Target pod: iptables redirects inbound to port 15006
    │
    ▼ Envoy inbound listener (15006)
    │   detects: plain HTTP or mTLS?
    │   enforces: AuthorizationPolicy
    ▼
reviews app container receives clean request
```

---

# Phase 2 — Traffic Management

## 2.1 VirtualService & DestinationRule

### The Mental Model

Think of it like a GPS + road quality system:

| Object | Analogy | Job |
|---|---|---|
| **VirtualService** | GPS routing rules | *Where* to send traffic & *how* (weights, headers, retries) |
| **DestinationRule** | Road quality rules | *What* the destination looks like (subsets, TLS, load balancing) |

> 💡 **Rule:** Always create `DestinationRule` first (defines subsets), then `VirtualService` (routes to those subsets).

### Why Subsets Are Needed

```
# Before DestinationRule — Envoy sees reviews as ONE pool:
reviews.default.svc.cluster.local:9080
  └── endpoints: [pod-v1-ip, pod-v2-ip, pod-v3-ip]  ← all mixed, random load balancing

# After DestinationRule — Envoy sees 3 distinct subsets:
reviews.default.svc.cluster.local:9080
  ├── subset:v1 → [pod-v1-ip]
  ├── subset:v2 → [pod-v2-ip]
  └── subset:v3 → [pod-v3-ip]    ← surgical routing now possible
```

### Create DestinationRules for All Services

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: reviews
spec:
  host: reviews
  subsets:
  - name: v1
    labels:
      version: v1   # matches pod label
  - name: v2
    labels:
      version: v2
  - name: v3
    labels:
      version: v3
```

### Pin All Traffic to v1

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: reviews
spec:
  hosts:
  - reviews
  http:
  - route:
    - destination:
        host: reviews
        subset: v1    # ALL traffic → v1, zero randomness
```

**Result:** Refresh browser 10 times — always no stars (v1). Traffic is 100% deterministic.

---

## 2.2 Canary Releases — Weight-Based Traffic Splitting

### The Production Pattern

```
Week 1:  v1=90%  v3=10%   ← canary, only 10% users see new version
Week 2:  v1=70%  v3=30%   ← metrics look good, increase
Week 3:  v1=50%  v3=50%   ← halfway
Week 4:  v1=0%   v3=100%  ← full rollout
```

If v3 has a bug, roll back instantly by changing weights — zero downtime, zero redeployment.

### 80/20 Split

```yaml
spec:
  hosts:
  - reviews
  http:
  - route:
    - destination:
        host: reviews
        subset: v1
      weight: 80
    - destination:
        host: reviews
        subset: v3
      weight: 20    # weights MUST sum to exactly 100
```

### Verify the Split

```bash
for i in $(seq 1 20); do
  kubectl exec -it $(kubectl get pod -l app=ratings -o jsonpath='{.items[0].metadata.name}') \
    -c ratings -- curl -s productpage:9080/productpage \
    | grep -o "glyphicon-star\|Reviewer1" | head -1
done

# Result: ~16 "Reviewer1" (v1, no stars) + ~4 "glyphicon-star" (v3, red stars)
# Proof: 80/20 split working as configured
```

> ⚠️ **Gotcha:** Weights must sum to exactly 100. Istio's admission webhook rejects the VirtualService if they don't.

---

## 2.3 Header-Based Routing — Dark Launches

### The Use Case

Route specific users to a new version based on HTTP headers — your QA team tests v3 in **live production traffic** while real users never see it. Zero risk.

```
Normal users  ──────────────────────────► reviews-v1 (stable)
QA team (end-user: vidhan header) ───────► reviews-v3 (new version)
```

### VirtualService Config

```yaml
spec:
  hosts:
  - reviews
  http:
  - match:                      # Rule 1: checked first
    - headers:
        end-user:
          exact: vidhan         # if header matches...
    route:
    - destination:
        host: reviews
        subset: v3              # ...send to v3

  - route:                      # Rule 2: default catch-all
    - destination:
        host: reviews
        subset: v1              # everyone else → v1
```

> 💡 **Key Insight:** Match rules are evaluated **top to bottom — first match wins**. Always put the most specific rules first, default catch-all last.

### Proof via Browser

1. Open `http://localhost:9080/productpage` → no stars (v1, anonymous)
2. Click **Sign In** → username `vidhan` → any password
3. Page now shows red stars (v3) — Bookinfo app sends `end-user: vidhan` header
4. Open incognito tab → same URL → no stars again

**Same pods, same cluster, different experience based on identity.**

### Verify in Envoy Config

```bash
istioctl proxy-config route deploy/productpage-v1 --name 9080 -o json | grep -A5 "end-user\|subset"

# "name": "end-user",
# "stringMatch": {
#     "exact": "vidhan"     ← header match rule compiled into Envoy native config
# }
```

---

## 2.4 Retries & Timeouts

### The Problem Without Istio

Every team writes their own retry logic in code:

```java
// Java — every service does this themselves, duplicated everywhere
for (int i = 0; i < 3; i++) {
    try {
        return reviewsClient.call();
    } catch (Exception e) {
        if (i == 2) throw e;
        Thread.sleep(1000);
    }
}
```

### With Istio — One Config, Zero Code Changes

```yaml
spec:
  http:
  - retries:
      attempts: 3           # retry up to 3 times
      perTryTimeout: 2s     # each attempt gets 2s max
      retryOn: 5xx          # retry on server errors
    timeout: 10s            # total budget for the request
    route:
    - destination:
        host: ratings
        subset: v1
```

### Fault Injection — Test Resilience Without Breaking Anything

```yaml
# Inject 500 errors on 50% of ratings requests
fault:
  abort:
    httpStatus: 500
    percentage:
      value: 50

# Inject 5 second delay on 100% of requests
fault:
  delay:
    percentage:
      value: 100
    fixedDelay: 5s
```

### Retry Math

With 50% failure rate and 3 retry attempts:
```
P(all 3 fail) = 0.5 × 0.5 × 0.5 = 12.5%
P(at least one succeeds) = 87.5%

Proven in our practical: all 10 productpage requests returned 200
even with 50% fault injection on ratings — retries masked the errors.
```

---

## 2.5 Circuit Breaker

### The Concept

Named after electrical circuit breakers. When current exceeds safe levels, the breaker **trips** and cuts power — protecting the circuit.

```
CLOSED (normal):
service-A ──────────────────────► ratings ✅

ratings starts failing/slow — threshold exceeded:
service-A ──────────────────────► ratings ❌❌❌

Circuit OPENS (trips):
service-A ──X (instant 503)      ratings 🚫
              ↓
        Returns error immediately (1.5ms!)
        instead of waiting (3.5ms+)

HALF-OPEN (cooldown expired):
service-A ── 1 test request ───► ratings
             if succeeds → CLOSED again ✅
             if fails → OPEN again ❌
```

### Key Difference from Retries

- **Retries** = keep trying the failing service (optimistic)
- **Circuit Breaker** = stop trying altogether when things are bad (protective)

### DestinationRule Config

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: ratings
spec:
  host: ratings
  subsets:
  - name: v1
    labels:
      version: v1
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 1           # max TCP connections
      http:
        http1MaxPendingRequests: 1  # max queued requests
        maxRequestsPerConnection: 1 # no connection reuse
    outlierDetection:
      consecutive5xxErrors: 3      # trip after 3 consecutive errors
      interval: 10s                # check health every 10s
      baseEjectionTime: 30s        # eject unhealthy pod for 30s
      maxEjectionPercent: 100      # allow ejecting all pods if needed
```

### Fortio Load Test Results — Our Practical

```bash
# Baseline: 1 concurrent connection
fortio load -c 1 -qps 0 -n 20 http://ratings:9080/ratings/1
# Code 200: 20 (100%) ← all pass, avg 3.878ms

# Overload: 3 concurrent connections (exceeds maxConnections:1)
fortio load -c 3 -qps 0 -n 20 http://ratings:9080/ratings/1
# Code 200: 8  (40%)  ← circuit breaker tripping
# Code 503: 12 (60%)  ← instant rejection by Envoy!
```

| Concurrent Conns | Success | 503s | Avg Response | Key Finding |
|---|---|---|---|---|
| 1 (baseline) | 20/20 (100%) | 0 | 3.878ms | All requests pass |
| 3 (overload) | 8/20 (40%) | 12 | 1.5ms for 503s | **Circuit breaker firing!** |

> 💡 **Key Insight:** 503s returned in **1.5ms** vs 3.5ms for 200s. Envoy rejected circuit-broken requests **before they ever touched the ratings app**. Fast failure, system protection.

---

# Phase 3 — Observability

The observability trinity gives you complete visibility with **zero application code changes**:

| Tool | Analogy | What it answers |
|---|---|---|
| **Kiali** | Control tower | WHO is talking to WHO |
| **Jaeger** | Microscope | HOW LONG each hop takes |
| **Prometheus** | Heart monitor | HOW MANY requests, error rates |
| **Grafana** | Dashboard TV | Trends and patterns over time |

### Install All Addons

```bash
# Demo profile doesn't bundle addons in Istio 1.29.0 — install separately
kubectl apply -f ~/istio-1.29.0/samples/addons/

kubectl get pods -n istio-system
# grafana-cdb9db549-fb5tg      1/1 Running
# jaeger-5d4bd98fc4-2tkhw      1/1 Running
# kiali-744c76b44c-crrp7       1/1 Running
# loki-0                       2/2 Running  ← bonus log aggregation
# prometheus-68fbbd698f-2mbnd  2/2 Running
```

---

## 3.1 Kiali — Service Mesh Topology

```bash
istioctl dashboard kiali
# Opens: http://localhost:20001
```

### What We Observed

**First view (reviews pinned to v1):**
```
[unknown source] ──► productpage-v1 ──► details-v1
                                    ──► reviews-v1
ratings-v1 (isolated — reviews-v1 doesn't call ratings!)
```

**After enabling 34/33/33 split:**
```
[istio-ingressgateway] ──🔒──► productpage-v1 ──► details-v1
                                               ──► reviews ──43.4%──► v1
                                                          ──33.0%──► v2 ──🔒──► ratings-v1
                                                          ──23.6%──► v3 ──🔒──► ratings-v1
```

**Graph stats:**
```
4 apps (6 versions) → 5 apps (7 versions) after gateway added
Traffic split on reviews: v1=43.4%, v2=33%, v3=23.6%  ← matches our VS config!
100% success rate, 0.00% error
🔒 padlock on EVERY edge → automatic mTLS everywhere
```

### Key Kiali Features

- **Traffic Animation** — animated dots show live traffic direction and volume
- **Security overlay** — 🔒 icons confirm mTLS on each connection
- **Istio Config tab** — validates your VS/DR configs, shows ✅ or ⚠️
- **Workload drill-down** — per-pod inbound/outbound metrics

> 💡 **Tip:** Enable "Show Gateways" in Display dropdown to see the `istio-ingressgateway` node as the mesh entry point.

---

## 3.2 Jaeger — Distributed Tracing

### How It Works — Zero App Changes*

Envoy automatically:
1. Generates a **trace ID** for every new incoming request
2. Adds trace headers (`x-b3-traceid`, `x-b3-spanid`) to all outbound calls
3. Reports timing data to Jaeger after the request completes

*Apps must **forward** trace headers when making downstream calls. Bookinfo does this already.

### Enable 100% Sampling

By default, Istio samples only 1% of requests. For learning, enable 100%:

```bash
# In the istio ConfigMap
kubectl patch configmap istio -n istio-system --type merge -p '{
  "data": {
    "mesh": "...tracing:\n  sampling: 100.0\ndefaultProviders:\n  tracing:\n  - jaeger..."
  }
}'

kubectl rollout restart deployment -n default
kubectl rollout restart deployment -n istio-system
```

```bash
istioctl dashboard jaeger
# Opens: http://localhost:16686
```

### Reading a Trace — Real Data from Our Cluster

**Fast trace (28.98ms):**
```
ratings.default  [28.98ms total]
  └─ productpage.default  [~28ms]
       ├─ productpage → details  [2.99ms]  ← starts at 7.25ms
       │    └─ details.default   [1.86ms]  ← actual details processing
       │
       └─ productpage → reviews  [starts at 14.44ms]
            └─ reviews.default   [13.52ms] ← Java is the slowest!
                 └─ reviews → ratings  [1.95ms]
                      └─ ratings.default [1.09ms]  ← Node.js is fast
```

**Slow trace (98.95ms) — 3.4x slower:**
```
Same structure but:
  reviews.default: 85.69ms  ← 6x slower than normal!
  ratings.default: 11.84ms  ← also impacted

Root cause: JVM Garbage Collection pause on reviews-v2
```

### Trace Comparison

| Metric | Fast Trace | Slow Trace | Difference |
|---|---|---|---|
| Total | 28.98ms | 98.95ms | +70ms |
| details | 1.86ms | 2.67ms | negligible |
| **reviews** | **13.52ms** | **85.69ms** | **+72ms ← GC pause!** |
| ratings | 1.09ms | 11.84ms | +10ms |

> 💡 **Real Finding:** reviews-v2 (Java) showed 6x latency spikes. Without Jaeger you'd know "productpage is slow sometimes" — with Jaeger you pinpoint **exactly which service** caused it, in seconds.

> 💡 **Observation:** productpage calls `details` first, waits, then calls `reviews` — **sequential, not parallel**. This is a design smell visible only in traces.

---

## 3.3 Prometheus — Metrics Collection

Every Envoy sidecar exposes hundreds of metrics at `:15090/stats/prometheus`, scraped every 15 seconds.

```bash
istioctl dashboard prometheus
# Opens: http://localhost:9090
```

### Key PromQL Queries

```promql
# Request rate to productpage (req/sec)
rate(istio_requests_total{
  destination_service="productpage.default.svc.cluster.local"
}[1m])

# Request rate broken down by HTTP response code
sum(rate(istio_requests_total{
  destination_service_name="productpage"
}[1m])) by (response_code)

# p99 latency for reviews service (milliseconds)
histogram_quantile(0.99,
  sum(rate(istio_request_duration_milliseconds_bucket{
    destination_service_name="reviews"
  }[1m])) by (le)
)

# Error rate across all services
sum(rate(istio_requests_total{
  response_code!="200"
}[1m])) by (destination_service_name)
```

### Observations from Our Cluster

```
Query 1: ~0.9 req/sec to productpage (steady state)
Query 2: Only response_code="200" visible — zero errors
Query 3: reviews p99 latency:
         Started at ~100ms (JVM cold start)
         Dropped to ~45ms (JVM warmed up)
         Spiked to ~80ms (GC pause burst)
         Settled to ~40ms (steady state)
Query 4: Empty result = NO errors anywhere in the mesh ✅
```

> 💡 **Key Insight:** `timeout: 0s` in Envoy config means **no timeout / infinite**, not zero seconds. This is a common source of confusion.

---

## 3.4 Grafana — Metrics Dashboards

```bash
istioctl dashboard grafana
# Opens: http://localhost:3000
# Navigate: Dashboards → Istio
```

### Available Istio Dashboards

| Dashboard | What it shows |
|---|---|
| **Istio Mesh Dashboard** | Global overview — all services, request rates, error rates, latency |
| **Istio Service Dashboard** | Per-service deep dive — client vs server metrics |
| **Istio Workload Dashboard** | Per-pod metrics with source breakdown |
| **Istio Performance Dashboard** | Envoy + istiod resource usage (CPU/memory) |

### Istio Mesh Dashboard — Real Data from Our Cluster

```
Global Traffic:   3.39 req/s total across all services
Success Rate:     100% 🟢
4xx errors:       0 req/s
5xx errors:       0 req/s
```

| Service | Workload | Req/s | P50 | P90 | P99 | Success |
|---|---|---|---|---|---|---|
| details | details-v1 | 0.89 | 3.11ms | 4.81ms | 19.45ms | 100% 🟢 |
| reviews | reviews-v1 | 0.14 | 3.50ms | 7.50ms | 9.75ms | 100% 🟢 |
| reviews | reviews-v2 | 0.43 | 16.63ms | 24.11ms | **221.50ms** | 100% ⚠️ |
| reviews | reviews-v3 | 0.31 | 17.50ms | 23.50ms | 24.85ms | 100% 🟢 |
| ratings | ratings-v1 | 0.75 | 3.00ms | 4.60ms | 4.96ms | 100% 🟢 |
| productpage | productpage-v1 | 0.87 | 25.69ms | 46.25ms | 194.50ms | 100% 🟢 |

> ⚠️ **Production Finding:** reviews-v2 P99 = **221ms** vs reviews-v1 P99 = **9.75ms** — a 22x difference! Prometheus proves this is a repeating pattern, not a one-off. In production, set an alert: `p99 > 200ms for 5 minutes → page on-call engineer`.

### Istio Performance Dashboard — Overhead is Tiny

```
Proxy (Envoy) resource usage across ALL sidecars:
  Memory: 312–360 MiB total
  vCPU:   0.05–0.07 cores  ← almost nothing!

Istiod resource usage:
  Memory: ~256 MiB resident
  vCPU:   0.003–0.011 cores
  Goroutines: ~772
```

**Conclusion:** All sidecars across 6 pods use less than 0.07 CPU cores combined. Istio overhead is production-viable.

---

# Phase 4 — Security

## 4.1 mTLS Deep Dive & SPIFFE Certificates

### Regular TLS vs Mutual TLS

```
Regular TLS (HTTPS):
Client ──"who are you?"──► Server shows certificate
Client trusts server ✅, encrypts traffic

Mutual TLS (mTLS):
Client ──"who are you?"──► Server shows certificate
Server ──"who are YOU?"──► Client shows certificate
Both verify each other ✅, encrypt traffic
```

### SPIFFE — The Identity Framework

Every Envoy sidecar receives a **SPIFFE X.509 certificate** from istiod (acting as CA).

```bash
# Inspect the actual certificate
istioctl proxy-config secret \
  $(kubectl get pod -l app=productpage -o jsonpath='{.items[0].metadata.name}') \
  -o json | \
  jq '.dynamicActiveSecrets[0].secret.tlsCertificate.certificateChain.inlineBytes' -r | \
  base64 -d | openssl x509 -noout -text | grep -A2 "Subject\|Validity\|URI"
```

### Actual Certificate from Our Cluster

```
Validity:
    Not Before: Feb 25 19:31:45 2026 GMT
    Not After:  Feb 26 19:33:45 2026 GMT   ← Only 24 HOURS!

Subject: (empty — identity is in SAN URI, not Subject CN)

X509v3 Subject Alternative Name: critical
    URI:spiffe://cluster.local/ns/default/sa/bookinfo-productpage
```

### SPIFFE URI Decoded

```
spiffe://cluster.local/ns/default/sa/bookinfo-productpage
│         │             │          │  │
│         │             │          │  └─ Kubernetes ServiceAccount name
│         │             │          └──── "sa" = ServiceAccount
│         │             └─────────────── namespace where pod runs
│         └───────────────────────────── cluster trust domain
└─────────────────────────────────────── SPIFFE standard scheme
```

This certificate **cryptographically proves** the workload's identity. It cannot be faked.

### Certificate Lifecycle

```
istiod (CA)
  │
  ├── Issues cert to productpage sidecar on pod start
  │   Valid: 24 hours
  │
  ├── Auto-rotates at 80% of lifetime (~19 hours)
  │   Zero downtime rotation
  │
  └── Revokes immediately if pod is deleted
```

> 💡 **Security Design:** 24-hour rotation means a compromised cert is useless within 24 hours maximum. Traditional TLS certs last 1-2 years — vastly inferior. istiod handles all rotation automatically.

### The mTLS Handshake

```
productpage Envoy                     reviews Envoy
      │                                     │
      │──── TLS ClientHello ───────────────►│
      │◄─── TLS ServerHello ────────────────│
      │     (reviews presents:              │
      │      spiffe://.../sa/bookinfo-reviews)
      │                                     │
      │──── Client Certificate ────────────►│
      │     (productpage presents:          │
      │      spiffe://.../sa/bookinfo-productpage)
      │                                     │
      │     Both verify against istiod CA   │
      │     SPIFFE URI extracted from cert  │
      │     Used for AuthorizationPolicy    │
      │                                     │
      │◄════ Encrypted mTLS tunnel ════════►│
      │     All subsequent traffic encrypted│
```

---

## 4.2 PeerAuthentication — STRICT Mode

### The Three Modes

| Mode | Behaviour | Use Case |
|---|---|---|
| `DISABLE` | Plain HTTP only, no TLS at all | Legacy non-mesh workloads |
| `PERMISSIVE` | Accept both plain HTTP AND mTLS | Gradual mesh adoption (default) |
| `STRICT` | mTLS only — plain HTTP rejected | Production zero-trust |

### Apply STRICT Mode Mesh-Wide

```yaml
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system   # istio-system = mesh-wide scope
spec:
  mtls:
    mode: STRICT
```

```bash
kubectl apply -f above.yaml
```

### Proof from Our Practical

**Step 1: Deploy a pod WITHOUT sidecar**
```bash
kubectl run plain-pod \
  --image=curlimages/curl \
  --restart=Never \
  --labels="sidecar.istio.io/inject=false" \
  -- sleep 3600

kubectl get pod plain-pod
# NAME        READY   STATUS
# plain-pod   1/1     Running  ← 1/1 = NO sidecar!
```

**Step 2: PERMISSIVE mode — plain HTTP works**
```bash
kubectl exec -it plain-pod -- curl -s \
  http://productpage.default.svc.cluster.local:9080/productpage \
  | grep -o "<title>.*</title>"
# <title>Simple Bookstore App</title>  ← SUCCESS in PERMISSIVE
```

**Step 3: Enable STRICT mode, then test again**
```bash
# Apply STRICT PeerAuthentication (see above)

kubectl exec -it plain-pod -- curl -sv \
  http://productpage.default.svc.cluster.local:9080/productpage 2>&1 | tail -5
# * Recv failure: Connection reset by peer
# * closing connection #0
# command terminated with exit code 56  ← REJECTED! No client cert
```

**Step 4: Mesh pod still works fine**
```bash
kubectl exec -it $(kubectl get pod -l app=ratings -o jsonpath='{.items[0].metadata.name}') \
  -c ratings -- curl -s productpage:9080/productpage | grep -o "<title>.*</title>"
# <title>Simple Bookstore App</title>  ← SUCCESS — has SPIFFE cert
```

**Step 5: Verify STRICT is active**
```bash
istioctl x describe pod $(kubectl get pod -l app=productpage -o jsonpath='{.items[0].metadata.name}') \
  | grep -A2 "PeerAuthentication"

# Effective PeerAuthentication:
#    Workload mTLS mode: STRICT          ← confirmed!
# Applied PeerAuthentication:
#    default.istio-system                ← mesh-wide policy applied
```

### Summary

| Test | Pod Type | Mode | Result | Reason |
|---|---|---|---|---|
| plain-pod → productpage | 1/1 (no sidecar) | PERMISSIVE | ✅ 200 | Plain HTTP accepted |
| plain-pod → productpage | 1/1 (no sidecar) | STRICT | ❌ Reset | No client certificate |
| ratings → productpage | 2/2 (has sidecar) | STRICT | ✅ 200 | SPIFFE cert verified |

### Scope and Precedence

```
Workload-specific PeerAuthentication  (highest priority)
  └─► Namespace-level PeerAuthentication
        └─► Mesh-wide PeerAuthentication (lowest priority)

# Workload-specific example:
spec:
  selector:
    matchLabels:
      app: productpage      # only applies to productpage pods
  mtls:
    mode: PERMISSIVE        # override mesh-wide STRICT for this workload
```

---

## 4.3 AuthorizationPolicy — Zero-Trust Access Control

### mTLS vs Authorization

```
mTLS (PeerAuthentication):
  "Are you who you say you are?" → AUTHENTICATION

AuthorizationPolicy:
  "Are you allowed to do this?" → AUTHORIZATION
```

Both are needed. mTLS without authorization is like checking IDs but having no guest list.

### How It Works

AuthorizationPolicy uses the **SPIFFE identity** from mTLS certificates to make decisions. The principal cannot be faked because it's embedded in a cryptographically verified certificate.

```yaml
rules:
- from:
  - source:
      principals:
      - cluster.local/ns/default/sa/bookinfo-reviews
```

This says: "Only allow requests from the workload with ServiceAccount `bookinfo-reviews`."

### The Three Actions

| Action | Behaviour | Default when present |
|---|---|---|
| `ALLOW` | Permit matching requests | Deny everything NOT explicitly allowed |
| `DENY` | Block matching requests | Allow everything NOT explicitly denied |
| `AUDIT` | Log matching requests | No effect on traffic |

> ⚠️ **Critical Rule:** `DENY` always takes precedence over `ALLOW`. If a request matches both a DENY and an ALLOW policy, it is denied.

### Practical 1 — Deny All Traffic to productpage

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: productpage-deny-all
  namespace: default
spec:
  selector:
    matchLabels:
      app: productpage
  action: DENY
  rules:
  - {}    # empty rule = match all requests
```

```bash
# Test — should return 403
kubectl exec -it $(kubectl get pod -l app=ratings -o jsonpath='{.items[0].metadata.name}') \
  -c ratings -- curl -s -o /dev/null -w "%{http_code}\n" productpage:9080/productpage
# 403   ← Forbidden! Envoy rejected before reaching the app
```

### Practical 2 — Only reviews Can Call ratings (GET /ratings/\* Only)

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: ratings-allow-reviews-only
  namespace: default
spec:
  selector:
    matchLabels:
      app: ratings
  action: ALLOW
  rules:
  - from:
    - source:
        principals:
        - cluster.local/ns/default/sa/bookinfo-reviews
    to:
    - operation:
        methods: ["GET"]
        paths: ["/ratings/*"]
```

### Proof from Our Practical

```bash
# Test 1: reviews-v2 → ratings GET /ratings/1 (SHOULD WORK)
kubectl exec -it $(kubectl get pod -l app=reviews,version=v2 \
  -o jsonpath='{.items[0].metadata.name}') \
  -c reviews -- curl -s -o /dev/null -w "%{http_code}\n" ratings:9080/ratings/1
# 200 ✅ — principal matches, method+path allowed

# Test 2: ratings → ratings GET /ratings/1 (SHOULD BE DENIED)
kubectl exec -it $(kubectl get pod -l app=ratings \
  -o jsonpath='{.items[0].metadata.name}') \
  -c ratings -- curl -s -o /dev/null -w "%{http_code}\n" ratings:9080/ratings/1
# 403 ❌ — principal not in allow list, instant rejection
```

> 💡 **Key Insight:** The 403 was returned in **milliseconds** — Envoy rejected it before it ever touched the ratings application code. Authorization enforced at the network layer.

### Complete Security Posture Achieved

```
Layer 1: Encryption
  └─ All traffic mTLS encrypted (STRICT mode)
  └─ No plain HTTP accepted anywhere in the mesh

Layer 2: Authentication
  └─ Every workload has SPIFFE certificate identity
  └─ istiod auto-rotates certs every 24 hours
  └─ Certificate = cryptographic proof of workload identity

Layer 3: Authorization
  └─ Explicit ALLOW rules per service
  └─ HTTP method + path level granularity
  └─ Everything not explicitly allowed = 403 Forbidden
  └─ Enforced by Envoy, not application code
```

This is **zero-trust networking** — exactly what financial systems, healthcare, and regulated industries require.

---

# Appendix

## A.1 Key Commands Reference

### Installation & Verification

```bash
# Download and install
curl -L https://istio.io/downloadIstio | sh -
istioctl x precheck
istioctl install --set profile=demo -y

# Verify
kubectl get pods -n istio-system
kubectl get crd | grep istio.io | wc -l    # should be 14
kubectl get mutatingwebhookconfigurations | grep istio
```

### Debugging Commands

```bash
# See all proxies and sync state
istioctl proxy-status

# Human-readable pod mesh summary
istioctl x describe pod <pod-name>

# Inspect Envoy config
istioctl proxy-config cluster deploy/<name>      # upstream clusters
istioctl proxy-config listener deploy/<name>     # port listeners
istioctl proxy-config route deploy/<name>        # HTTP routes
istioctl proxy-config secret deploy/<name>       # TLS certificates
istioctl proxy-config endpoint deploy/<name>     # actual pod IPs

# Check specific service in cluster config
istioctl proxy-config cluster deploy/<name> --fqdn <service>.default.svc.cluster.local -o json
```

### Traffic Management

```bash
# List all traffic resources
kubectl get virtualservices
kubectl get destinationrules
kubectl get gateway

# Apply and verify
kubectl apply -f vs.yaml
istioctl proxy-config route deploy/<caller> --name 9080 -o json | grep -A5 "subset"
```

### Security

```bash
# Check mTLS policies
kubectl get peerauthentication -A

# Check authorization policies
kubectl get authorizationpolicy -A

# Inspect certificate
istioctl proxy-config secret <pod> -o json | \
  jq '.dynamicActiveSecrets[0].secret.tlsCertificate.certificateChain.inlineBytes' -r | \
  base64 -d | openssl x509 -noout -text | grep -A2 "URI\|Validity"
```

### Observability Dashboards

```bash
istioctl dashboard kiali       # http://localhost:20001
istioctl dashboard jaeger      # http://localhost:16686
istioctl dashboard prometheus  # http://localhost:9090
istioctl dashboard grafana     # http://localhost:3000
```

---

## A.2 Common Gotchas & Fixes

| # | Gotcha | Root Cause | Fix |
|---|---|---|---|
| 1 | `EXTERNAL-IP: <pending>` on IngressGateway | kind has no cloud load balancer | `kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80` |
| 2 | `verify-install` command not found | Removed in Istio 1.29.0 | Use `kubectl get pods -n istio-system` to verify |
| 3 | Weights don't sum to 100 | VS admission webhook validates | Ensure all destination weights sum to exactly 100 |
| 4 | Wildcard `*` not allowed for mesh gateway | Istio 1.29 validation rule | Create two separate VSes — one for gateway (`hosts: ["*"]`), one for mesh (`hosts: ["productpage"]`) |
| 5 | Jaeger shows only `jaeger` service, no app traces | Default sampling = 1% | Set `tracing.sampling: 100.0` and add jaeger as `defaultProviders.tracing` |
| 6 | Timeout test returned 200 after 5s | Fault delay injected server-side after connection accepted | Test from the actual calling service, not the target pod |
| 7 | `jq` command not found | Not installed by default on Ubuntu | `sudo apt install jq -y` |
| 8 | `curl` not in productpage container | Python container, no curl | Use `python3 -c "import urllib.request; ..."` or deploy debug pod |
| 9 | Deployment name not `productpage` | Actual name is `productpage-v1` | `kubectl get deploy` to see exact names first |
| 10 | Jaeger Service dropdown only shows `jaeger` | ConfigMap patch applied but pods not restarted | `kubectl rollout restart deployment -n default && -n istio-system` |

---

## A.3 Istio CRDs Reference

| CRD | API Group | Purpose |
|---|---|---|
| `VirtualService` | networking.istio.io | Traffic routing rules — weights, headers, retries, timeouts, fault injection |
| `DestinationRule` | networking.istio.io | Post-routing config — subsets, load balancing, circuit breaker, TLS settings |
| `Gateway` | networking.istio.io | Ingress/Egress gateway listener config — port, protocol, host |
| `ServiceEntry` | networking.istio.io | Register external services (outside cluster) into the mesh |
| `Sidecar` | networking.istio.io | Fine-tune sidecar scope — limit what each proxy sees (memory optimisation at scale) |
| `EnvoyFilter` | networking.istio.io | Raw Envoy config customization (expert level, escape hatch) |
| `ProxyConfig` | networking.istio.io | Per-workload proxy tuning |
| `WorkloadEntry` | networking.istio.io | Add VM/non-K8s workloads to the mesh |
| `WorkloadGroup` | networking.istio.io | Template for WorkloadEntries (VM fleets) |
| `PeerAuthentication` | security.istio.io | mTLS mode per workload/namespace/mesh |
| `AuthorizationPolicy` | security.istio.io | Service-to-service access control (ALLOW/DENY/AUDIT) |
| `RequestAuthentication` | security.istio.io | JWT token validation at the proxy |
| `Telemetry` | telemetry.istio.io | Customize metrics, tracing, access log settings per workload |
| `WasmPlugin` | extensions.istio.io | Deploy WebAssembly plugins into Envoy sidecars |

---

## A.4 xDS Protocol Reference

Istio uses the **Envoy xDS API** to push configuration from istiod to all Envoy proxies. Understanding this is key to debugging.

```
istiod ──gRPC streaming──► Envoy (per proxy)
         (xDS APIs)
```

| API | Configures | When to inspect |
|---|---|---|
| **CDS** (Cluster) | Upstream services — where traffic can go | `istioctl proxy-config cluster` |
| **LDS** (Listener) | Ports Envoy intercepts — 15001, 15006, 9080 etc. | `istioctl proxy-config listener` |
| **EDS** (Endpoint) | Actual pod IPs behind each service | `istioctl proxy-config endpoint` |
| **RDS** (Route) | HTTP routing rules — path/header matching | `istioctl proxy-config route` |
| **SDS** (Secret) | TLS certificates and keys | `istioctl proxy-config secret` |

### Special Clusters Every Proxy Has

```
BlackHoleCluster       ← drops traffic (used for deny rules, missing routes)
PassthroughCluster     ← bypasses Envoy entirely (escape hatch)
InboundPassthroughCluster ← for inbound traffic not matching any rule
xds-grpc               ← connection back to istiod (control plane channel)
prometheus_stats       ← Envoy's own metrics at :15090/stats/prometheus
```

### Special Ports Every Sidecar Listens On

```
15001  ← ALL outbound traffic intercepted here by iptables
15006  ← ALL inbound traffic intercepted here by iptables
15090  ← Envoy metrics (Prometheus scrapes this)
15021  ← Health check endpoint (/healthz/ready)
15020  ← Merged Prometheus metrics (app + Envoy combined)
```

---

*Istio Learning Notes — Phases 1–4 Complete*  
*Environment: Istio 1.29.0 on kind cluster (WSL2/Ubuntu/Windows 10)*  
*Generated: April 2026*

> 📝 **Note:** Phase 5 (Advanced Topics) notes will be added upon completion —  
> covering Ingress TLS, Egress Gateway, EnvoyFilter, WASM plugins, and Istio upgrades.
