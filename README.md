---
title: Fiction Bank dbt Project
tags: [dbt, banking, loans, analytics]
created: 2026-01-22
---

# Fiction Bank - Loan Analytics dbt Project

A fictional western-themed bank specializing in small real estate loans and personal lending.

## Overview

Fiction Bank focuses on:
- **Primary Mortgages** - Residential home loans
- **Home Equity Loans** - Home equity lines of credit
- **Personal Loans** - Unsecured personal lending

## Project Structure

### Seeds (Raw Data)
- `loan_types.csv` - Reference table for loan product types
- `raw_loans.csv` - Loan account information
- `raw_loan_payments.csv` - Payment transaction history

### Staging Models (`models/staging/`)
- `stg_loans` - Cleaned loan account data
- `stg_loan_payments` - Cleaned payment transactions

### Marts Models (`models/marts/`)
- `fct_loan_details` - Analytics table joining loans with loan types, includes LTV calculations
- `fct_monthly_loan_summary` - Monthly aggregation of originations and payment activity

## Key Metrics

The project tracks:
- Loan originations by month and type
- Payment collection metrics
- Loan-to-value (LTV) ratios for real estate loans
- Average loan sizes and interest rates

## Getting Started

```bash
# Install dependencies
dbt deps

# Load seed data
dbt seed

# Run all models
dbt run

# Run tests
dbt test
```
