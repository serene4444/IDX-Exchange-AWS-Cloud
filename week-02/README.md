# Week 02: IAM and Security Foundations

## Policies

### [administrator-access.json](./policies/administrator-access.json)

**What it allows:** every action (`"Action": "*"`) on every resource (`"Resource": "*"`) in the account. This is the same document as the AWS managed policy `AdministratorAccess`.

**Who it's attached to:** my `SerenePlummer-admin` IAM admin user from Lab 1.3.

**Why it's scoped this way:** I need one identity that can do everyday admin work, like creating users, policies, and later EC2, RDS, and VPC resources, without signing in as root. It is deliberately *not* least privilege. To make up for that, the user has MFA, and I don't use it to test low-privilege behavior. A Deny never shows up when you test as an admin.

### [s3-uploader-only.json](./policies/s3-uploader-only.json)

**What it allows:** only `s3:PutObject` (upload) and `s3:GetObject` (download), and only on objects inside `my-training-bucket-sereneplummer` (`arn:aws:s3:::my-training-bucket-sereneplummer/*`).

**Who it's attached to:** `s3-test-user`, which has no console access and is used through the `s3test` CLI profile.

**Why it's scoped this way:** it's least privilege. The user only needs to put files into one bucket and read them back. It can't list buckets, delete objects, change bucket settings, or touch any other bucket. Here are the scoping choices:

- **The `/*` suffix:** `PutObject` and `GetObject` are object-level actions, so the resource has to be the objects in the bucket (`bucket/*`), not the bucket ARN itself. Without `/*`, uploads fail with AccessDenied (Debug Lab 2.3).
- **No `s3:ListBucket` or `s3:ListAllMyBuckets`:** that's why `aws s3 ls --profile s3test` returns AccessDenied. That's the expected result, not a bug. If listing the bucket's contents were ever needed, `s3:ListBucket` would be added as a separate statement on the bucket ARN (`arn:aws:s3:::my-training-bucket-sereneplummer`, no `/*`).

## Verification

```bash
aws s3 ls --profile s3test
# An error occurred (AccessDenied) when calling the ListBuckets operation  <-- expected
```

## IAM Access Analyzer (Lab 2.2)

I created an analyzer with the default settings (IAM → Access Analyzer → Create analyzer). It checks continuously for resources shared outside the account. Expected result on a fresh account: **0 active findings**.

## Key concepts

- **Policy evaluation:** everything starts as an implicit deny. An Allow grants access, but an explicit Deny anywhere (identity policy, bucket policy, SCP) always wins.
- **Identity-based vs resource-based:** identity policies attach to users, groups, or roles and say what *that identity* can do. Resource policies (like an S3 bucket policy) attach to the resource and say *who* can access it.
- **Managed vs inline:** managed policies are standalone and reusable across identities. Inline policies are embedded in a single identity and get deleted along with it.
