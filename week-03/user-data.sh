#!/bin/bash
# EC2 user data for property-api-01 (Amazon Linux 2023).
# Runs once as root on first boot. Log: /var/log/cloud-init-output.log
yum update -y
yum install -y python3 python3-pip
pip3 install flask==3.0.3
mkdir -p /opt/property-api

cat > /opt/property-api/app.py << 'PYEOF'
import csv
import os

from flask import Flask, jsonify, request

app = Flask(__name__)
DATA_PATH = os.environ.get("PROPERTY_DATA_PATH", "rets_property_sample.csv")


def load_properties():
    with open(DATA_PATH, newline="") as f:
        return list(csv.DictReader(f))


@app.route("/health")
def health():
    return jsonify(status="ok")


@app.route("/properties")
def list_properties():
    city = request.args.get("city")
    rows = load_properties()
    if city:
        rows = [r for r in rows if r.get("L_City", "").lower() == city.lower()]
    return jsonify(rows[:50])


@app.route("/properties/<listing_id>")
def get_property(listing_id):
    rows = load_properties()
    match = next((r for r in rows if r.get("L_ListingID") == listing_id), None)
    if not match:
        return jsonify(error="not found"), 404
    return jsonify(match)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
PYEOF

cat > /opt/property-api/rets_property_sample.csv << 'CSVEOF'
L_ListingID,L_City,L_Keyword2,LM_Dec_3,LM_Int2_3,L_SystemPrice,L_Status
R100234,Sacramento,3,2.0,1450,450000,Active
R100235,Fresno,4,2.5,1900,395000,Active
R100236,Sacramento,2,1.0,900,299000,Pending
CSVEOF

cd /opt/property-api && nohup python3 app.py > /var/log/property-api.log 2>&1 &
