# Azure Asset Inventory & Governance Engine

Enterprise-grade Azure Subscription inventory and governance analytics engine built with Terraform + Azure Resource Graph.

![Terraform](https://img.shields.io/badge/Terraform-1.5+-blue)
![Azure](https://img.shields.io/badge/Azure-ResourceGraph-blue)
![License](https://img.shields.io/badge/License-MIT-green)

---

## 🚀 Overview

This project provides a production-ready Azure asset inventory and governance analytics framework.

It delivers:

- ✅ Full subscription-wide resource discovery (Azure Resource Graph)
- ✅ Resource Group → Resources hierarchical mapping
- ✅ Resource type distribution analytics
- ✅ Regional distribution analytics
- ✅ Top 10 resource type ranking
- ✅ Untagged resource detection
- ✅ JSON artifact exports
- ✅ Auto-generated Markdown governance report

---

## 🏗 Architecture

```
Azure CLI (az login)
        │
        ▼
Terraform Runtime
        │
        ▼
External Data Source (query_resources.sh)
        │
        ▼
Azure Resource Graph (KQL)
        │
        ▼
inventory.json | summary.json | inventory_report.md
```

---

## 🔐 Authentication

Uses Azure CLI authentication:

```bash
az login
az account set --subscription <SUBSCRIPTION_ID>
```

Terraform authentication priority:

1. Environment variables (ARM_*)
2. Managed Identity
3. Azure CLI

This project relies on Azure CLI for portability.

---

## 📦 Outputs

### inventory.json
Hierarchical structure of all resources grouped by Resource Group.

### summary.json
Analytics summary including:

- Total resources
- Total resource groups
- Resource type distribution
- Location distribution
- Top 10 resource types
- Untagged resource count

### inventory_report.md
Human-readable governance report.

---

## 🛠 Usage

```bash
# Copy example vars
cp terraform.tfvars.example terraform.tfvars

# Edit subscription ID
nano terraform.tfvars

# Login
az login
az account set --subscription <SUBSCRIPTION_ID>

# Run
terraform init
terraform plan
terraform apply
```

---

## 📊 Governance Capabilities

- Resource type analytics
- Region distribution analytics
- Untagged resource detection
- Top-N resource classification

---

## 🏢 Enterprise Extensions

Future enhancements may include:

- Multi-subscription scanning
- Azure Blob export
- CI/CD scheduling
- Tag compliance enforcement
- Security risk detection
- Cost analysis integration
- HTML dashboard generation

---

## 📜 License

MIT License — see LICENSE file.

---

## 🤝 Contributing

Pull requests and improvements are welcome.

---

Maintained as an extensible Azure Asset Inventory & Governance Engine.
