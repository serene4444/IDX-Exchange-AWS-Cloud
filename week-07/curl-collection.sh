#!/bin/bash
# Week 07 curl collection: PropertyLite's serverless read path.
# Usage: API=https://<api-id>.execute-api.us-east-2.amazonaws.com bash curl-collection.sh
set -u
API=${API:?set API to the HTTP API base URL}

run() { echo "== $1"; echo "\$ curl $2"; curl -s -w "\n[HTTP %{http_code}, %{time_total}s]\n\n" "$2"; }

run "Existing listing (first call may include a Lambda cold start)" "$API/properties/R100234"
run "Same listing again (warm)"                                     "$API/properties/R100234"
run "Another listing"                                               "$API/properties/R100236"
run "Unknown listing -> 404, same as the Flask app"                 "$API/properties/R999999"
run "Route that doesn't exist -> API Gateway's own 404"             "$API/properties"
