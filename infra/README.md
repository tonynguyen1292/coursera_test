# AWS infrastructure — edge delivery (block A)

Terraform for the AWS deployment of the WA Mining dashboard. This is the
first of three planned blocks and is deliberately the cheap, low-risk one:
it puts the real, working app on AWS for roughly nothing, and it establishes
the seam the later blocks migrate through.

**Status: written, never applied.** There was no AWS account when this was
authored and no `terraform` binary on the machine, so none of it has been
run through `validate`, `plan` or `apply`. Treat the first apply as the
point where it is proven, not as a formality. Anything that turns out to be
wrong belongs in the troubleshooting log, not quietly fixed.

## What it builds

| Resource | Why |
|---|---|
| S3 bucket | The built React bundle. Private, versioned, encrypted, never a website endpoint |
| CloudFront distribution | Two origins: the bucket, and the API |
| Origin Access Control | Lets only this distribution read the bucket |
| CloudFront Function | Rewrites extensionless paths to `/index.html` |
| AWS Budget | Two actual thresholds and a forecast alarm |

No load balancer and no NAT gateway, on purpose. Those two are where
portfolio AWS bills come from — roughly $16 and $32 a month respectively,
billed per hour whether or not anything uses them, and neither is in the
free tier.

## The idea worth understanding

The frontend calls `/api/...` on its own origin. CloudFront routes those to a
second origin — currently the Netlify deployment — while everything else goes
to S3.

That means **the browser only ever talks to one domain**, so there is no
cross-origin request and no CORS configuration anywhere. It works because
`frontend/src/api/client.ts` falls back to `window.location.origin` when
`VITE_API_BASE_URL` is unset, so the bundle deployed here is byte-identical
to the one Netlify builds.

The payoff is the migration. When the API moves to Lambda + API Gateway,
`var.api_origin_domain` changes and nothing else does — no frontend rebuild,
no redeploy of the bundle, no CORS to introduce, no client code aware that
anything moved. CloudFront is being used as an indirection layer, not just a
cache.

## Before the first apply

Do these in order. The ordering is the point: the budget alarm exists before
anything that can bill.

1. **Create the AWS account**, then immediately **enable MFA on the root
   user**. Root has no permission boundary and cannot be restricted.
2. **Create an IAM user (or Identity Center user) for day-to-day work** and
   stop using root. Give it the access it needs to run this stack.
3. **Configure credentials locally** — `aws configure` — and confirm with
   `aws sts get-caller-identity`.
4. `cp terraform.tfvars.example terraform.tfvars` and set your email.
5. `terraform init && terraform plan` — read the plan before applying.
6. `terraform apply`, then **accept the budget subscription email**. Until
   you click it, the alarm is inert.

## Deploying the frontend

```bash
terraform output -raw deploy_command
```

Build with `VITE_API_BASE_URL` **unset**. Setting it would bake an absolute
origin into the bundle and bypass the whole same-origin arrangement.

CloudFront gives 1,000 invalidation paths a month free; `/*` counts as one.

## Cost

Approximately zero, and — unlike the later blocks — with no 12-month cliff.
CloudFront's 1 TB/month free tier is perpetual rather than a first-year
allowance, S3 at this size is cents, and the default certificate is free.
The budget alarm defaults to $5 so it fires on a mistake long before the
amount matters.

## Teardown

```bash
terraform destroy
```

The bucket is versioned, so `destroy` fails while objects remain. Empty it
first:

```bash
aws s3 rm s3://$(terraform output -raw bucket_name) --recursive
```

That deletes current versions only. If versioned objects persist, remove
them through the console's "Empty bucket" action, which handles version
markers, then re-run `destroy`.

## What comes next

- **Block C — data lake.** S3 + Glue + Athena over the MINEDEX dataset.
  Cheap, and the piece most portfolios do not have.
- **Block B — API tier.** FastAPI on Lambda behind API Gateway, Postgres in
  private subnets, credentials in SSM Parameter Store. The most substantial
  architecture and the one carrying real cost risk, which is why it is last.
  Landing it is a one-variable change here.
- **Custom domain (WMDP2-20).** Route 53 + an ACM certificate **issued in
  `us-east-1`** — CloudFront reads certificates from that region only,
  regardless of where the rest of the stack lives. The provider alias in
  `versions.tf` is already declared for it.
