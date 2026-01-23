with source as (
    select * from {{ ref('raw_loans') }}
),

renamed as (
    select
        loan_id,
        customer_id,
        loan_type_id,
        loan_amount,
        interest_rate,
        loan_start_date::date as loan_start_date,
        loan_term_months,
        property_address,
        property_value
    from source
)

select * from renamed
