locals {
  panel_library = {
    latency = {
      chart_type     = "xy"
      title          = "Latency p95"
      x_json         = jsonencode({
        operation               = "date_histogram"
        field                   = "@timestamp"
        suggested_interval      = "auto"
        use_original_time_range = false
        include_empty_rows      = true
        drop_partial_intervals  = false
      })
      y_json         = jsonencode({
        operation  = "percentile"
        field      = "duration_ms"
        percentile = 95
      })
      esql_query_tpl = ""
      esql_column    = ""
      esql_format    = { type = "number", params = { decimals = 0 } }
    }
    traffic = {
      chart_type     = "xy"
      title          = "Request rate"
      x_json         = jsonencode({
        operation               = "date_histogram"
        field                   = "@timestamp"
        suggested_interval      = "auto"
        use_original_time_range = false
        include_empty_rows      = true
        drop_partial_intervals  = false
      })
      y_json         = jsonencode({
        operation     = "count"
        empty_as_null = true
      })
      esql_query_tpl = ""
      esql_column    = ""
      esql_format    = { type = "number", params = { decimals = 0 } }
    }
    errors = {
      chart_type     = "metric"
      title          = "Error rate"
      x_json         = ""
      y_json         = ""
      esql_query_tpl = "FROM {idx} | WHERE status >= 400 | STATS errors = COUNT(*)"
      esql_column    = "errors"
      esql_format    = { type = "number", params = { decimals = 0 } }
    }
    saturation = {
      chart_type     = "metric"
      title          = "Saturation (CPU)"
      x_json         = ""
      y_json         = ""
      # Saturation reads from the metrics index, so this query is not parameterized by {idx}.
      esql_query_tpl = "FROM metrics-payments-* | STATS avg_cpu = AVG(cpu.pct)"
      esql_column    = "avg_cpu"
      esql_format    = { type = "number", params = { decimals = 2 } }
    }
    cart_value = {
      chart_type     = "metric"
      title          = "Cart value"
      x_json         = ""
      y_json         = ""
      esql_query_tpl = "FROM {idx} | STATS total = SUM(cart_total)"
      esql_column    = "total"
      esql_format    = { type = "number", params = { decimals = 2 } }
    }
  }

  teams = {
    payments = {
      index  = "logs-payments-*"
      panels = ["errors", "saturation", "latency", "traffic"]
    }
    checkout = {
      index  = "logs-checkout-*"
      panels = ["errors", "cart_value", "latency", "traffic"]
    }
  }
}

resource "elasticstack_kibana_dashboard" "golden_signals" {
  for_each    = local.teams
  title       = "Golden Signals - ${each.key}"
  description = "Latency, traffic, and errors for the ${each.key} service"

  query            = { language = "kql", text = "" }
  refresh_interval = { pause = false, value = 60000 }
  time_range       = { from = "now-15m", to = "now" }

  panels = [
    for i, p in each.value.panels : {
      type = "vis"
      grid = local.panel_library[p].chart_type == "metric" ? {
        x = (i % 2) * 24
        y = 0
        w = 24
        h = 6
      } : {
        x = ((i - 2) % 2) * 24
        y = 6
        w = 24
        h = 10
      }
      vis_config = {
        by_value = {
          xy_chart_config = local.panel_library[p].chart_type == "xy" ? {
            title       = local.panel_library[p].title
            axis = {
              y = {
                domain_json       = jsonencode({ type = "full", rounding = true })
                grid              = true
                label_orientation = "horizontal"
                scale             = "linear"
                ticks             = true
                title             = { visible = false }
              }
            }
            decorations = {}
            fitting     = { type = "none" }
            legend = {
              visibility = "visible"
              position   = "bottom"
              size       = "m"
              inside     = false
            }
            query = { expression = "" }
            layers = [
              {
                type = "line"
                data_layer = {
                  data_source_json = jsonencode({
                    type          = "data_view_spec"
                    index_pattern = each.value.index
                    time_field    = "@timestamp"
                  })
                  x_json = local.panel_library[p].x_json
                  y      = [{ config_json = local.panel_library[p].y_json }]
                }
              }
            ]
          } : null

          metric_chart_config = local.panel_library[p].chart_type == "metric" ? {
            title = local.panel_library[p].title
            data_source_json = jsonencode({
              type  = "esql"
              query = replace(local.panel_library[p].esql_query_tpl, "{idx}", each.value.index)
            })
            metrics = [{
              config_json = jsonencode({
                type   = "primary"
                column = local.panel_library[p].esql_column
              })
            }]
          } : null
        }
      }
    }
  ]
}
