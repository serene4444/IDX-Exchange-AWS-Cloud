# Week 04: AWS Storage & Database Decision Guide

| Service | What it is | Access pattern | Scales / durability | Use this when… |
| --- | --- | --- | --- | --- |
| **S3** | Object storage: files ("objects") in buckets, reached over HTTPS | Whole-object PUT/GET by key. You can't edit part of a file in place | Effectively unlimited. 11 nines of durability across 3+ AZs. Storage classes (Standard → IA → Glacier) trade retrieval speed for cost | …you're storing files, backups, logs, static website assets, or data-lake files that are written once and read many times. |
| **EBS** | Block storage: a virtual hard disk attached to **one** EC2 instance | Low-latency block reads and writes, like a local disk | Lives in a single AZ. Back it up with snapshots, which are stored in S3 | …an EC2 instance needs a boot volume or fast disk for its own OS, app, or self-managed database. |
| **EFS** | Managed NFS file system that **many** instances mount at once | POSIX file paths, shared read/write | Grows and shrinks automatically. Multi-AZ | …several EC2 instances or containers need to share the same files, like a shared uploads folder or content directory. |
| **RDS** | Managed relational database (MySQL, PostgreSQL, and others) | SQL: joins, transactions, ad-hoc queries | Vertical scaling, read replicas, Multi-AZ standby for failover, automated backups | …the data is relational with a fixed schema, and you need SQL queries, joins, or transactions. That's PropertyLite's `rets_property` table. |
| **DynamoDB** | Managed NoSQL key-value / document database | Fast lookups by partition key (plus an optional sort key). No joins | Serverless, scales horizontally to huge throughput, single-digit-ms latency, on-demand or provisioned capacity | …you know your access patterns up front, like "get listing by ID", and need predictable low latency at any scale with no servers to manage. |

## Quick rules of thumb

- **Files go to S3. A disk for one server is EBS. A disk shared by many servers is EFS.**
- **Need SQL, joins, or transactions?** Use RDS. **Key lookups at massive scale?** Use DynamoDB.
- **Data that's rarely read after 30 days?** Add an S3 lifecycle rule to move it to a cheaper class. Glacier has a 90-day minimum storage charge, so deleting early still costs 90 days.
- **High availability:** RDS Multi-AZ keeps a synchronous standby in a second AZ. It's for failover, not for read scaling, which is what read replicas do. EBS is single-AZ, so cross-AZ resilience comes from snapshots.

## How PropertyLite uses these

- **RDS MySQL** holds the full sanitized `rets_property` table, used for analytics like the city/price aggregate.
- **DynamoDB `Properties`** serves the single-listing lookup by `L_ListingID`. Week 7's Lambda reads from it.
- **S3** stores files: runbooks now, and later backups and artifacts.
