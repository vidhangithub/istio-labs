# Hit ratings service directly - should see 500s 50% of the time
for i in $(seq 1 10); do
  kubectl exec -it $(kubectl get pod -l app=ratings -o jsonpath='{.items[0].metadata.name}') \
    -c ratings -- curl -s -o /dev/null -w "%{http_code}\n" ratings:9080/ratings/1
done