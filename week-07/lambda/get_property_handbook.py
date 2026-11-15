# The handbook's Step 62 code, verbatim. Kept only to reproduce the Decimal bug
# (see README "Debug Lab 7.3"). The deployed version is get_property.py.
import json, boto3
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('Properties')

def lambda_handler(event, context):
    listing_id = event['pathParameters']['id']
    resp = table.get_item(Key={'L_ListingID': listing_id})
    return {
        'statusCode': 200,
        'body': json.dumps(resp.get('Item', {}))
    }
