#Normal users  ──────────────────────► reviews-v1 (stable, no stars)
#QA engineer   ── header: user=vidhan ► reviews-v3 (new version, red stars)
cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: reviews
spec:
  hosts:
  - reviews
  http:
  - match:
    - headers:
        end-user:
          exact: vidhan
    route:
    - destination:
        host: reviews
        subset: v3
  - route:
    - destination:
        host: reviews
        subset: v1
EOF