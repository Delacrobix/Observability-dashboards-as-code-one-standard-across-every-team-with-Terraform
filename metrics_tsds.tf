# Turns metrics-payments-* into a time series data stream (TSDS) so the
# saturation panel can use the ES|QL TS command. A TSDS needs index.mode
# set to time_series plus at least one dimension field; cpu.pct is marked
# as a gauge metric.
resource "elasticstack_elasticsearch_index_template" "metrics_payments" {
  name           = "metrics-payments"
  priority       = 200
  index_patterns = ["metrics-payments-*"]

  data_stream {}

  template {
    settings = jsonencode({
      index = {
        mode = "time_series"
        # The seed script writes several hours of history; widen the TSDS
        # accepted time window so those documents are not rejected.
        look_back_time = "12h"
      }
    })

    mappings = jsonencode({
      properties = {
        "@timestamp" = { type = "date" }
        host = {
          properties = {
            name = {
              type                  = "keyword"
              time_series_dimension = true
            }
          }
        }
        cpu = {
          properties = {
            pct = {
              type               = "double"
              time_series_metric = "gauge"
            }
          }
        }
      }
    })
  }
}
