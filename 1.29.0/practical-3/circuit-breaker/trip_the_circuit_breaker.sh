FORTIO_POD=$(kubectl get pod -l app=fortio -o jsonpath='{.items[0].metadata.name}')

# 3 concurrent connections - exceeds maxConnections:1
kubectl exec -it $FORTIO_POD -c fortio -- \
  fortio load -c 3 -qps 0 -n 20 -quiet http://ratings:9080/ratings/1