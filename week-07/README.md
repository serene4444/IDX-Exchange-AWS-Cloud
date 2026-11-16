# Week 07: Serverless & Event-Driven Architecture

Region: **us-east-2 (Ohio)**, because of my org's SCP. Date run: 2026-11-15.

This week takes PropertyLite's existing `GET /properties/<listing_id>` route and re-hosts it **serverless**. There's no new business logic, just the same lookup without an always-on EC2 instance.

## Request path

```text
curl GET https://<api-id>.execute-api.us-east-2.amazonaws.com/properties/R100234
  │
  ▼
API Gateway HTTP API "property-api"
  route  GET /properties/{id}  ──►  integration AWS_PROXY (payload v2.0)
  │       (any other path → API Gateway's own 404, Lambda never runs)
  ▼
Lambda "get-property" (Python 3.12)       ◄── resource policy: only this API's
  event["pathParameters"]["id"] = "R100234"     GET /properties/{id} route may invoke
  │  assumes execution role get-property-role
  ▼
DynamoDB table "Properties"  GetItem(L_ListingID = "R100234")
  │                                       role allows dynamodb:GetItem on this
  ▼                                       one table ARN, nothing else
{"L_City": "Sacramento", ...}  → 200     (missing item → 404 {"error": "not found"})
  │
  └─ logs ──► CloudWatch Logs /aws/lambda/get-property
```

## Files

| File | What it is |
| --- | --- |
| [lambda/get_property.py](./lambda/get_property.py) | The deployed function (handbook code + 2 fixes, explained below) |
| [lambda/get_property_handbook.py](./lambda/get_property_handbook.py) | The handbook's Step 62 code verbatim, kept to reproduce its bug |
| [policies/get-property-dynamodb-read.json](./policies/get-property-dynamodb-read.json) | Least-privilege execution-role policy |
| [build-serverless.sh](./build-serverless.sh) | Creates the table + data, role, Lambda, HTTP API, and SQS queues |
| [teardown-serverless.sh](./teardown-serverless.sh) | Deletes all of it, with a leftover check |
| [curl-collection.sh](./curl-collection.sh) / [curl-collection-output.txt](./curl-collection-output.txt) | Request collection and a recorded run |

## Lab 7.1: API Gateway → Lambda → DynamoDB

**Data:** the `Properties` table is loaded from the 3 rows in [propertylite/rets_property_sample.csv](../propertylite/rets_property_sample.csv). Those rows already use synthetic `R1xxxxx` IDs and contain no PII. My Week 4 RDS instance (the sanitized `rets_property` table) was deleted at the end of Week 4, and the handbook says never to pull rows from the raw `.sql` file.

**Result:**

```text
$ curl https://<api-id>.execute-api.us-east-2.amazonaws.com/properties/R100234
{"LM_Dec_3": "2", "LM_Int2_3": "1450", "L_City": "Sacramento", "L_Keyword2": "3", "L_ListingID": "R100234", "L_Status": "Active", "L_SystemPrice": "450000"}
[HTTP 200]
```

That matches the Flask app's response from Week 6's ALB: same keys and same string values, with one exception. `LM_Dec_3` is `"2"` instead of `"2.0"`. **DynamoDB Numbers are normalized** (`2.0` is stored as `2`), so a trailing zero that only existed as CSV text doesn't survive. If the exact text mattered, I'd store that attribute as a String.

**Cold vs warm start:** the first request took **1.98 s** and the next one took **0.32 s**. The first call pays for a new execution environment: downloading the code, starting Python, and running the module-level `boto3.resource(...)`. Warm calls reuse all of that, which is why the DynamoDB client is created outside the handler.

### Why the role only reaches `Properties`

The execution role has exactly two policies:

1. **Inline `dynamodb-read-properties`:** `dynamodb:GetItem` on `arn:aws:dynamodb:us-east-2:548848855009:table/Properties` only. It allows no `Scan`, no writes, and no other tables. Even if the function's code were compromised, it could read single items from this one table and nothing else.
2. **`AWSLambdaBasicExecutionRole`:** permission to write its own CloudWatch logs. The console adds this automatically when it creates a role, but the handbook's CLI-style steps don't mention it. Without it, Debug Lab 7.3 is impossible because there are no logs to read.

