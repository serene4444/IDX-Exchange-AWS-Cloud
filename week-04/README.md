# Week 04: Storage & Databases

Regions: RDS is in **us-east-2 (Ohio)**, next to my Week 3 instance `property-api-01`, which I reused as the client. RDS and the EC2 instance that connects to it must be in the same region and VPC. S3 and DynamoDB are in us-east-1, my CLI default.

## Lab 4.1: S3 bucket with a lifecycle rule

```bash
aws s3 mb s3://my-training-bucket-sereneplummer
aws s3 cp week-03/runbook.md s3://my-training-bucket-sereneplummer/
aws s3 ls s3://my-training-bucket-sereneplummer/
aws s3api put-bucket-lifecycle-configuration --bucket my-training-bucket-sereneplummer \
  --lifecycle-configuration file://week-04/lifecycle.json
aws s3api get-bucket-lifecycle-configuration --bucket my-training-bucket-sereneplummer
```

The rule `archive-after-30-days` ([lifecycle.json](./lifecycle.json)) moves every object to Glacier Flexible Retrieval after 30 days. Everything else uses the bucket defaults: Block Public Access is on and encryption is SSE-S3.

## Lab 4.2: RDS MySQL and PII cleanup

**Setup:** MySQL 8.0, Free tier template, instance `training-db`, user `admin`, **not publicly accessible**, default VPC. The password lives in my password manager and is never committed.

**Connecting:** I connect from `property-api-01` (Week 3), which is in the same default VPC. The RDS security group allows **MySQL 3306 from the EC2 instance's security group ID**, not from an IP. That's the "security group references security group" pattern (Debug Lab 4.4).

**Import:** `rets_property.sql` is a raw production export (about 660 MB) with real agents' names, emails, and phone numbers. It is gitignored and never uploaded to S3. I compressed it, copied it to the EC2 instance with `scp`, and imported it as-is:

```bash
mysql -h <rds-endpoint> -u admin -p -e "CREATE DATABASE training_data;"
gunzip -c rets_property.sql.gz | mysql -h <rds-endpoint> -u admin -p training_data
```

**Sanitize before any analysis:** [pii-cleanup.sql](./pii-cleanup.sql) does three things:

1. Drops 21 identifying columns: the handbook's 17, plus 4 I added after reading the actual schema.
   - `L_DisplayId` is the public MLS number, so keeping it would undo the ID remap.
   - `L_Remarks` is free-text agent remarks, which often contain names and phone numbers.
   - `LO1_OrganizationName` and `ListAgentAOR` identify the agent's brokerage and association.
2. Replaces the real `L_ListingID` with synthetic IDs (`R100001`, `R100002`, …) using `ROW_NUMBER() OVER (ORDER BY id)`. That needs MySQL 8.
3. Makes the synthetic ID the primary key.

   **Fix vs the handbook:** the dump already defines `id` as an `AUTO_INCREMENT PRIMARY KEY`, so a bare `ADD PRIMARY KEY (L_ListingID)` fails with *"Multiple primary key defined"*. The script removes `AUTO_INCREMENT`, drops the old primary key, and adds the new one in a single `ALTER`.

**Verification:** `pii_columns_remaining = 0`, `ids_not_synthetic = 0`, and the city/price aggregate returns real data. Screenshot: [rds-cleanup.png](./rds-cleanup.png)

**Afterward:** I deleted `rets_property.sql` from my laptop and from the EC2 instance. The raw file still contains PII even after the database copy is clean.

## Lab 4.3: DynamoDB

```bash
aws dynamodb create-table --table-name Properties \
  --attribute-definitions AttributeName=L_ListingID,AttributeType=S \
  --key-schema AttributeName=L_ListingID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
aws dynamodb wait table-exists --table-name Properties
```

I loaded one row taken from the **sanitized** RDS table (`SELECT L_ListingID, L_City, L_Keyword2, L_SystemPrice FROM rets_property LIMIT 1;`) using `put-item`, then read it back with `get-item`. Screenshot: [dynamodb-get-item.png](./dynamodb-get-item.png)

`PAY_PER_REQUEST` (on-demand) means there's no capacity planning and I'm billed per request, which suits low or unpredictable traffic. `L_ListingID` is the partition key because the app's main access pattern is "get one listing by ID."

## Debug Lab 4.4: RDS connection times out

A **timeout** means the network blocked the connection. An "Access denied for user" error would mean a bad password instead. Check these:

- Does the RDS security group allow 3306 from the EC2 instance's **security group**?
- Are RDS and EC2 in the same VPC and region?

The usual cause is a missing inbound rule.

## Cleanup

- `aws dynamodb delete-table --table-name Properties`
- RDS → `training-db` → Delete. I skipped the final snapshot and didn't retain automated backups.
- Terminate `property-api-01`, then delete its security group and the Week 3 snapshot.
- Delete the S3 object and lifecycle rule while the object is still in Standard. Glacier has a 90-day minimum charge.
- Delete `rets_property.sql` and the `.gz` everywhere they were copied.
- Billing check: [billing-screenshot.png](./billing-screenshot.png)

## Deliverable

[decision-guide.md](./decision-guide.md): S3 vs EBS vs EFS vs RDS vs DynamoDB.
