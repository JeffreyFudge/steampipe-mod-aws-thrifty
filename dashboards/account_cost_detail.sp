dashboard "account_cost_detail" {

  title = "AWS Account Detail"

  tags = merge(local.account_common_tags, {
    type = "Detail"
  })

  input "account_id" {
    title = "Select an account:"
    query = query.account_id_input
    width = 4
  }

  container {
    card {
      query = query.account_current_cost_mtd
      width = 3
      args  = [self.input.account_id.value]
    }

    card {
      query = query.account_forecast_cost_mtd
      width = 3
      args  = [self.input.account_id.value]
    }

    card {
      query = query.account_current_cost_ytd
      width = 3
      args  = [self.input.account_id.value]
    }

    card {
      query = query.account_forecast_cost_ytd
      width = 3
      args  = [self.input.account_id.value]
    }
  }

  container {

    chart {
      title = "Cost by Month"
      query = query.account_cost_last_twelve_months
      type  = "line"
      args  = [self.input.account_id.value]

      axes {
        x {
          title {
            value = "Month"
          }
          labels {
            display = "always"
          }
        }

        y {
          title {
            value = "Cost($)"
          }
          labels {
            display = "always"
          }
        }
      }
    }

    chart {
      type     = "column"
      title    = "Top 5 Most Used Services Comaprison with Previous Month"
      grouping = "compare"
      query    = query.account_comparision_by_service
      width    = 6
      args     = [self.input.account_id.value]

      series previous_month {
        title = "Previous Month"
        color = "green"
      }

      series current_month {
        title = "Current Month"
        color = "red"
      }
    }
  }

}

# Input queries

query "account_id_input" {
  sql = <<-EOQ
    select
      title as label,
      account_id as value,
      json_build_object(
        'account_aliases', account_aliases
      ) as tags
    from
      aws_account
    order by
      title;
  EOQ
}

query "account_current_cost_mtd" {
  sql = <<-EOQ
    select
      'Current MTD' as label,
      net_unblended_cost_amount as value
    from
      aws_cost_by_account_monthly
   where
    date(period_end) = date(current_timestamp)
    and account_id = $1
  EOQ
}

query "account_forecast_cost_mtd" {
  sql = <<-EOQ
    select
      'Forecast MTD' as label,
      net_unblended_cost_amount + mean_value as value
    from
      aws_cost_by_account_monthly as m,
      aws_cost_forecast_daily as d
   where
    date(m.period_end) = date(current_timestamp)
    and date(d.period_start) = date(current_timestamp)
    and m.account_id = $1
    and d.account_id = $1
  EOQ
}

query "account_current_cost_ytd" {
  sql = <<-EOQ
    select
      'Current YTD' as label,
      sum(unblended_cost_amount) as value
    from
      aws_cost_by_account_monthly
    where
      period_start >= date_trunc('year', now())
      and period_end <= now()
      and linked_account_id = $1
    group by
      linked_account_id
  EOQ
}

query "account_forecast_cost_ytd" {
  sql = <<-EOQ
    select
      'Forecast YTD' as label,
      sum(unblended_cost_amount) + mean_value as value
    from
      aws_cost_by_account_monthly as m,
      aws_cost_forecast_daily as d
    where
      m.period_start >= date_trunc('year', now())
      and m.period_end <= now()
      and m.linked_account_id = $1
      and date(d.period_start) = date(current_timestamp)
      and d.account_id = $1
    group by
      linked_account_id,
      mean_value
  EOQ
}

query "account_cost_last_twelve_months" {
  sql = <<-EOQ
    select
      period_start as label,
      unblended_cost_amount as value
    from
      aws_cost_by_account_monthly
    where
      account_id = $1
    order by
      period_start
  EOQ
}

query "account_cost_by_service" {
  sql = <<-EOQ
    select
      period_start as label,
      unblended_cost_amount as value
    from
      aws_cost_by_account_monthly
    where
      account_id = $1
  EOQ
}

query "account_comparision_by_service" {
  sql = <<-EOQ
    with previous_month as (
      select
        service as service,
        'previous_month' as type,
        sum(net_unblended_cost_amount) as previous_cost
      from
        aws_cost_by_service_monthly
      where
        period_start >= (date_trunc('month', now()) -interval '1 month')
        and period_end <= date_trunc('month', now())
        and account_id = $1
      group by service
      order by previous_cost desc
    ), current_month as (
    select
      m.service as service,
      'current_month' as type,
      sum(net_unblended_cost_amount) as current_cost
    from
      aws_cost_by_service_monthly as m
      left join previous_month as p on p.service = m.service
    where
      period_start >= date_trunc('month', now())
      and period_end <= now()
      and account_id = $1
    group by m.service
    order by current_cost desc
    limit 5
    ), data as (
      select
        service as service,
        type as type,
        previous_cost as cost
      from
        previous_month
      where service in (select  service from current_month)
      union
      select
        service as service,
        type as type,
        current_cost as cost
      from
        current_month
    )
    select
      service,
      type,
      cost
    from
      data
    group by service, type, cost
  EOQ
}