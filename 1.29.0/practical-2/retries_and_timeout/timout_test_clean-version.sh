# Apply 5s delay on ALL requests + 2s timeout
cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: ratings
spec:
  hosts:
  - ratings
  http:
  - fault:
      delay:
        percentage:
          value: 100
        fixedDelay: 5s
    timeout: 2s
    route:
    - destination:
        host: ratings
        subset: v1
EOF