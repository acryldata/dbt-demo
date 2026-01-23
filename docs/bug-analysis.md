---
title: "Bug Analysis: Join Fan-Out Pattern"
tags: [bug-analysis, sql-antipattern, data-quality]
created: 2026-01-23
---

# Bug Analysis: Add customer_id to Monthly Loan Aggregations

## Overview

**Branch:** `feat/add-customer-id`
**File Changed:** `models/marts/agg_monthly_loans.sql`

This PR introduces a classic join fan-out bug that multiplies aggregate rows when joining monthly summaries to individual loan records.

## The Bug

### Code Change

**Before (Correct):**
```sql
combined as (
    select
        coalesce(orig.month_start, pay.month_start) as month,
        orig.loan_type_name,
        coalesce(orig.loans_originated, 0) as new_loans,
        coalesce(orig.total_amount_originated, 0) as amount_originated,
        -- ... other aggregates ...
    from monthly_originations orig
    full outer join monthly_payments pay
        on orig.month_start = pay.month_start
)
```

**After (Buggy):**
```sql
combined as (
    select
        coalesce(orig.month_start, pay.month_start) as month,
        orig.loan_type_name,
        loans.customer_id,                           -- ✗ Added customer_id
        coalesce(orig.loans_originated, 0) as new_loans,
        coalesce(orig.total_amount_originated, 0) as amount_originated,
        -- ... other aggregates ...
    from monthly_originations orig
    full outer join monthly_payments pay
        on orig.month_start = pay.month_start
    left join loans                                  -- ✗ Join to loan-level table
        on orig.loan_type_name = loans.loan_type_name
)
```

### What Changed

1. **Added join to `loans` table** - Joins monthly aggregates to individual loan records
2. **Joined on `loan_type_name`** - A non-unique key that creates a one-to-many relationship
3. **Added `customer_id` to output** - Brings loan-level detail into an aggregation model
4. **Result**: Each monthly row multiplies by the number of loans of that type

## Why This Happens

### The Mental Model Mistake

A junior analyst thinks:
- "I have monthly aggregates for each loan type"
- "I want to add customer information"
- "I'll join to the loans table to get customer_id"

**What they missed**: The granularity mismatch.

### The Math

If a month has:
- **1 row** in monthly_originations for "Mortgage" loans
- **3 individual Mortgage loans** in the loans table

When you join on `loan_type_name`:
- 1 row × 3 matching loans = **3 rows** in the output
- All 3 rows show the same monthly aggregates
- The aggregates get **triple-counted**

## Data Impact

### Example: February 2023

**Original (Correct):**
| month | loan_type_name | new_loans | amount_originated |
|-------|----------------|-----------|-------------------|
| 2023-02-01 | Mortgage | 1 | $200,000 |

**After Bug:**
| month | loan_type_name | customer_id | new_loans | amount_originated |
|-------|----------------|-------------|-----------|-------------------|
| 2023-02-01 | Mortgage | C001 | 1 | $200,000 |
| 2023-02-01 | Mortgage | C003 | 1 | $200,000 |
| 2023-02-01 | Mortgage | C007 | 1 | $200,000 |

Now when someone sums up `amount_originated`, they get $600,000 instead of $200,000!

### Overall Impact

| Metric | Impact |
|--------|--------|
| **Row Multiplication** | Each monthly row becomes N rows (where N = loans of that type) |
| **Data Accuracy** | Aggregates appear correct per row, but sum to wrong totals |
| **Root Cause** | Joining aggregated data (monthly) to detail data (individual loans) |
| **Visibility** | Subtle - individual rows look fine, but totals are wrong |

## Why This Bug Is Realistic

This is **extremely common** among junior analysts because:

1. **It compiles** - No SQL errors
2. **It seems logical** - "I need customer info, so I'll join to get it"
3. **Rows look correct** - Each individual row has valid data
4. **The error is in totals** - Only shows up when you sum or count across rows
5. **Easy to miss in small data** - Works "fine" when there's only one loan per type

## Intended Purpose

The analyst wanted to see which customers were associated with each month's activity. This is a reasonable business question, but the implementation is wrong.

**What they should have done:**
- Keep the aggregation model as-is (no customer_id)
- Create a separate detail model that shows loan-level information
- Or aggregate customer counts: `count(distinct customer_id)` instead of joining

## How To Detect

### SQL Code Review

Look for:
- Joins between aggregated CTEs and detail-level tables
- Joins on non-unique keys (like `loan_type_name`)
- Adding detail fields to aggregate models

### Data Quality Test

```sql
-- Test: Row count should match expected monthly periods
with expected_months as (
    select distinct
        date_trunc('month', loan_start_date)::date as month,
        loan_type_name
    from {{ ref('fct_loan_details') }}
),
actual_months as (
    select distinct month, loan_type_name
    from {{ ref('agg_monthly_loans') }}
)
select
    count(*) as expected_rows,
    (select count(*) from actual_months) as actual_rows,
    (select count(*) from actual_months) - count(*) as extra_rows
from expected_months
having (select count(*) from actual_months) != count(*)
```

## The Fix

**Option 1: Remove the join entirely**
```sql
-- Keep the aggregation model pure
combined as (
    select
        coalesce(orig.month_start, pay.month_start) as month,
        orig.loan_type_name,
        -- Don't add customer_id
        coalesce(orig.loans_originated, 0) as new_loans,
        ...
    from monthly_originations orig
    full outer join monthly_payments pay
        on orig.month_start = pay.month_start
)
```

**Option 2: Create a separate detail model**
```sql
-- Create a new model: loan_monthly_detail.sql
select
    date_trunc('month', loan_start_date)::date as month,
    loan_type_name,
    customer_id,
    loan_id,
    loan_amount
from {{ ref('fct_loan_details') }}
```

## Lessons Learned

1. **Understand data granularity** - Don't mix monthly aggregates with loan-level details
2. **Joins on non-unique keys create fan-out** - One row becomes many
3. **Keep aggregation models pure** - Don't add detail fields to summary tables
4. **Create separate models for different granularities** - One model for monthly totals, another for loan details
5. **Test row counts** - Unexpected row counts are a red flag

## Related Patterns

This is an example of the **"Join Fan-Out"** anti-pattern, related to:
- Joining on non-unique keys without understanding cardinality
- Mixing different levels of aggregation in one model
- "Just one more column" syndrome - adding fields without considering impact

## References

- [The Data Warehouse Toolkit](https://www.kimballgroup.com/data-warehouse-business-intelligence-resources/books/data-warehouse-dw-toolkit/) - Chapter on fact table grain
- [dbt Best Practices: Model Naming](https://docs.getdbt.com/guides/best-practices/how-we-structure/1-guide-overview)
- [SQL Anti-Patterns: Ambiguous Groups](https://pragprog.com/titles/bksqla/sql-antipatterns/)
