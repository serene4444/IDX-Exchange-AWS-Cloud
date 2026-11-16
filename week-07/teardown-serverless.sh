#!/bin/bash
# Week 07 cleanup: API -> Lambda (+ its log group) -> IAM role -> DynamoDB table -> SQS queues.
set -uo pipefail
export AWS_REGION=us-east-2 AWS_DEFAULT_REGION=us-east-2 AWS_PAGER="" MSYS_NO_PATHCONV=1
q() { aws "$@" --output text; }

for api in $(q apigatewayv2 get-apis --query "Items[?Name=='property-api'].ApiId"); do
  echo "Deleting HTTP API $api"; aws apigatewayv2 delete-api --api-id "$api"
done
aws lambda delete-function --function-name get-property >/dev/null 2>&1 && echo "Deleted Lambda get-property"
aws logs delete-log-group --log-group-name /aws/lambda/get-property 2>/dev/null && echo "Deleted log group"
if aws iam get-role --role-name get-property-role >/dev/null 2>&1; then
  aws iam delete-role-policy --role-name get-property-role --policy-name dynamodb-read-properties
  aws iam detach-role-policy --role-name get-property-role --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
  aws iam delete-role --role-name get-property-role && echo "Deleted IAM role get-property-role"
fi
if aws dynamodb describe-table --table-name Properties >/dev/null 2>&1; then
  aws dynamodb delete-table --table-name Properties >/dev/null && aws dynamodb wait table-not-exists --table-name Properties
  echo "Deleted DynamoDB table Properties"
fi
for n in property-queue property-dlq; do
  u=$(q sqs get-queue-url --queue-name $n --query QueueUrl 2>/dev/null) && aws sqs delete-queue --queue-url "$u" && echo "Deleted queue $n"
done

echo
echo "Leftover check (all should be empty):"
echo "  APIs:    $(q apigatewayv2 get-apis --query "Items[?Name=='property-api'].ApiId")"
echo "  Lambda:  $(q lambda list-functions --query "Functions[?FunctionName=='get-property'].FunctionName")"
echo "  Role:    $(q iam list-roles --query "Roles[?RoleName=='get-property-role'].RoleName")"
echo "  Tables:  $(q dynamodb list-tables --query "TableNames[?@=='Properties']")"
echo "  Queues:  $(q sqs list-queues --queue-name-prefix property- --query QueueUrls)"
