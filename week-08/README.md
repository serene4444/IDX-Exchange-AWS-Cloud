# Week 08: Infrastructure as Code (Terraform)

**Region:** us-east-1 · **Account:** `604531678534`, through the `intern01` AWS SSO profile (`InternAdmin` role) · **Date run:** 2026-11-16 · **Terraform** 1.17.1, AWS provider ~> 5.0

> Weeks 5–7 ran in my other account (`548848855009`, us-east-2), whose org SCP blocks us-east-1. From Week 8 on I use `intern01` in us-east-1, matching the handbook. Before any Terraform command, sign in with `aws sso login --profile intern01`. The SSO token expires, and an expired token fails with *"Token has expired and refresh failed"*.

## Lab 8.1: Week 5's VPC in Terraform

[main.tf](./main.tf) is the handbook's config. It uses the community `terraform-aws-modules/vpc/aws` module pinned to `5.8.1`. I added four things:

- **`profile = "intern01"`** in the provider block, so Terraform never falls back to my default credentials, which point at the other account.
- A **pinned provider version** (`~> 5.0`). Module 5.8.1 was written for AWS provider v5, and an unpinned `init` could pull an incompatible major version later. The exact versions are recorded in `.terraform.lock.hcl`, which *is* committed.
- **`default_tags`** (`Project=week-08`, `ManagedBy=terraform`) on every resource. Anyone looking in the console can tell a resource is Terraform-managed and shouldn't be edited by hand.
- **Outputs** for the VPC, subnet IDs, and NAT IP.

```text
terraform init       # downloads the AWS provider + VPC module into .terraform/
terraform plan       # Plan: 19 to add, 0 to change, 0 to destroy.
terraform apply      # Apply complete! Resources: 19 added, 0 changed, 0 destroyed.  (2 min 3 s, 1m44s of it the NAT Gateway)
```

Verified in AWS:

| Resource | Value |
| --- | --- |
| VPC `training-vpc-tf` | `10.1.0.0/16` |
| Public subnets | `10.1.1.0/24` (us-east-1a), `10.1.2.0/24` (us-east-1b) |
| Private subnets | `10.1.101.0/24` (us-east-1a), `10.1.102.0/24` (us-east-1b) |
| IGW, 1 NAT Gateway + EIP, public and private route tables | ✅ all present, routes match Week 5 |
| Second `terraform plan` right after apply | `No changes`, exit code 0 |

### 19 resources from one module block

The module turns ~10 lines of config into 19 resources. That's the VPC, 4 subnets, IGW, EIP, NAT, 2 route tables, 2 routes, and 4 route-table associations. It also adopts the VPC's **default** route table, NACL, and security group, so Terraform manages those defaults too. My Week 5 bash script needed about 90 lines and a separate 55-line teardown script for roughly the same thing.

## What plan, apply, and destroy each do

| Command | What it does | Changes anything? |
| --- | --- | --- |
| `terraform plan` | **Refreshes** state by reading the real resources from AWS, compares them with the `.tf` files, and prints the difference as create (`+`), update in place (`~`), destroy (`-`), or replace (`-/+`). | No. Read-only. |
| `terraform apply` | Runs a plan, waits for `yes` (or uses a saved plan file), makes the API calls in dependency order, and records each result in state. | Yes |
| `terraform destroy` | Plans the deletion of **everything in state**, in reverse dependency order, then deletes it. | Yes. It only touches what's in state. |

`terraform plan -out=x.tfplan` followed by `terraform apply x.tfplan` applies **exactly** the plan I reviewed. A plain `apply` re-plans, and the result could differ if something changed in between.

## Why state matters

`terraform.tfstate` is Terraform's **map from my code to real resource IDs**. For example, `module.vpc.aws_vpc.this[0]` → `vpc-05d6c0f0b922317fc`. Without state, Terraform has no idea which VPC in the account is "its" VPC.

- **Plan uses state** to look up what to compare. Anything missing from state looks like it needs to be **created**, even if it already exists.
- **Destroy uses state** to decide what to delete. Anything missing from state gets left behind, still costing money.
- **State can contain secrets** in plain text, such as database passwords and keys. That's why `.terraform/`, `*.tfstate`, `*.tfstate.*`, and `*.tfplan` are in `.gitignore` and were never committed.
- **State lives on my laptop** for now, so only one person (me) can safely run Terraform against it. A team would use a **remote backend** (an S3 bucket with state locking) so everyone shares one state and two `apply` runs can't collide.

## Debug Lab 8.2: drift and state mismatches (reproduced two ways)

### a) Drift: a managed resource deleted outside Terraform

1. **Break:** deleted the public route table's `0.0.0.0/0 → IGW` route with the CLI, the same as deleting it in the console.
2. **Symptom:** `terraform plan` caught it during refresh:

   ```text
   Note: Objects have changed outside of Terraform
     # module.vpc.aws_route.public_internet_gateway[0] has been deleted
     # module.vpc.aws_route.public_internet_gateway[0] will be created
   Plan: 1 to add, 0 to change, 0 to destroy.
   ```

3. **Fix:** `terraform apply` recreated the route in 1 s. That's what IaC is for: the code is the source of truth, and apply puts reality back.

### b) State mismatch: the resource exists, but Terraform lost track of it

1. **Break:** `terraform state rm 'module.vpc.aws_internet_gateway.this[0]'`. The IGW still existed and was still attached in AWS, but Terraform had forgotten about it.
2. **Symptom:** the handbook's "plan wants to recreate a resource you know already exists":

   ```text
     # module.vpc.aws_internet_gateway.this[0] will be created
     # module.vpc.aws_route.public_internet_gateway[0] will be updated in-place
   Plan: 1 to add, 1 to change, 0 to destroy.
   ```

   Applying this would create a **second** IGW and fail to attach it, because a VPC can have only one. Then `destroy` would never delete the orphaned original.
3. **Diagnose:** `terraform state list` didn't include the IGW, while the console showed `igw-09b25a32019ec4d62` attached to the VPC.
4. **Fix:** `terraform import 'module.vpc.aws_internet_gateway.this[0]' igw-09b25a32019ec4d62` → `Import successful!` → `terraform plan` → **No changes**.

**Which fix to use:**

| Situation | Fix |
| --- | --- |
| Resource changed or deleted outside Terraform, and the code is right | `terraform apply` puts it back |
| Resource **exists** but isn't in state | `terraform import <address> <id>` |
| Resource is in state but **genuinely gone**, and I don't want it back | Remove it from the code, or `terraform state rm <address>` |
| I just want to see drift without changing anything | `terraform plan -refresh-only` |

**Something I noticed after the import:** `terraform plan -refresh-only` still reported *"Objects have changed outside of Terraform"* on the public route table. Its stored `route` list was saved while the route was deleted, so it was stale. `terraform apply -refresh-only` updated state to match reality without touching any infrastructure. After that, the refresh-only plan showed no changes.

**Lesson:** once a resource is managed by Terraform, every change goes through Terraform. In the console I treat it as read-only. The `ManagedBy=terraform` tag is there as the reminder.

## Cleanup

```text
terraform destroy    # Destroy complete! Resources: 19 destroyed.  (71 s)
```

The leftover check in us-east-1 (VPCs, NAT Gateways, EIPs, and IGWs tagged `Project=week-08`) came back empty, and `terraform state list` showed 0 resources. The VPC was up for about 5 minutes, so the NAT Gateway cost less than $0.01.

> **To do (me):** add `billing-screenshot.png` for the `604531678534` account.
