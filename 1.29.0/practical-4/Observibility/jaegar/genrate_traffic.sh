# Generate 50 requests to create traces
for i in $(seq 1 50); do
  kubectl exec -it $(kubectl get pod -l app=ratings -o jsonpath='{.items[0].metadata.name}') \
    -c ratings -- curl -s productpage:9080/productpage > /dev/null
  sleep 0.3
done