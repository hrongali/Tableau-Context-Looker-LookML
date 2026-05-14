# =============================================================================
# mccontext.model.lkml
# Model file ties views together into explores that Conversational Analytics
# (Gemini in Looker) can query in natural language.
#
# IMPORTANT: replace `bq_mccontext` below with the actual name of the BigQuery
# connection you create in Looker Admin -> Connections.
# =============================================================================

connection: "bq_mccontext"

# Include all views from the /views directory
include: "/views/*.view.lkml"

# -----------------------------------------------------------------------------
# Explore: customer_support
#
# Primary entry point for Conversational Analytics. Joins customer_360 to
# fact_cases on customer_id so questions like "show me open cases for Platinum
# customers" can be answered in one query.
# -----------------------------------------------------------------------------
explore: customer_support {
  label: "Customer Support 360"
  description: "Customer profiles joined to support case history. Use this for any question that combines customer attributes (tier, Plus status, LTV) with case-level facts (status, priority, resolution time, intent)."

  from: customer_360
  view_name: customer_360

  join: fact_cases {
    type: left_outer
    relationship: one_to_many
    sql_on: ${customer_360.customer_id} = ${fact_cases.customer_id} ;;
  }
}

# -----------------------------------------------------------------------------
# Explore: cases_only
#
# Standalone explore on fact_cases. Useful when the question is purely about
# case operations (queues, SLAs, intents) and customer attributes aren't needed.
# -----------------------------------------------------------------------------
explore: cases_only {
  label: "Support Cases"
  description: "Operational view of support cases. Use this for SLA, queue, priority, intent, and resolution questions that don't need customer attributes."
  from: fact_cases
  view_name: fact_cases
}
