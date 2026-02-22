# Hit 10 times again - should see mostly 200s now
for i in $(seq 1 10); do
  kubectl exec -it $(kubectl get pod -l app=ratings -o jsonpath='{.items[0].metadata.name}') \
    -c ratings -- curl -s -o /dev/null -w "%{http_code}\n" productpage:9080/productpage
done