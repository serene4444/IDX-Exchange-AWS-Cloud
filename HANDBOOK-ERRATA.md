# Handbook Errata: Weeks 0–7

Corrections to the *IDX Exchange AWS Cloud Engineer Track Intern Handbook*, found while working through the labs. Each entry gives the location, the problem, and copy-paste-ready replacement text. Step numbers follow the handbook's continuous numbering (1–81).

## 1. Week 3, Lab 3.1, Step 28: user data script has a placeholder instead of the app

**Problem:** the script writes `app.py` as a single comment line:

```bash
cat > /opt/property-api/app.py << 'PYEOF'
# ... (same app.py content from Week 0) ...
PYEOF
```

EC2 runs user data exactly as written; nothing fills in that placeholder. On boot, `app.py` contains only a comment, so `python3 app.py` exits immediately, port 8080 never opens, and the "You'll know it worked when" `curl` check times out.

**Fix:** replace the Step 28 code block with this fully inlined script. It's also in the repo as [week-03/user-data.sh](./week-03/user-data.sh). Save it with LF line endings: CRLF breaks the `#!/bin/bash` line.

```bash
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
```

**Tested:** launched on Amazon Linux 2023 / t3.micro. `curl http://<public-ip>:8080/health` returned `{"status":"ok"}` and `/properties/R100234` returned the Sacramento listing.

**Suggested addition to "Common mistakes":** user data runs only on first boot, and `nohup` doesn't survive a reboot. After a stop/start (or after restoring from the Lab 3.2 snapshot), the app won't be running until you start it again manually.

## 2. Week 4, Lab 4.2, Step 37: wrong step reference

**Problem:** Step 37 says *"required — step 10 below uses ROW_NUMBER()"*. The handbook numbers steps continuously, so there's no step 10 in Lab 4.2. The `ROW_NUMBER()` query is in **Step 46**.

**Fix:** replace Step 37 with:

