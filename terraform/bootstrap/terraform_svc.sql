-- Service user that Terraform authenticates as. Run once, as a human ACCOUNTADMIN, in a Snowsight worksheet
-- (a trial account has no SAML IdP, so `snow --authenticator externalbrowser` doesn't work). Fill in the key first:
--   grep -v '^--' terraform/bootstrap/terraform_svc.sql | sed "s|<% pubkey %>|$PUBKEY|" | pbcopy   (see phase 4)
--
-- TYPE = SERVICE: no password, no MFA, no Snowsight UI. Key-pair only.
-- Roles: SYSADMIN (objects), SECURITYADMIN (roles, users, grants),
--        ACCOUNTADMIN (storage integration, resource monitor: nothing else can create them).
-- Terraform uses one provider alias per role, so each resource is created with the least role it needs.

USE ROLE ACCOUNTADMIN;

CREATE USER IF NOT EXISTS TERRAFORM_SVC
  TYPE = SERVICE
  DEFAULT_ROLE = SYSADMIN
  COMMENT = 'Terraform automation (cdc-lab). Key-pair auth only.';

ALTER USER TERRAFORM_SVC SET RSA_PUBLIC_KEY = '<% pubkey %>';

GRANT ROLE SYSADMIN      TO USER TERRAFORM_SVC;
GRANT ROLE SECURITYADMIN TO USER TERRAFORM_SVC;
GRANT ROLE ACCOUNTADMIN  TO USER TERRAFORM_SVC;

-- Warehouse for Terraform's own queries. Bootstrap, not Terraform: the provider needs it before any stack runs.
CREATE WAREHOUSE IF NOT EXISTS TERRAFORM_WH
  WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Terraform automation (cdc-lab).';
GRANT USAGE ON WAREHOUSE TERRAFORM_WH TO ROLE SYSADMIN;
GRANT USAGE ON WAREHOUSE TERRAFORM_WH TO ROLE SECURITYADMIN;
ALTER USER TERRAFORM_SVC SET DEFAULT_WAREHOUSE = TERRAFORM_WH;

-- Facts the plan needs (region: S3 bucket goes in the same AWS region to avoid transfer cost).
SELECT CURRENT_REGION() AS region, CURRENT_ORGANIZATION_NAME() || '-' || CURRENT_ACCOUNT_NAME() AS account;
