# Claude Desktop — Windows Deployment SOP

> Draft. Fill in organization-specific details as the deployment process is finalized.

## 1. Purpose & Scope

Procedure for installing, configuring, and maintaining the Claude desktop application on managed Windows endpoints.

## 2. Prerequisites

- Supported Windows version
- Administrator rights / deployment tooling (e.g., Intune, SCCM, GPO)
- Network access to required Anthropic endpoints

## 3. Installation

1. Obtain the approved installer.
2. Deploy via the chosen management tool.
3. Verify installation on a pilot group.

## 4. Configuration

- Baseline settings and policies (see `config/`).
- Authentication / SSO setup.

## 5. Validation

- Confirm launch and sign-in.
- Confirm policy enforcement.

## 6. Rollout

- Pilot → phased rollout → full deployment.

## 7. Support & Rollback

- Troubleshooting steps.
- Uninstall / rollback procedure.
