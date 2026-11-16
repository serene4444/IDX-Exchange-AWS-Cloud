# Week 06: Elastic Load Balancing & Auto Scaling

Region: **us-east-2 (Ohio)**, because of my org's SCP (see [week-05](../week-05/README.md#note-why-us-east-2)). Date run: 2026-11-15.

The full write-up with graphs and timings is in **[load-test-report.md](./load-test-report.md)**. This page covers what I built and how to rebuild it.

## Architecture

```text
laptop ──HTTP:80──► ALB property-api-alb  (public subnets 2a + 2b, alb-sg: 80 from 0.0.0.0/0)
                        │ forward
                        ▼
                    target group property-api-tg  (HTTP 8080, health check GET /health)
                        │
                        ▼
          ASG property-api-asg  (private subnets 2a + 2b, min 1 / desired 2 / max 4)
          each instance: t3.micro, Week 3 user data, property-api-sg: 8080 from alb-sg only
                        │ outbound (yum, pip)
                        ▼
                    NAT Gateway ──► internet
```

The instances have **no public IP** and **no SSH rule**. Only the ALB can reach port 8080. I ran the stress test with **SSM Run Command** instead of SSH, which needs no bastion and no open port 22. The instance role gets just `AmazonSSMManagedInstanceCore`.

## Scripts

| File | What it does |
| --- | --- |
| [build-asg.sh](./build-asg.sh) | Rebuilds the Week 5 VPC, then creates the SGs, launch template, target group, ALB + listener, ASG, and target-tracking policy. Waits for 2 healthy targets. |
| [teardown-asg.sh](./teardown-asg.sh) | Deletes everything in the handbook's order (ASG → ALB → target group → launch template), then the network and IAM role, and ends with a leftover check. |

The launch template uses the **same AMI and user data as Week 3** ([week-03/user-data.sh](../week-03/user-data.sh)). The only changes are `t3.micro`, the instance profile, IMDSv2, and **detailed monitoring**. Detailed monitoring sends 1-minute metrics, so target tracking reacts in about 3 minutes instead of about 15.

## Lab results

| Check | Result |
| --- | --- |
| `curl http://<alb-dns>/health` | ✅ `{"status":"ok"}` |
| `curl http://<alb-dns>/properties` | ✅ all 3 sample listings |
| `curl http://<alb-dns>/properties/R100234` | ✅ Sacramento listing, identical to Week 3 |
| Self-healing: terminate 1 of 2 instances | ✅ replacement launched at **+101 s**, healthy in target group at **+178 s** |
| Availability during self-healing | 14 of 15 `/health` requests OK. 1 failed while the instance was draining. |
| Scale-out under CPU load | ✅ desired **2 → 4** at **+4 min 59 s** after the stress started |
| Scale-in after load | ✅ started about 15 min after CPU dropped (desired 4 → 3) |

## Debug Lab 6.3: ALB can't reach the targets (reproduced)

1. **Break:** removed `property-api-sg`'s inbound rule *8080 from `alb-sg`*.
2. **Symptom:** within **34 s** all 4 targets showed `unhealthy (Target.Timeout)`. The ALB returned **`504 Gateway Time-out`** after about 10 s on every request.
3. **Fix:** re-added the rule with **source = the ALB's security group ID**. The next request returned `200 {"status":"ok"}` immediately.

**I got a 504, not the handbook's 502.** A security group that silently drops packets makes the ALB's connection *time out* (504). A **502** happens when the ALB reaches the instance but the connection is *refused or reset*. For example, the SG is open but the app isn't listening on 8080, or it crashed. Both are "the ALB can't get a good answer from the target," but the status code tells you which layer to check: 504 points to the network/SG, and 502 points to the app/port. I've added this to the [errata](../HANDBOOK-ERRATA.md).

**Lesson:** an ALB is just another network peer. It needs an explicit inbound rule like anything else, and "internet-facing" only describes the ALB's own listener. Referencing the ALB's **security group** instead of IPs matters because ALB node IPs change.

## Handbook fixes I needed

- **`amazon-linux-extras` doesn't exist on Amazon Linux 2023.** It returns exit 127, "command not found." AL2023 has `stress-ng` in its default repos: `sudo dnf install -y stress-ng && stress-ng --cpu 2 --timeout 300`.
- **Stressing one instance isn't enough** with desired = 2. One instance at 100% and one idle averages about 50%, which barely touches a 50% target and may never fire the alarm. I stressed both instances by targeting the ASG's tag with SSM.
- **Private instances can't be reached by SSH** without the Week 5 bastion. The handbook says "SSH into an instance" but puts the ASG in private subnets. SSM Run Command avoids that problem.
- The first ASG in an account creates the **Auto Scaling service-linked role**. `put-scaling-policy` can fail for about 20 s with `ServiceLinkedRoleFailure` until that role is ready. Retrying works.

## Cleanup

`bash week-06/teardown-asg.sh` finished with an empty leftover check (ASG, ALB, instances, NAT, EIPs, VPC). The stack was up for about 1h45m: NAT Gateway about $0.08, ALB about $0.04, t3.micro instance-hours and public IPv4 a few cents.

> **To do (me):** add `billing-screenshot.png` from the Billing console.
