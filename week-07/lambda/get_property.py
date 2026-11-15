"""get-property: PropertyLite's GET /properties/<listing_id> route, re-hosted on Lambda.

Same lookup as propertylite/app.py's get_property(), but it reads one item from the
DynamoDB Properties table instead of scanning rets_property_sample.csv.

Two fixes vs the handbook's Step 62 code:
  1. DynamoDB returns numbers as decimal.Decimal, which json.dumps can't serialize.
     The handbook code crashes (500) on any item with a Number attribute, which includes
     the R100234 item the handbook itself loads. default=str fixes it, and it also makes
     the output match PropertyLite exactly, since the Flask app returns CSV values as strings.
  2. A missing listing returns 404 {"error": "not found"}, like the Flask app,
     instead of 200 {}.
"""
import json

import boto3

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table("Properties")


def lambda_handler(event, context):
    listing_id = event["pathParameters"]["id"]
    resp = table.get_item(Key={"L_ListingID": listing_id})
    item = resp.get("Item")
    if item is None:
        return _response(404, {"error": "not found"})
    return _response(200, item)


def _response(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, default=str, sort_keys=True),
    }
