locals {
  panel_library = {
    latency = {
      chart_type            = "xy"
      title                 = "Latency p95"
      x_json                = jsonencode({
        operation               = "date_histogram"
        field                   = "@timestamp"
        suggested_interval      = "auto"
        use_original_time_range = false
        include_empty_rows      = true
        drop_partial_intervals  = false
      })
      y_json                = jsonencode({
        operation  = "percentile"
        field      = "duration_ms"
        percentile = 95
      })
      esql_query_tpl        = ""
      esql_column           = ""
      esql_secondary_column = ""
      esql_format           = { type = "number", params = { decimals = 0 } }
    }
    traffic = {
      chart_type            = "xy"
      title                 = "Request rate"
      x_json                = jsonencode({
        operation               = "date_histogram"
        field                   = "@timestamp"
        suggested_interval      = "auto"
        use_original_time_range = false
        include_empty_rows      = true
        drop_partial_intervals  = false
      })
      y_json                = jsonencode({
        operation     = "count"
        empty_as_null = true
      })
      esql_query_tpl        = ""
      esql_column           = ""
      esql_secondary_column = ""
      esql_format           = { type = "number", params = { decimals = 0 } }
    }
    errors = {
      chart_type            = "metric"
      title                 = ""
      x_json                = ""
      y_json                = ""
      esql_query_tpl        = "FROM {idx} | WHERE @timestamp <= ?_tend AND @timestamp > ?_tstart | STATS `5xx errors` = COUNT(CASE(status >= 500, 1, null)), `4xx errors` = COUNT(CASE(status >= 400 AND status < 500, 1, null))"
      esql_column           = "5xx errors"
      esql_secondary_column = "4xx errors"
      esql_format           = { type = "number", params = { decimals = 0 } }
    }
    saturation = {
      chart_type            = "metric"
      title                 = ""
      x_json                = ""
      y_json                = ""
      # Saturation reads from the metrics index, so this query is not parameterized by {idx}.
      esql_query_tpl        = "FROM metrics-payments-* | WHERE @timestamp <= ?_tend AND @timestamp > ?_tstart | STATS `Avg CPU %` = ROUND(AVG(cpu.pct) * 100, 1), `Peak CPU %` = ROUND(MAX(cpu.pct) * 100, 1)"
      esql_column           = "Avg CPU %"
      esql_secondary_column = "Peak CPU %"
      esql_format           = { type = "number", params = { decimals = 2 } }
    }
    cart_value = {
      chart_type            = "metric"
      title                 = ""
      x_json                = ""
      y_json                = ""
      esql_query_tpl        = "FROM {idx} | WHERE @timestamp <= ?_tend AND @timestamp > ?_tstart | STATS `Total cart value` = ROUND(SUM(cart_total), 2), `Avg cart value` = ROUND(AVG(cart_total), 2)"
      esql_column           = "Total cart value"
      esql_secondary_column = "Avg cart value"
      esql_format           = { type = "number", params = { decimals = 2 } }
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

  panels = concat(
    [
      for i, p in each.value.panels : {
        type = "vis"
        grid = local.panel_library[p].chart_type == "metric" ? {
          x = (i % 2) * 24
          y = 0
          w = 24
          h = 5
        } : {
          x = ((i - 2) % 2) * 24
          y = 5
          w = 24
          h = 10
        }

        # Metric panels use config_json to access styling (not available in typed vis_config).
        config_json = local.panel_library[p].chart_type == "metric" ? jsonencode({
          type                  = "metric"
          sampling              = 1
          ignore_global_filters = false
          data_source = {
            type  = "esql"
            query = replace(local.panel_library[p].esql_query_tpl, "{idx}", each.value.index)
          }
          metrics = concat(
            [{
              type           = "primary"
              column         = local.panel_library[p].esql_column
              color          = { type = "auto" }
              apply_color_to = "value"
            }],
            local.panel_library[p].esql_secondary_column != "" ? [{
              type    = "secondary"
              column  = local.panel_library[p].esql_secondary_column
              compare = { to = "primary", palette = "compare_to", icon = true, value = true }
              color   = { type = "none" }
            }] : []
          )
          styling = {
            primary = {
              position = "bottom"
              labels   = { alignment = "left" }
              value    = { sizing = "auto", alignment = "left" }
            }
            secondary = {
              label = { visible = false }
              value = { alignment = "left" }
            }
          }
        }) : null

        vis_config = local.panel_library[p].chart_type == "xy" ? {
          by_value = {
            xy_chart_config = {
              title = local.panel_library[p].title
              axis = {
                x = {
                  ticks             = true
                  grid              = true
                  label_orientation = "horizontal"
                  title             = { visible = false }
                }
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
                  type = "area"
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
            }
            metric_chart_config = null
            datatable_config    = null
          }
        } : null
      }
    ],
    [{
      type = "vis"
      grid = { x = 0, y = 15, w = 48, h = 12 }
      vis_config = {
        by_value = {
          datatable_config = {
            esql = {
              title            = "Request breakdown by status"
              data_source_json = jsonencode({
                type  = "esql"
                query = "FROM ${each.value.index} | WHERE @timestamp <= ?_tend AND @timestamp > ?_tstart | STATS `Requests` = COUNT(*), `Avg latency (ms)` = ROUND(AVG(duration_ms), 0) BY `Status` = TO_STRING(status) | SORT `Requests` DESC"
              })
              metrics = [
                {
                  config_json = jsonencode({
                    column         = "Requests"
                    apply_color_to = "badge"
                    color          = { type = "auto" }
                  })
                },
                {
                  config_json = jsonencode({
                    column         = "Avg latency (ms)"
                    apply_color_to = "badge"
                    color          = { type = "auto" }
                  })
                }
              ]
              rows = [{
                config_json = jsonencode({
                  column = "Status"
                })
              }]
              styling = {
                density = { mode = "expanded" }
              }
            }
          }
          metric_chart_config = null
          xy_chart_config     = null
        }
      }
    }]
  )
}
