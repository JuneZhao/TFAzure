# Azure Subscription Inventory

基于 Terraform + Azure AzAPI Provider 的订阅资源盘点、成本排行与告警工具。
**纯 Terraform 实现**（不依赖 `az` / `jq` / `python3`），支持**多订阅**聚合、**成本告警**与**历史快照归档**。

## 能力

- 通过 **Azure Resource Graph**（provider-level action，azapi v2）拉取资源清单：
  `id / name / type / kind / sku / resourceGroup / location / subscriptionId / tags`
- 通过 **Cost Management Query API**（azapi v2）抓取成本，时间窗口与 `AmortizedCost/ActualCost` 均可配置
- 生成 Resource Group 层级结构、资源类型 / 地域分布统计、未打标签资源完整清单
- Top 10 资源类型 + Top N 高成本资源
- **成本告警**：通过 `cost_alert_threshold` 标记/高亮超阈资源，单独输出 `over_threshold_resources`
- **多订阅**：根模块 `for_each` 到每个订阅，产出每订阅报告 + 跨订阅聚合报告
- **历史归档**：`enable_history = true` 时，每次 apply 将 `reports/` 拷贝一份到 `reports/_history/<timestamp>/`

## 代码结构

```
.
├── main.tf                               # 根模块入口 (for_each over subscription_ids)
├── variables.tf / outputs.tf / provider.tf / versions.tf
├── terraform.tfvars(.example)
└── modules/subscription_inventory/
    ├── main.tf      # azapi_resource_action: ResourceGraph + CostManagement
    ├── locals.tf    # 数据清洗 / 统计 / 告警 / Markdown
    ├── variables.tf / outputs.tf / versions.tf
```

## 前置条件

### 运行环境

- **Linux**（Azure VM / 任意 Linux / WSL 均可，不再支持 Windows 原生）
- Terraform `>= 1.5.0`
- `enable_history = true` 额外需要：`bash`、`cp`（几乎所有发行版自带）

### Provider 版本

- `hashicorp/azurerm ~> 4.0`
- `azure/azapi ~> 2.0`
- `hashicorp/local ~> 2.4`
- `hashicorp/null ~> 3.2`

### Azure 权限（对每个目标订阅）

- `Reader`（读取资源清单）
- `Cost Management Reader`（读取成本数据）

`resource_provider_registrations = "none"` 已在 provider 里启用，确保本项目**绝不会改动租户状态**。

## 认证方式

推荐优先级：

1. **Azure CLI 登录态**（本地开发最方便）
   ```bash
   az login
   ```
2. **环境变量**（CI 推荐）
   ```bash
   export ARM_TENANT_ID=...
   export ARM_SUBSCRIPTION_ID=...     # 任意可访问订阅；真正的目标列表在 tfvars
   export ARM_CLIENT_ID=...
   export ARM_CLIENT_SECRET=...        # 或 ARM_USE_OIDC=true
   ```
3. **Managed Identity**（Azure VM / ACI / AKS / GitHub Actions OIDC）
   ```hcl
   use_msi                    = true
   managed_identity_client_id = "<UAMI Client ID>"
   ```

## 使用方式

```bash
cp terraform.tfvars.example terraform.tfvars
# 编辑 terraform.tfvars，至少填好 tenant_id + subscription_ids

terraform init
terraform plan
terraform apply
```

执行完成后，产物落在 `reports/` 目录：

```
reports/
├── _aggregated_summary.json          # 跨订阅汇总
├── _combined_report.md               # 跨订阅 Markdown 总报告
├── <subscription_id>/
│   ├── inventory.json
│   ├── summary.json
│   └── inventory_report.md
└── _history/                         # 仅 enable_history=true 时存在
    ├── 2026-04-17T091500Z/           # 历史快照 (时间戳由 history_timestamp_format 控制)
    │   ├── _aggregated_summary.json
    │   ├── _combined_report.md
    │   └── <subscription_id>/...
    └── 2026-04-18T091500Z/
        └── ...
```

## 输入变量（根模块）

| 变量 | 类型 | 必填 | 默认 | 说明 |
|---|---|---|---|---|
| `tenant_id` | string | 是 | - | Azure AD 租户 ID |
| `subscription_ids` | list(string) | 是 | - | 需要盘点的订阅 ID 列表 |
| `use_msi` | bool | 否 | `false` | 是否使用托管身份认证 |
| `managed_identity_client_id` | string | 否 | `""` | UAMI Client ID（仅 `use_msi=true` 时生效） |
| `top_n_cost_resources` | number | 否 | `10` | 每订阅高成本资源榜长度 |
| `cost_timeframe` | string | 否 | `Last7Days` | `Last7Days` / `MonthToDate` / `BillingMonthToDate` |
| `cost_type` | string | 否 | `AmortizedCost` | `AmortizedCost` / `ActualCost` |
| `cost_alert_threshold` | number | 否 | `0` | 单资源成本告警阈值，`0` 表示禁用 |
| `reports_dir` | string | 否 | `reports` | 产物输出目录 |
| `enable_history` | bool | 否 | `false` | 是否启用历史快照归档 |
| `history_timestamp_format` | string | 否 | `YYYY-MM-DD'T'hhmmss'Z'` | 历史目录时间戳格式（`formatdate` 语法） |

