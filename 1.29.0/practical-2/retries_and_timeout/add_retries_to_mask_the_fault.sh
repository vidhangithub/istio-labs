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
      abort:
        httpStatus: 500
        percentage:
          value: 50
    retries:
      attempts: 3
      perTryTimeout: 2s
      retryOn: 5xx
    route:
    - destination:
        host: ratings
        subset: v1
EOF