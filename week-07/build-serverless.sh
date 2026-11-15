#!/bin/bash
# Week 07, Labs 7.1 + 7.2: PropertyLite's read path on API Gateway (HTTP API) -> Lambda -> DynamoDB,
# plus an SQS queue with a dead-letter queue.
# Region is us-east-2: my org's SCP only allows Ohio.
set -euo pipefail
export AWS_REGION=us-east-2 AWS_DEFAULT_REGION=us-east-2 MSYS_NO_PATHCONV=1 AWS_PAGER=""
HERE="$(cd "$(dirname "$0")" && pwd)"
HERE_W="$(cd "$HERE" && pwd -W 2>/dev/null || pwd)"   # Windows-style path for file:// / fileb:// on Git Bash
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
PY=$(command -v python3 || command -v python)

# --- DynamoDB: Properties table, loaded from the sanitized sample rows --------------
aws dynamodb create-table --table-name Properties \
  --attribute-definitions AttributeName=L_ListingID,AttributeType=S \
  --key-schema AttributeName=L_ListingID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --tags Key=Project,Value=week-07 >/dev/null
aws dynamodb wait table-exists --table-name Properties
# One put-item per CSV row. Numeric columns are stored as DynamoDB Numbers (N), like the handbook.
"$PY" - "$HERE_W/../propertylite/rets_property_sample.csv" <<'PYEOF' | while IFS= read -r item; do
import csv, json, sys
NUM = {"L_Keyword2", "LM_Dec_3", "LM_Int2_3", "L_SystemPrice"}
for row in csv.DictReader(open(sys.argv[1], newline="")):
    print(json.dumps({k: {"N" if k in NUM else "S": v} for k, v in row.items()}))
PYEOF
  aws dynamodb put-item --table-name Properties --item "$item"
done
echo "Properties table: $(aws dynamodb scan --table-name Properties --select COUNT --query Count --output text) items"

# --- IAM: execution role scoped to this one table -----------------------------------
aws iam create-role --role-name get-property-role --tags Key=Project,Value=week-07 \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
aws iam put-role-policy --role-name get-property-role --policy-name dynamodb-read-properties \
  --policy-document "file://$HERE_W/policies/get-property-dynamodb-read.json"
# CloudWatch Logs permission. The console adds this automatically; the CLI doesn't.
aws iam attach-role-policy --role-name get-property-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
sleep 10   # new roles take a few seconds before Lambda can assume them

# --- Lambda --------------------------------------------------------------------------
"$PY" -c "import sys,zipfile; z=zipfile.ZipFile(sys.argv[1],'w'); z.write(sys.argv[2],'get_property.py'); z.close()" \
  "$HERE_W/lambda/function.zip" "$HERE_W/lambda/get_property.py"
FN_ARN=$(aws lambda create-function --function-name get-property --runtime python3.12 \
  --handler get_property.lambda_handler --role "arn:aws:iam::$ACCOUNT:role/get-property-role" \
  --zip-file "fileb://$HERE_W/lambda/function.zip" --tags Project=week-07 \
  --query FunctionArn --output text)
aws lambda wait function-active-v2 --function-name get-property
rm -f "$HERE/lambda/function.zip"
echo "Lambda: $FN_ARN"

# --- API Gateway HTTP API: GET /properties/{id} -> get-property ---------------------
API=$(aws apigatewayv2 create-api --name property-api --protocol-type HTTP --tags Project=week-07 \
  --query ApiId --output text)
INTEG=$(aws apigatewayv2 create-integration --api-id "$API" --integration-type AWS_PROXY \
  --integration-uri "$FN_ARN" --payload-format-version 2.0 --query IntegrationId --output text)
aws apigatewayv2 create-route --api-id "$API" --route-key 'GET /properties/{id}' \
  --target "integrations/$INTEG" >/dev/null
aws apigatewayv2 create-stage --api-id "$API" --stage-name '$default' --auto-deploy >/dev/null
# Resource-based policy: let this API (and only this route) invoke the function
aws lambda add-permission --function-name get-property --statement-id apigw-get-property \
  --action lambda:InvokeFunction --principal apigateway.amazonaws.com \
  --source-arn "arn:aws:execute-api:us-east-2:$ACCOUNT:$API/*/GET/properties/{id}" >/dev/null
URL="https://$API.execute-api.us-east-2.amazonaws.com"
echo "API: $URL/properties/R100234"

# --- Lab 7.2: SQS queue with a dead-letter queue -----------------------------------
DLQ_URL=$(aws sqs create-queue --queue-name property-dlq --tags Project=week-07 --query QueueUrl --output text)
DLQ_ARN=$(aws sqs get-queue-attributes --queue-url "$DLQ_URL" --attribute-names QueueArn --query Attributes.QueueArn --output text)
Q_URL=$(aws sqs create-queue --queue-name property-queue --tags Project=week-07 \
  --attributes "{\"RedrivePolicy\":\"{\\\"deadLetterTargetArn\\\":\\\"$DLQ_ARN\\\",\\\"maxReceiveCount\\\":\\\"3\\\"}\"}" \
  --query QueueUrl --output text)
echo "SQS: $Q_URL (DLQ $DLQ_URL, maxReceiveCount 3)"