Verified with the IAM policy simulator:

| Action | Resource | Decision |
| --- | --- | --- |
| `dynamodb:GetItem` | `table/Properties` | ✅ allowed |
| `dynamodb:Scan` | `table/Properties` | implicitDeny |
| `dynamodb:PutItem` | `table/Properties` | implicitDeny |
| `dynamodb:DeleteTable` | `table/Properties` | implicitDeny |
| `dynamodb:GetItem` | `table/OtherTable` | implicitDeny |

**Simulator gotcha:** without `--context-entries ContextKeyName=aws:RequestedRegion,ContextKeyValues=us-east-2,ContextKeyType=string`, *every* action shows **explicitDeny**, including the allowed `GetItem`. The simulator doesn't fill in a region by default, so my org's region-lock SCP denies everything.

**Who can invoke it:** this is the resource-based side. `lambda add-permission` lets `apigateway.amazonaws.com` invoke the function only when the source ARN is this API's `GET /properties/{id}` route.

## Lab 7.2: SQS with a dead-letter queue

`property-queue` has a redrive policy: after **3** receives without a delete, a message moves to `property-dlq`.

```text
send  {"L_ListingID":"R100234"}
receive 1 → body, ApproximateReceiveCount=1   (not deleted; visibility timeout 2 s)
receive 2 → body, ApproximateReceiveCount=2
receive 3 → body, ApproximateReceiveCount=3
receive 4 on property-queue → nothing
receive   on property-dlq   → {"L_ListingID":"R100234"}  ✅
```

The handbook's sample message uses `"PropertyId":"P1002"`. I used `L_ListingID` with a real sample ID so it matches the rest of PropertyLite. A DLQ turns a "poison" message, one that fails every time it's processed, from an infinite retry loop into something parked where I can inspect it and alarm on it.

## Debug Lab 7.3: API Gateway returns 500 (reproduced both ways)

In both cases the API returned only `{"message":"Internal Server Error"}`. **CloudWatch Logs** (`/aws/lambda/get-property`) gave the real cause:

**a) The handbook's own code:**

```text
[ERROR] TypeError: Object of type Decimal is not JSON serializable
```

boto3 returns DynamoDB Numbers as `decimal.Decimal`, and `json.dumps` can't serialize them. The handbook loads `R100234` with `L_Keyword2` and `L_SystemPrice` as Numbers (`"N"`), so its own Step 62 code returns **500 on the handbook's own test item**. **Fix:** `json.dumps(item, default=str)`. That also makes the output match the Flask app, which returns strings.

**b) Policy scoped to the wrong table (`table/Property`):**

```text
[ERROR] ClientError: ... (AccessDeniedException) when calling the GetItem operation:
User: arn:aws:sts::548848855009:assumed-role/get-property-role/get-property is not authorized
to perform: dynamodb:GetItem on resource: .../table/Properties
because no identity-based policy allows the dynamodb:GetItem action
```

The error names the *exact* resource that was requested (`Properties`). Comparing that with the policy's `Resource` (`Property`) shows the typo right away.

**IAM propagation surprised me.** After I put the correct policy back, the API kept returning 500 for about **5 minutes** before it started working. IAM is eventually consistent, so "I fixed the policy but it still fails" doesn't always mean the fix is wrong. Re-check the policy, then wait and retry before changing anything else.

**Also fixed:** the handbook code returns **200 `{}`** for a listing that doesn't exist. Mine returns **404 `{"error": "not found"}`**, the same as `propertylite/app.py`.

**Lesson:** never debug a Lambda from the API response. Lambda → Monitor → View CloudWatch logs shows the actual exception every time.

## Cleanup

`bash week-07/teardown-serverless.sh` deleted the API, function, log group, role, table, and both queues, and the leftover check was empty. Everything this week is pay-per-request, so the cost was effectively $0.

> **To do (me):** add `billing-screenshot.png` from the Billing console.
