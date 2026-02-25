cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: productpage
spec:
  hosts:
  - "*"
  gateways:
  - bookinfo-gateway          # bind to our gateway
  - mesh                      # also keep internal mesh routing
  http:
  - route:
    - destination:
        host: productpage
        subset: v1
        port:
          number: 9080
EOF