## 输出（Terraform outputs）

- `inventories` - `map(subscription_id → inventory)`
- `summaries` - `map(subscription_id → summary)`，含 `untagged_resources` / `over_threshold_resources` 完整清单
- `markdown_reports` - `map(subscription_id → markdown)`
- `top_cost_resources_by_subscription` - `map(subscription_id → list)`
- `over_threshold_resources_by_subscription` - `map(subscription_id → list)`
- `aggregated_summary` - 跨订阅聚合（含 `total_over_threshold`）
- `combined_markdown_report` - 合并 Markdown
- `history_snapshot_dir` - 本次 apply 归档目录（`enable_history=false` 时为 `null`）

## 成本告警

设置 `cost_alert_threshold > 0` 会在多个位置展现超阈资源：

- Markdown 报告 `Top Cost Resources` 段：超阈项前缀 `**[ALERT]**`
- Markdown 报告新增独立段 `## Cost Alerts (> <threshold>)`
- 每订阅 summary 新增 `over_threshold_resources` / `over_threshold_count` / `cost_alert_threshold`
- 聚合 `aggregated_summary.total_over_threshold`

阈值单位以 Cost Management 返回的 `Currency` 字段为准（通常为订阅计费币种）。

## 历史归档

实现细节：

- Terraform 管理的只有 `reports/<sub_id>/` 和 `reports/_aggregated_summary.json` 等"最新"快照
- 历史归档通过 `null_resource` + `local-exec` 执行 `cp -r`，**不入 state**
- 好处：任意次 apply 不会销毁任何历史目录；state 文件不会随着历史快照增长
- 代价：需要 Linux 宿主；`terraform destroy` 不会清理历史目录（需要手工 `rm -rf reports/_history/`）

每次 apply 的快照目录会打印在 `history_snapshot_dir` 输出中。

## 从 v1 升级

如果你从本项目早期版本（azurerm 3.x / azapi 1.x / bash 脚本）升级，需要重新 `terraform init -upgrade`；state 中的 `local_file` address 已从单例迁移为 `for_each`，第一次 plan 会显示 destroy + create（**只影响本地 JSON/MD 文件**），这是预期行为。

## 成本数据口径

- 时间窗口：`cost_timeframe`
- 成本类型：`cost_type`
- 聚合：按 `ResourceId` 汇总 `PreTaxCost`
- 注意：
  - 成本数据通常有 **8–24 小时**延迟
  - 近期成本可能对应已删除资源，`name/type/resource_group` 会显示为 `unknown`
  - 只统计 `cost > 0`（退款/credit 当前被过滤）

## 已知限制

- **Resource Graph 单次 1000 行硬限**：`modules/subscription_inventory/main.tf` 设置了 `options.top = 1000`，超过该数量的订阅会被截断。如需支持更大订阅，需要扩展为基于 `$skipToken` 的分页循环（目前纯 Terraform 内较难优雅实现，建议届时改用脚本预取 + `jsondecode(file())`）。
- **仅统计正成本**：退款 / credit 类负值目前被过滤；如需纳入，放开 `locals.tf` 里 `if cost_info.cost > 0` 即可。
- **阈值币种感知缺失**：`cost_alert_threshold` 是裸数字，跨币种订阅需要分别拆分成多次 apply 或扩展为 `map(currency, number)` 形式。

## 常见问题

**Q: Cost Management 查询 403？**
A: 每个目标订阅需要 `Cost Management Reader`。该角色与 `Reader` 独立。

**Q: Resource Graph 查询为空？**
A: 检查 `Reader` 作用域；新建订阅同步到 ARG 索引有数分钟延迟。

**Q: 多订阅时某个订阅报错导致整个 apply 失败？**
A: 临时从 `subscription_ids` 中移除该订阅。

**Q: `enable_history=true` 之后磁盘一直涨怎么办？**
A: 通过外部 cron / systemd timer 定期清理 `reports/_history/` 中旧目录即可，例如：
```bash
find reports/_history -maxdepth 1 -mindepth 1 -mtime +30 -exec rm -rf {} +
```

## 最小自检

```bash
terraform init -upgrade
terraform validate
terraform fmt -recursive -check
terraform plan
```
