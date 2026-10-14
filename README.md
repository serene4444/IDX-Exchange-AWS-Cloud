# IDX Exchange — AWS Cloud Engineer Journey

My work log and portfolio from the **IDX Exchange AWS Cloud Engineer internship**, a 12-week program aligned to the **AWS Certified Solutions Architect – Associate (SAA-C03)** exam.

The program doesn't build a new app every week. It hands you one small, working application, **PropertyLite** (a Flask API for real-estate listings), and takes it further into production each week: deploy it, secure it, scale it, containerize it, automate its releases, and monitor it. That's the day-to-day work of a junior cloud/DevOps engineer.

## Progress

| Week | Topic | Status | Deliverable |
| --- | --- | --- | --- |
| 0 | Environment setup + PropertyLite | ✅ Done | [propertylite/](./propertylite/) |
| 1 | Cloud fundamentals & account security | ✅ Done | [week-01/](./week-01/) |
| 2 | IAM & security foundations | ✅ Done | [week-02/](./week-02/) |
| 3 | Compute: EC2 | ✅ Done | [week-03/](./week-03/) |
| 4 | Storage & databases (S3, RDS, DynamoDB) | 🔄 In progress | |
| 5 | Networking: VPC deep dive | ⏳ | |
| 6 | Load balancing & auto scaling | ⏳ | |
| 7 | Serverless & event-driven (Lambda, API Gateway, SQS) | ⏳ | |
| 8 | Infrastructure as Code (Terraform) | ⏳ | |
| 9 | Containers (Docker, ECR, ECS Fargate) | ⏳ | |
| 10 | CI/CD (GitHub Actions + OIDC) | ⏳ | |
| 11 | Observability, Well-Architected & cost | ⏳ | |
| 12 | Capstone: PropertyLite in production | ⏳ | |

## What I've done so far

### Week 0: PropertyLite

- Set up the AWS CLI, Git, and VS Code, and ran PropertyLite locally.
- PropertyLite serves `GET /health`, `GET /properties?city=`, and `GET /properties/<id>` on port 8080. Its data uses real RETS field names: `L_ListingID`, `L_City`, `L_SystemPrice`, and so on.

### Week 1: Account security

- Turned on **MFA for the root user** and created a **zero-spend budget alert**.
- Created an IAM admin user for daily work, so I stay off root, and configured the AWS CLI.
- Wrote up root vs IAM and the **Shared Responsibility Model**.

### Week 2: IAM & least privilege

- Wrote a **least-privilege S3 policy**: `PutObject` and `GetObject` on one bucket's objects only, attached to a CLI-only test user.
- Confirmed it with an expected `AccessDenied` on `aws s3 ls`. That denial is least privilege working, not a bug.
- Turned on **IAM Access Analyzer** for continuous auditing.
- Documented the policy evaluation rule: implicit deny by default, and an explicit Deny always wins.

### Week 3: EC2

- Deployed PropertyLite to an **EC2 `t3.micro` running Amazon Linux 2023**. A **user data bootstrap script** installs Python and Flask, writes the app, and starts it on first boot, with no manual setup.
- Opened SSH only to my IP and port 8080 to the public through the security group. Connected over SSH with a key pair.
- Practiced **EBS snapshots** and documented how to debug SSH timeouts, which are usually a stale "My IP" rule.
- Tore everything down at the end of the week to avoid charges.

## Skills & services

**AWS:** IAM (users, policies, Access Analyzer), EC2, EBS, security groups, Budgets  
**Tools:** AWS CLI v2, Git/GitHub, Python/Flask, Bash, SSH  
**Coming up:** S3, RDS (MySQL), DynamoDB, VPC, ALB/ASG, Lambda, API Gateway, SQS/SNS, Terraform, Docker, ECS Fargate, GitHub Actions, CloudWatch

## Repo layout

```text
propertylite/     The Flask app operated all program (app.py, requirements, sample data)
week-01/          Account security evidence + concepts write-up
week-02/          IAM policies (JSON) + README explaining each one
week-03/          EC2 runbook, user data bootstrap script, curl evidence
```

## Habits I follow every week

- **Tear down every resource** at the end of each lab and check that billing stays at about $0.
- **Never commit secrets.** Access keys, `.pem` files, DB passwords, and raw data exports containing PII are all gitignored.
- Use least-privilege identities for testing and never use root for daily work.
- Commit at the end of every session.

## Goal

Take the **SAA-C03** exam the Monday after Week 12. Finish with a Terraform-defined, monitored, CI/CD-deployed PropertyLite that I can tear down and rebuild from scratch.
