# Handbook Errata: Weeks 0–4

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
