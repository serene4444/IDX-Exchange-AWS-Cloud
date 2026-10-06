# Week 01: AWS Account Security and Budget

## Concepts

The AWS account root user is the identity created with the account, and it has broad access to account-wide settings and resources. Because root access is powerful, I would protect it with multi-factor authentication (MFA) and use it only for tasks that require root. AWS Identity and Access Management (IAM) lets an account create users, roles, groups, and policies with permissions tailored to specific tasks. I would use an appropriately limited IAM identity for regular work instead of using the root user. The Shared Responsibility Model means AWS secures the cloud infrastructure that runs its services, while customers secure the data, identities, permissions, and configurations they put in the cloud. The exact split depends on the AWS service, but customers remain responsible for configuring their workloads and access safely.

## Evidence

- MFA enabled: [mfa-enabled.png](./mfa-enabled.png)
- Budget and cost view: [budget.png](./budget.png)
