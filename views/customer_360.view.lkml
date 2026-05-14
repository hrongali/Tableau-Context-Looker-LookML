# =============================================================================
# customer_360.view.lkml
# Generated from Atlan Context Repo: customer_360.yaml
# Source: mccontext.gold.customer_360 (BigQuery)
# =============================================================================

view: customer_360 {
  sql_table_name: `salesengineering-2022.mccontext_gold.customer_360` ;;
  label: "Customer 360"

  # ---------------------------------------------------------------------------
  # Dimensions
  # ---------------------------------------------------------------------------

  dimension: customer_id {
    primary_key: yes
    type: number
    sql: ${TABLE}.customer_id ;;
    description: "Unique customer identifier (joins to all fact tables)."
  }

  dimension: full_name {
    type: string
    sql: ${TABLE}.full_name ;;
    description: "Customer's full name. Synonyms: name, customer name."
  }

  dimension: email {
    type: string
    sql: ${TABLE}.email ;;
    description: "Customer's email address."
  }

  dimension: phone {
    type: string
    sql: ${TABLE}.phone ;;
    description: "Customer's phone number."
  }

  dimension: plus_subscriber {
    type: yesno
    sql: ${TABLE}.plus_subscriber ;;
    description: "Whether customer is a Plus subscriber. Synonyms: Plus member, Plus status, subscription status."
  }

  dimension: loyalty_tier {
    type: string
    sql: ${TABLE}.loyalty_tier ;;
    description: "Customer loyalty tier (Bronze, Silver, Gold, Platinum). Synonyms: tier, loyalty level, rewards tier."
  }

  dimension: subscription_plan {
    type: string
    sql: ${TABLE}.subscription_plan ;;
    description: "Current subscription plan name. Synonyms: plan, membership plan."
  }

  # ---------------------------------------------------------------------------
  # Time dimensions
  # ---------------------------------------------------------------------------

  dimension_group: signup {
    type: time
    timeframes: [raw, date, week, month, quarter, year]
    convert_tz: no
    datatype: date
    sql: ${TABLE}.signup_date ;;
    description: "When the customer first signed up. Synonyms: join date, registration date."
  }

  dimension_group: last_order {
    type: time
    timeframes: [raw, time, date, week, month, quarter, year]
    sql: ${TABLE}.last_order_at ;;
    description: "Most recent order timestamp. Synonyms: last activity, last purchase."
  }

  dimension_group: refreshed {
    type: time
    timeframes: [raw, time, date]
    sql: ${TABLE}.refreshed_at ;;
    description: "When this profile was last refreshed."
  }

  # ---------------------------------------------------------------------------
  # Measures
  # ---------------------------------------------------------------------------

  measure: lifetime_spend_usd {
    type: sum
    sql: ${TABLE}.lifetime_spend_usd ;;
    value_format_name: usd
    description: "Total customer lifetime spend in USD. Synonyms: LTV, lifetime value, total spend, CLV."
  }

  measure: lifetime_refund_usd {
    type: sum
    sql: ${TABLE}.lifetime_refund_usd ;;
    value_format_name: usd
    description: "Total refund amount issued. Synonyms: total refunds, refund amount."
  }

  measure: avg_csat {
    type: average
    sql: ${TABLE}.avg_csat_last_5 ;;
    value_format: "0.00"
    description: "Average CSAT score from last 5 interactions. Synonyms: satisfaction score, CSAT."
  }

  measure: lifetime_orders {
    type: sum
    sql: ${TABLE}.lifetime_orders ;;
    description: "Total number of orders placed. Synonyms: order count, total orders."
  }

  measure: open_case_count {
    type: sum
    sql: ${TABLE}.open_case_count ;;
    description: "Number of currently open support cases (pre-aggregated)."
  }

  measure: lifetime_case_count {
    type: sum
    sql: ${TABLE}.lifetime_case_count ;;
    description: "Total support cases ever opened. Synonyms: total cases, case count."
  }

  measure: earn_multiplier {
    type: average
    sql: ${TABLE}.earn_multiplier ;;
    value_format: "0.00"
    description: "Loyalty points earn multiplier."
  }

  measure: mrr_usd {
    type: sum
    sql: ${TABLE}.mrr_usd ;;
    value_format_name: usd
    description: "Monthly recurring revenue from this customer. Synonyms: MRR, monthly revenue."
  }

  measure: customer_count {
    type: count_distinct
    sql: ${customer_id} ;;
    description: "Distinct customers."
  }

  # ---------------------------------------------------------------------------
  # Filters  (YAML filters -> LookML yesno dimensions = governed predicates)
  # ---------------------------------------------------------------------------

  dimension: is_plus_subscriber {
    type: yesno
    sql: ${TABLE}.plus_subscriber = true ;;
    description: "Active Plus subscribers only."
  }

  dimension: is_high_value_customer {
    type: yesno
    sql: ${TABLE}.lifetime_spend_usd > 1000 ;;
    description: "Customers with lifetime spend over $1000."
  }

  dimension: is_at_risk {
    type: yesno
    sql: ${TABLE}.avg_csat_last_5 < 3.0 ;;
    description: "Customers with low CSAT (below 3.0)."
  }

  dimension: is_platinum_tier {
    type: yesno
    sql: ${TABLE}.loyalty_tier = 'Platinum' ;;
    description: "Platinum loyalty tier customers."
  }

  dimension: has_open_cases {
    type: yesno
    sql: ${TABLE}.open_case_count > 0 ;;
    description: "Customers with at least one open case."
  }
}
