# Remove circuit breaker from ratings, restore clean DestinationRule
cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: ratings
spec:
  host: ratings
  subsets:
  - name: v1
    labels:
      version: v1
EOF