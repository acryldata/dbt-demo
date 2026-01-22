-- Analytics table: Loan details joined with loan types
-- Provides comprehensive loan information with type metadata

with loans as (
    select * from {{ ref('stg_loans') }}
),

loan_types as (
    select * from {{ ref('loan_types') }}
),

loan_details as (
    select
        loans.loan_id,
        loans.customer_id,
        loans.loan_type_id,
        loan_types.loan_type_name,
        loan_types.description as loan_type_description,
        loans.loan_amount,
        loans.interest_rate,
        loans.loan_start_date,
        loans.loan_term_months,
        loan_types.typical_term_months,
        loans.property_address,
        loans.property_value,
        -- Calculate loan-to-value ratio for real estate loans
        case
            when loans.property_value > 0
            then round((loans.loan_amount::numeric / loans.property_value::numeric) * 100, 2)
            else null
        end as ltv_ratio,
        -- Calculate monthly payment estimate (simplified)
        round(
            loans.loan_amount * (loans.interest_rate / 100 / 12) *
            power(1 + (loans.interest_rate / 100 / 12), loans.loan_term_months) /
            (power(1 + (loans.interest_rate / 100 / 12), loans.loan_term_months) - 1),
            2
        ) as estimated_monthly_payment
    from loans
    left join loan_types
        on loans.loan_type_id = loan_types.loan_type_id
)

select * from loan_details
