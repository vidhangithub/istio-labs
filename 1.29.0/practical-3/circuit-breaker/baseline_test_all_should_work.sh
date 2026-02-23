FORTIO_POD=$(kubectl get pod -l app=fortio -o jsonpath='{.items[0].metadata.name}')

# 20 requests, 1 at a time - all should succeed
kubectl exec -it $FORTIO_POD -c fortio -- \
  fortio load -c 1 -qps 0 -n 20 -quiet http://ratings:9080/ratings/1