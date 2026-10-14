# Week 03 Runbook: Deploy PropertyLite to EC2

Goal: run the same PropertyLite app from Week 0 on a single EC2 instance, bootstrapped entirely by a user data script, so the instance serves the API on port 8080 with no manual setup.

## 1. Launch the instance (Lab 3.1)

| Setting | Value | Why |
|---|---|---|
| Name | `property-api-01` | Easy to find later and to terminate during cleanup |
| AMI | Amazon Linux 2023 | Free Tier eligible, uses `yum`/`dnf`, and the default user is `ec2-user` |
| Instance type | `t3.micro` (or `t2.micro`) | Free Tier |
| Key pair | New RSA `.pem` called `training-key` | Needed for SSH. It can only be downloaded once, so I saved it to `~/.ssh/training-key.pem` |
| Security group: SSH (22) | Source **My IP** | Only my laptop can try to SSH in. "Anywhere" would expose SSH to the whole internet |
| Security group: Custom TCP (8080) | Source **Anywhere** | PropertyLite listens on 8080, not 80, so this is the port the public API needs |
| User data | Contents of [user-data.sh](./user-data.sh) | Installs Python and Flask, writes the app and CSV to `/opt/property-api`, and starts it |

**How the user data script works:** EC2 runs it once, as root, on first boot. It updates packages, installs Python 3, pip, and Flask 3.0.3, then uses heredocs (`cat > file << 'EOF'`) to write `app.py` and `rets_property_sample.csv` onto the instance. That makes the instance self-contained, with no `git clone` or S3 download. Finally it starts the app in the background with `nohup` and sends its output to `/var/log/property-api.log`. The quoted heredoc markers (`'PYEOF'`) stop bash from expanding anything inside the Python code.

## 2. Connect over SSH

On Windows, I run these from WSL or Git Bash:

```bash
chmod 400 ~/.ssh/training-key.pem
ssh -i ~/.ssh/training-key.pem ec2-user@<public-ip>
```

`chmod 400` makes the key readable only by me. SSH refuses keys whose permissions are "too open."

Useful checks once I'm on the instance:

```bash
sudo tail -50 /var/log/cloud-init-output.log   # did user data run cleanly?
cat /var/log/property-api.log                  # Flask's output
curl localhost:8080/health                     # does the app answer locally?
```

## 3. Verify from my laptop

```bash
curl http://<public-ip>:8080/health
# {"status":"ok"}

curl http://<public-ip>:8080/properties/R100234
# {"L_City":"Sacramento","L_Keyword2":"3",...,"L_SystemPrice":"450000","L_Status":"Active"}
```

Screenshot: [curl-responses.png](./curl-responses.png)

## 4. EBS snapshot (Lab 3.2)

EC2 → Volumes → select the root volume of `property-api-01` → Actions → Create snapshot. Wait until EC2 → Snapshots shows **completed**.

**What a volume created from it would be:** a new EBS volume that's an exact point-in-time copy of the root disk at snapshot time, with the OS, Flask, and `/opt/property-api` included. I could attach it to another instance or use it to restore this one.

Note: once the instance is terminated, the snapshot no longer needs to be kept. I deleted it during cleanup so it doesn't build up storage charges.

## 5. Debugging: SSH times out (Debug Lab 3.3)

Symptom: `ssh` hangs and then times out, even though it worked earlier.

Check these in order:
1. Is the instance in the **running** state?
2. Has my public IP changed? Compare `curl ifconfig.me` against the SSH rule's source in the security group.
3. Does the VPC have an internet gateway, and does the subnet's route table have a `0.0.0.0/0` route to it?

The usual cause is #2. "My IP" saves my IP once, when the rule is created. It never updates. Fix: EC2 → Security Groups → edit the inbound SSH rule → set the source to My IP again.

A timeout points to the network (security group, routing). An immediate "Permission denied (publickey)" points to the key or username instead.

## 6. Cleanup

1. EC2 → Instances → `property-api-01` → Instance state → **Terminate**.
2. EC2 → Volumes: confirm the root volume is gone. It's deleted on termination by default.
3. EC2 → Snapshots: delete the Lab 3.2 snapshot.
4. Optionally delete the security group. The `.pem` key stays in `~/.ssh`, and it's never committed to git.
5. Billing dashboard shows $0.00–$1.00: [billing-screenshot.png](./billing-screenshot.png)
