# Azure Subscription Inventory Module

基于 Terraform + Azure CLI 的 Azure 订阅资源盘点与成本排行模块。  
当前实现已经包含资源清单、统计汇总、Markdown 报告，以及最近 7 天高成本资源排行（AmortizedCost）。

## 当前模块实际能力

- 通过 Azure Resource Graph 拉取订阅内资源清单（含 `id/name/type/resourceGroup/location/tags`）
- 生成 Resource Group -> Resources 层级结构
- 统计资源类型分布、地域分布、未打标签资源数量
- 生成 Top 10 资源类型
- 通过 Cost Management Query API 生成最近 7 天高成本资源 Top N（默认 10）
- 输出 Terraform outputs，并落地本地文件：
  - `inventory.json`
  - `summary.json`
  - `inventory_report.md`

## 代码结构

- 根模块入口：`main.tf`
- 子模块：`modules/subscription_inventory`
- 外部脚本：
  - `query_resources.sh`（资源清单）
  - `query_costs.sh`（成本排行）
- 产物输出定义：`outputs.tf`

## 执行前置条件

### Terraform 与 Provider

- Terraform `>= 1.5.0`
- Provider：
  - `hashicorp/azurerm ~> 3.100`
  - `azure/azapi ~> 1.12`
  - `hashicorp/local ~> 2.4`

### Azure 权限

执行身份（用户或服务主体）至少需要：

- 订阅 `Reader`（读取资源清单）
- 订阅 `Cost Management Reader`（读取成本数据）

### Linux 环境依赖包（含 jq）

以下依赖建议在 Linux/WSL 上提前安装：

- `bash`
- `curl`
- `ca-certificates`
- `python3`（脚本首选 JSON 封装工具）
- `jq`（脚本备用 JSON 封装工具，建议也安装）
- Azure CLI (`az`)

Ubuntu / Debian 示例：

```bash
sudo apt-get update
sudo apt-get install -y bash curl ca-certificates python3 jq
```

安装 Azure CLI（如未安装）：

```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

建议安装/确认 Resource Graph 扩展：

```bash
az extension add --name resource-graph --upgrade
```

## 认证方式

默认使用 Azure CLI 登录态（本地最常见）：

```bash
az login
az account set --subscription <SUBSCRIPTION_ID>
```

项目同时支持通过 Terraform Provider 使用 MSI（参见 `use_msi` 和 `managed_identity_client_id` 变量）。

## 使用方式

1) 复制变量文件

```bash
cp terraform.tfvars.example terraform.tfvars
```

2) 编辑 `terraform.tfvars`，至少填入：

- `subscription_id`
- `tenant_id`
- （可选）`managed_identity_client_id`
- （可选）`top_n_cost_resources`（默认 `10`）

3) 执行 Terraform

```bash
terraform init
terraform plan
terraform apply
```

## 输入变量

根模块变量（`variables.tf`）：

- `subscription_id`：目标订阅 ID
- `tenant_id`：租户 ID
- `use_msi`：是否启用托管身份（默认 `false`）
- `managed_identity_client_id`：用户分配托管身份 client id（默认空）
- `top_n_cost_resources`：高成本资源榜单数量（默认 `10`）

## 输出说明

Terraform outputs：

- `inventory`：按资源组组织的完整资源清单
- `summary`：统计汇总（含 `top_cost_resources`）
- `markdown_report`：可读报告 Markdown
- `top_cost_resources`：高成本资源 Top N

本地文件产物：

- `inventory.json`
- `summary.json`
- `inventory_report.md`

## 成本排行口径

- 时间窗口：`Last7Days`
- 成本类型：`AmortizedCost`
- 聚合指标：`PreTaxCost`（按 `ResourceId` 汇总）

说明：

- 成本数据通常有延迟（常见 8-24 小时）
- 某些近期开销可能对应已删除资源，报告中会显示为 `unknown`

## 常见问题

- `query_resources.sh` 或 `query_costs.sh` 报错找不到命令：
  - 确认 `az`、`python3`、`jq` 已安装，且在 `PATH` 中。
- 成本查询失败（权限）：
  - 确认执行身份具备 `Cost Management Reader`。
- Terraform 计划阶段失败：
  - 优先检查 `az account show` 当前订阅是否正确。

## 最小可运行检查清单

执行以下 5 组命令，快速确认环境可运行：

```bash
# 1) 基础命令是否存在
command -v terraform
command -v az
command -v python3
command -v jq
command -v bash

# 2) Azure 登录与订阅
az login
az account set --subscription <SUBSCRIPTION_ID>
az account show --query "{subscription:id, tenant:tenantId, user:user.name}" -o table

# 3) Resource Graph 可用性
az extension add --name resource-graph --upgrade
az graph query -q "Resources | take 1" --subscriptions <SUBSCRIPTION_ID> -o table

# 4) Cost Management API 可用性
bash query_costs.sh <SUBSCRIPTION_ID> | python3 -c 'import json,sys;print("ok" if "result" in json.load(sys.stdin) else "failed")'

# 5) Terraform 执行链路
terraform init
terraform validate
terraform plan
```

如果第 4 步失败，优先检查当前身份是否具备订阅级 `Cost Management Reader` 权限。
