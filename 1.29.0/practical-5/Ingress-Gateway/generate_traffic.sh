# First generate some traffic through the gateway
for i in $(seq 1 30); do
  curl -s http://localhost:8080/productpage > /dev/null
  sleep 0.5
done