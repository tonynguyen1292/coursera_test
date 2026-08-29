# The first thing that should exist in a fresh account, before anything
# billable. An accident you find out about in a day costs a coffee; the same
# accident found on next month's statement costs real money. This is cheap
# insurance and it is also the Cost-Optimized domain of SAA-C03 in practice
# rather than in theory.
#
# Two thresholds on purpose: ACTUAL tells you something already happened,
# FORECASTED tells you it is about to. The forecast alarm is the one that
# gives you time to act, which is why it fires at a lower percentage.

resource "aws_budgets_budget" "monthly" {
  name         = "${var.project_name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Actual spend has crossed half the ceiling.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_notification_email]
  }

  # Actual spend has crossed the ceiling itself.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_notification_email]
  }

  # Projected to cross the ceiling by month end -- the early warning, and the
  # one that catches a resource left running by mistake while the actual
  # number is still small.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_notification_email]
  }
}
