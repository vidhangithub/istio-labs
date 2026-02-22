# Hit the app 20 times and count which version responds
for i in $(seq 1 20); do
  kubectl exec -it $(kubectl get pod -l app=ratings -o jsonpath='{.items[0].metadata.name}') \
    -c ratings -- curl -s productpage:9080/productpage | grep -o "glyphicon-star\|Reviewer1" | head -1
done