> Console → RDS → Create database → Standard create → MySQL → Engine Version: MySQL 8.0.x (required — Step 46 below uses `ROW_NUMBER()`, which doesn't exist before MySQL 8.0)

## 3. Week 2, Lab 2.1 / Debug Lab 2.3: the bucket is never created

**Problem:** Debug Lab 2.3 runs `aws s3 cp file.txt s3://my-training-bucket-<yourname>/ --profile s3test`, but the bucket isn't created until Week 4 (Lab 4.1). On a fresh account this fails with **`NoSuchBucket`**. That's a bucket-existence error, not the IAM `AccessDenied` the debug lab is about, so students end up debugging the wrong problem.

**Fix:** insert this as a new first step in Lab 2.1, before Step 16:

> **Prerequisite: create the training bucket (as your admin user, not `s3test`).**
> ```bash
> aws s3 mb s3://my-training-bucket-<yourname> --region us-east-1
> aws s3 ls | grep my-training-bucket-<yourname>
> ```
> *You'll know it worked when:* the second command prints your bucket. Bucket names are globally unique; if `mb` fails with `BucketAlreadyExists`, add a suffix (e.g. `-2026`) and use that name everywhere below.

Then add to the end of Lab 2.1:

> Prove the Allow works, too: `echo test > file.txt` then `aws s3 cp file.txt s3://my-training-bucket-<yourname>/ --profile s3test`. *You'll know it worked when:* it prints `upload: ./file.txt to s3://…`, while `aws s3 ls --profile s3test` still returns AccessDenied.

And update Lab 4.1 so `aws s3 mb` is marked *"skip if you already created this bucket in Week 2."*

**Suggested addition to Debug Lab 2.3:** read the end of the error message first. It names the layer that blocked you. `NoSuchBucket` means the bucket doesn't exist. `AccessDenied` with no "explicit deny" wording means nothing allowed the action. `explicit deny in an identity-based policy` points to an IAM Deny. `explicit deny in a service control policy` means an AWS Organizations SCP blocked it, and no IAM change inside the account can fix that.

## 4. Week 4, Lab 4.2, Step 46: `ADD PRIMARY KEY` fails on the real dump

**Problem:** the provided `rets_property.sql` already defines `id` as an `AUTO_INCREMENT PRIMARY KEY`. The last line of Step 46, `ALTER TABLE rets_property ADD PRIMARY KEY (L_ListingID);`, fails with **`ERROR 1068: Multiple primary key defined`**. Dropping the old key on its own also fails, because MySQL requires an AUTO_INCREMENT column to stay indexed.

**Fix:** replace the last line of Step 46 with:

```sql
ALTER TABLE rets_property
  MODIFY id INT NOT NULL,
  DROP PRIMARY KEY,
  ADD PRIMARY KEY (L_ListingID);
```

## 5. Week 4, Lab 4.2, Step 44: PII column list is incomplete

**Problem:** after the 17 listed columns are dropped and `L_ListingID` is remapped, the table still contains:

- **`L_DisplayId`**: the public-facing MLS number. It maps each row straight back to a live listing, which defeats Step 46's remap.
- **`L_Remarks`**: free-text agent remarks, which often include agent names and phone numbers.
- **`LO1_OrganizationName`** and **`ListAgentAOR`**: the agent's brokerage and association.

**Fix:** add these to the end of the Step 44 statement:

```sql
  DROP COLUMN L_DisplayId, DROP COLUMN L_Remarks,
  DROP COLUMN LO1_OrganizationName, DROP COLUMN ListAgentAOR;
```

Also change Step 45's text from *"none of the 17 columns"* to *"none of the 21 columns"*.

A complete corrected script, with built-in verification queries, is in [week-04/pii-cleanup.sql](./week-04/pii-cleanup.sql).

## 6. Week 0, Step 2: Windows install commands don't apply

**Problem:** the "or" AWS CLI install line uses `AWSCLIV2.pkg` and `installer -pkg`, which are both macOS-only, and `brew` isn't available on Windows.

**Fix:** add a Windows line:

```text
# Windows (PowerShell, or inside WSL2 use the Linux zip installer):
msiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi
```

## 7. All weeks: a stale system proxy breaks the AWS CLI on Windows

**Not a handbook bug, but worth a Common-mistakes line in Week 1.** If a VPN, ad blocker, or inspection tool sets a Windows system proxy and then exits, every CLI call fails with `Failed to connect to proxy URL: "http://127.0.0.1:<port>"`, even with no `HTTP(S)_PROXY` environment variables set. That's because the CLI also reads the proxy from Windows Internet Settings.

- **Workaround for one session:** `$env:NO_PROXY='*'`
- **Permanent fix:** Settings → Network & internet → Proxy → Manual proxy setup → turn off **Use a proxy server**.

## 8. Week 6, Lab 6.2: `amazon-linux-extras` doesn't exist on Amazon Linux 2023

**Problem:** Week 3 and Week 6 both specify the **Amazon Linux 2023** AMI, but Lab 6.2 runs `sudo amazon-linux-extras install epel -y`, an Amazon Linux **2** tool. On AL2023 it fails with `amazon-linux-extras: command not found` (exit 127).

**Fix:** replace the Lab 6.2 stress commands with:

```bash
sudo dnf install -y stress-ng
stress-ng --cpu 2 --timeout 300
```

## 9. Week 6, Lab 6.2: stressing one instance may not trigger scale-out

**Problem:** the ASG runs **2** instances and the target is **50% average** CPU. Stressing one instance gives one at 100% and one at about 0%, which averages to about 50%. That doesn't reliably *exceed* the target, so the "You'll know it worked when" check may never happen. The instances are also in **private subnets** with no bastion in this lab, so "SSH into an instance" isn't possible as written.

**Fix:** stress **every** instance in the group, without SSH, using SSM Run Command. Give the launch template an instance profile with `AmazonSSMManagedInstanceCore`, then run:

```bash
aws ssm send-command --document-name AWS-RunShellScript \
  --targets Key=tag:aws:autoscaling:groupName,Values=<your-asg-name> \
  --parameters 'commands=["dnf install -y stress-ng","nohup stress-ng --cpu 2 --timeout 600 >/tmp/stress.log 2>&1 &"]'
```

**Suggested addition:** turn on **detailed monitoring** in the launch template. With basic (5-minute) metrics, target tracking needs about 15 minutes to scale out. With 1-minute metrics it took about 4 minutes in my run.

## 10. Week 6, Debug Lab 6.3: the symptom is 504, not 502

**Problem:** when the instance SG doesn't allow 8080 from the ALB's SG, the ALB's connections to the targets **time out**. Reproduced: all targets showed `unhealthy (Target.Timeout)`, and the ALB returned **`504 Gateway Time-out`** after about 10 s. A **502 Bad Gateway** comes from a *refused or reset* connection: the SG is open but nothing is listening on 8080, or the app crashed. Students who see a 504 won't match it to this lab.

**Fix:** change the Debug Lab 6.3 symptom to *"returns 504 Gateway Time-out (or 503 if no targets are registered)"*. Then add: *"A 502 instead means the ALB reached the instance but the app refused or dropped the connection. Check that the app is running and listening on 8080."*

## 11. Week 7, Lab 7.1, Step 62: the Lambda code returns 500 on the handbook's own data

**Problem:** Lab 4.3 (and Step 60, which reuses it) loads `R100234` with `L_Keyword2` and `L_SystemPrice` as DynamoDB **Numbers**. boto3 returns Numbers as `decimal.Decimal`, and `json.dumps(resp.get('Item', {}))` raises `TypeError: Object of type Decimal is not JSON serializable`. So the Step 65 `curl` returns `{"message":"Internal Server Error"}` on the first try. It also returns `200 {}` for a missing ID, while PropertyLite returns `404`.

**Fix:** replace the Step 62 code with:

```python
import json, boto3
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('Properties')

def lambda_handler(event, context):
    listing_id = event['pathParameters']['id']
    item = table.get_item(Key={'L_ListingID': listing_id}).get('Item')
    if item is None:
        return {'statusCode': 404, 'body': json.dumps({'error': 'not found'})}
    return {'statusCode': 200, 'body': json.dumps(item, default=str)}
```

**Suggested addition to Debug Lab 7.3's root causes:** *(3) `TypeError: Object of type Decimal is not JSON serializable`: DynamoDB numbers come back as `Decimal`; pass `default=str` to `json.dumps`.*

## 12. Week 7, Lab 7.1, Step 63: the role also needs CloudWatch Logs permission, and fixes take time

**Problem:** Step 63 says to attach a custom read-only DynamoDB policy, and Debug Lab 7.3 says to read the CloudWatch logs. A console-created function gets a role with log permissions automatically, but a role created any other way (CLI, and Terraform from Week 8 on) doesn't. Then the function has no logs at all.

**Fix:** add to Step 63: *"Make sure the role also has `AWSLambdaBasicExecutionRole` (the console adds it automatically; the CLI and Terraform don't)."* Also, the custom policy only needs `dynamodb:GetItem`, not all read actions. Least privilege for this one route is a single action.

**Suggested addition to Debug Lab 7.3:** *"IAM changes are eventually consistent. After fixing the policy I saw `AccessDeniedException` keep appearing for about 5 minutes. Re-check the policy, then wait and retry before changing anything else."* Also: the IAM policy simulator shows **explicitDeny for everything** when an Organizations SCP restricts regions, unless you pass the `aws:RequestedRegion` context key.

## 13. Week 6, Step 58: the first ASG in an account can fail to get a scaling policy

**Not a handbook bug, but worth a Common-mistakes line.** Creating the first Auto Scaling group in an account also creates the `AWSServiceRoleForAutoScaling` service-linked role. For about 20 seconds afterward, `put-scaling-policy` fails with `ServiceLinkedRoleFailure: ... not yet ready for use`. Wait and retry.
