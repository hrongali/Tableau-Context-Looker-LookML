# =============================================================================
# fact_cases.view.lkml
# Generated from Atlan Context Repo: fact_cases.yaml
# Source: mccontext.silver.fact_cases (BigQuery)
# Mapping rules:
#   YAML dimensions       -> LookML dimension blocks
#   YAML time_dimensions  -> LookML dimension_group (type: time)
#   YAML measures (expr)  -> LookML measure blocks (type-driven, no raw SQL)
#   YAML filters          -> LookML yesno dimensions (governed predicates)
#   YAML synonyms         -> appended to LookML description (read by Gemini /
#                           Conversational Analytics for NL matching)
# =============================================================================

view: fact_cases {
  sql_table_name: `salesengineering-2022.mccontext_silver.fact_cases` ;;
  label: "Support Cases"
  description: "Support case lifecycle for McContext customer service. Each row represents a support case (ticket) with priority, SLA tracking, linked entities (charges, orders, outages, refunds), and resolution details."

  # ---------------------------------------------------------------------------
  # Dimensions
  # ---------------------------------------------------------------------------

  dimension: ticket_id {
    primary_key: yes
    type: string
    sql: ${TABLE}.ticket_id ;;
    description: "Unique identifier for the support case/ticket. Synonyms: case id, ticket number, case number."
  }

  dimension: ticket_number {
    type: string
    sql: ${TABLE}.ticket_number ;;
    description: "Human-readable ticket number."
  }

  dimension: customer_id {
    type: number
    hidden: yes
    sql: ${TABLE}.customer_id ;;
    description: "Customer who opened the case. Foreign key to customer_360."
  }

  dimension: status {
    type: string
    sql: ${TABLE}.status ;;
    description: "Current case status (open, pending, resolved, closed, escalated). Synonyms: case status, ticket status."
  }

  dimension: priority {
    type: string
    sql: ${TABLE}.priority ;;
    description: "Case priority level (low, normal, high, critical). Synonyms: urgency, case priority."
  }

  dimension: assigned_team {
    type: string
    sql: ${TABLE}.assigned_team ;;
    description: "Team currently handling the case. Synonyms: team, queue."
  }

  dimension: current_assignee_id {
    type: number
    sql: ${TABLE}.current_assignee_id ;;
    description: "Agent currently assigned to the case."
  }

  dimension: resolution_type {
    type: string
    sql: ${TABLE}.resolution_type ;;
    description: "How the case was resolved (Closed - no action, refund, credit, escalation, duplicate_charge_reversal). Synonyms: resolution, outcome."
  }

  dimension: intent_classified {
    type: string
    sql: ${TABLE}.intent_classified ;;
    description: "Classified intent of the customer's issue (food_quality, double_charge, outage, refund_request). Synonyms: intent, issue type, case type."
  }

  dimension: linked_charge_count {
    type: number
    sql: ${TABLE}.linked_charge_count ;;
    description: "Number of charges linked to this case."
  }

  dimension: linked_order_count {
    type: number
    sql: ${TABLE}.linked_order_count ;;
    description: "Number of orders linked to this case."
  }

  dimension: linked_refund_count {
    type: number
    sql: ${TABLE}.linked_refund_count ;;
    description: "Number of refunds linked to this case."
  }

  # ---------------------------------------------------------------------------
  # Time dimensions  (YAML time_dimensions -> LookML dimension_group)
  # Generates opened_date, opened_week, opened_month, opened_quarter, opened_year
  # ---------------------------------------------------------------------------

  dimension_group: opened {
    type: time
    timeframes: [raw, time, date, week, month, quarter, year]
    sql: ${TABLE}.opened_at ;;
    description: "When the case was opened. Synonyms: created at, case date."
  }

  dimension_group: first_response {
    type: time
    timeframes: [raw, time, date, week, month]
    sql: ${TABLE}.first_response_at ;;
    description: "When the first agent response was sent."
  }

  dimension_group: closed {
    type: time
    timeframes: [raw, time, date, week, month, quarter, year]
    sql: ${TABLE}.closed_at ;;
    description: "When the case was closed/resolved. Synonyms: resolved at, closure date."
  }

  # ---------------------------------------------------------------------------
  # Measures
  # ---------------------------------------------------------------------------

  measure: case_count {
    type: count
    description: "Number of support cases. Synonyms: ticket count, number of cases."
    drill_fields: [ticket_number, status, priority, intent_classified, opened_date]
  }

  # HERO METRIC for side-by-side walkthrough:
  #   YAML expr:   COUNT(CASE WHEN status IN ('open','pending') THEN 1 END)
  #   LookML:      declarative filtered count -- no raw SQL, no drift across
  #                dashboards. Gemini sees this as a single governed measure.
  measure: open_case_count {
    type: count
    description: "Number of currently open/pending cases."
    filters: [status: "open,pending"]
  }

  measure: credit_amount_usd {
    type: sum
    sql: ${TABLE}.credit_amount_usd ;;
    value_format_name: usd
    description: "Total credit amount issued on cases."
  }

  measure: refund_amount_usd {
    type: sum
    sql: ${TABLE}.refund_amount_usd ;;
    value_format_name: usd
    description: "Total refund amount on cases."
  }

  measure: time_to_first_response_seconds {
    type: average
    sql: ${TABLE}.time_to_first_response_seconds ;;
    value_format: "0"
    description: "Time from case open to first response in seconds. Synonyms: first response time, TTFR."
  }

  measure: time_to_first_response_hours {
    type: number
    sql: ${time_to_first_response_seconds} / 3600.0 ;;
    value_format: "0.00"
    description: "Time-to-first-response in hours (derived from seconds)."
  }

  measure: time_to_resolution_seconds {
    type: average
    sql: ${TABLE}.time_to_resolution_seconds ;;
    value_format: "0"
    description: "Time from case open to resolution in seconds. Synonyms: resolution time, TTR."
  }

  measure: time_to_resolution_hours {
    type: number
    sql: ${time_to_resolution_seconds} / 3600.0 ;;
    value_format: "0.00"
    description: "Time-to-resolution in hours (derived from seconds)."
  }

  # ---------------------------------------------------------------------------
  # Filters  (YAML filters -> LookML yesno dimensions = governed predicates)
  # Gemini / Conversational Analytics can use these directly as filter chips.
  # ---------------------------------------------------------------------------

  dimension: is_open_case {
    type: yesno
    sql: ${TABLE}.status IN ('open','pending') ;;
    description: "Currently open or pending cases."
  }

  dimension: is_escalated {
    type: yesno
    sql: ${TABLE}.status = 'escalated' ;;
    description: "Cases that have been escalated."
  }

  dimension: is_high_priority {
    type: yesno
    sql: ${TABLE}.priority IN ('high','critical') ;;
    description: "High or critical priority cases."
  }

  dimension: is_double_charge_case {
    type: yesno
    sql: ${TABLE}.intent_classified = 'double_charge' ;;
    description: "Cases classified as double-charge issues."
  }

  dimension: is_outage_case {
    type: yesno
    sql: ${TABLE}.intent_classified = 'outage' ;;
    description: "Cases related to outages."
  }
}
