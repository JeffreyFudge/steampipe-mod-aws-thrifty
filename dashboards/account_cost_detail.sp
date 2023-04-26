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
      query = query.account_previous_month_cost_mtd
      width = 2
      args  = [self.input.account_id.value]
    }

    card {
      query = query.account_forecast_cost_mtd
      width = 2
      args  = [self.input.account_id.value]
    }

    card {
      query = query.account_current_cost_mtd
      width = 2
      args  = [self.input.account_id.value]
    }

    card {
      query = query.account_forecast_cost_ytd
      width = 2
      args  = [self.input.account_id.value]
    }

    card {
      query = query.account_current_cost_ytd
      width = 2
      args  = [self.input.account_id.value]
    }

    card {
      query = query.account_currency
      width = 2
    }

  }

  container {

    chart {
      title = "Cost by Month"
      query = query.account_cost_last_twelve_months
      type  = "line"
      width = 6
      args  = [self.input.account_id.value]

      axes {
        y {
          title {
            value = "Cost"
          }
          labels {
            display = "always"
          }
        }
      }
    }

    chart {
      title = "Cost by Date - MTD"
      query = query.account_cost_mtd
      type  = "column"
      width = 6
      args  = [self.input.account_id.value]

      axes {
        y {
          title {
            value = "Cost"
          }
          labels {
            display = "always"
          }
        }
      }
    }
  }

  ## All Service by cost
  container {

    chart {
      type  = "column"
      title = "Top 15 Cost by Services - YTD"
      query = query.account_service_stack_chart
      legend {
        position = "bottom"
      }
      args  = [self.input.account_id.value]
    }
  }

  container {

    chart {
      title = "Top 5 Most Used Services Cost - MTD"
      width = 6
      query = query.account_top_5_service_by_mtd
      type  = "column"
      args  = [self.input.account_id.value]
      legend {
        position = "bottom"
      }
    }

    chart {
      type     = "column"
      title    = "Top 5 Most Used Services Comaprison with Previous Month"
      grouping = "compare"
      query    = query.account_comparision_by_service
      width    = 6
      args     = [self.input.account_id.value]

      legend {
        position = "bottom"
      }

      series "previous_month" {
        title = "Previous Month"
        color = "red"
      }

      series "current_month" {
        title = "Current Month"
        color = "green"
      }
    }
  }

  container {

    input "service" {
      title = "Account Cost by Service"
      type  = "multiselect"
      placeholder = "Choose services"
      width = "6"
      query = query.account_service_input
    }

    container {
      chart {
        title = "Per Service MTD"
        query = query.account_service_mtd_trend
        type  = "column"
        width = "6"
        args  = [self.input.service.value, self.input.account_id.value]
        legend {
          position = "bottom"
        }
      }

      chart {
        title = "Per Service YTD"
        query = query.account_service_ytd_trend
        type  = "column"
        width = "6"
        args  = [self.input.service.value, self.input.account_id.value]
        legend {
          position = "bottom"
        }
      }
    }
  }

  container {

    title = "Services by Cost - MTD"

    table {
      width = 12
      query = query.account_service_by_usage_mtd
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
        'account_id', account_id
      ) as tags
    from
      aws_account
    order by
      title;
  EOQ
}

query "account_service_input" {
  sql = <<-EOQ
    select
      distinct service as value,
      service as label
    from
      aws_cost_by_service_monthly
    group by service, period_start
    order by service
  EOQ
}

query "account_current_cost_mtd" {
  sql = <<-EOQ
    with previous_month as (
      select
        net_unblended_cost_amount as previous_month_cost
      from
        aws_cost_by_account_monthly
      where
        period_start >= (date_trunc('month', now()) -interval '1 month')
        and period_end <= date_trunc('month', now())
        and account_id = $1
    )
    select
      'Current MTD (' || net_unblended_cost_unit || ')' as label,
      net_unblended_cost_amount::numeric(10,2)::text as value,
      case when previous_month_cost > net_unblended_cost_amount then 'ok' else 'alert' end as type
    from
      aws_cost_by_account_monthly,
      previous_month
    where
    date(period_end) = date(current_timestamp)
    and account_id = $1;
  EOQ
}

query "account_previous_month_cost_mtd" {
  sql = <<-EOQ
   select
      'Invoice Previous Month (' || net_unblended_cost_unit || ')' as label,
      cast((net_unblended_cost_amount) as numeric(10,2))::text as value
    from
      aws_cost_by_account_monthly
    where
      period_start >= (date_trunc('month', now()) -interval '1 month')
      and period_end <= date_trunc('month', now())
      and account_id = $1
  EOQ
}

query "account_forecast_cost_mtd" {
  sql = <<-EOQ
    with forecast_cost_till_month_end as (
      select
        sum(mean_value) as forecast
      from
        aws_cost_forecast_daily
      where
        to_char(period_start, 'YYYY-MM') = to_char(now(), 'YYYY-MM')
        and account_id = $1
    )
    select
      'Month-End Forecast (' || net_unblended_cost_unit || ')' as label,
      cast((net_unblended_cost_amount + forecast) as numeric(10,2))::text as value
    from
      aws_cost_by_account_monthly as m,
      forecast_cost_till_month_end
    where
      date(m.period_end) = date(current_timestamp)
      and m.account_id = $1
  EOQ
}

query "account_current_cost_ytd" {
  sql = <<-EOQ
    select
      'Current YTD (' || unblended_cost_unit || ')' as label,
      sum(unblended_cost_amount)::numeric(10,2)::text as value
    from
      aws_cost_by_account_monthly
    where
      period_start >= date_trunc('year', now())
      and period_end <= now()
      and linked_account_id = $1
    group by
      linked_account_id,
      unblended_cost_unit;
  EOQ
}

query "account_forecast_cost_ytd" {
  sql = <<-EOQ
    select
      'Forecast YTD (' || m.unblended_cost_unit || ')' as label,
      cast((sum(unblended_cost_amount) + mean_value) as numeric(10,2))::text as value
      -- sum(unblended_cost_amount) + mean_value as value
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
      mean_value,
      m.unblended_cost_unit;
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

query "account_cost_mtd" {
  sql = <<-EOQ
     select
      date(period_start),
      unblended_cost_amount as value
    from
      aws_cost_by_account_daily
    where
      period_start >= date_trunc('month', now())
      and period_end <= now()
      and account_id = $1
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
        current_cost as cost
      from
        current_month
      union
      select
        service as service,
        type as type,
        previous_cost as cost
      from
        previous_month
      where service in (select  service from current_month)
    )
    select
      service,
      type,
      cost
    from
      data
    group by service, type, cost
    order by type desc
  EOQ
}

query "account_service_stack_chart" {
  sql = <<-EOQ
    with used_services as (
      select
        service,
        period_start,
        trunc(sum(net_unblended_cost_amount)::numeric, 2) as current_month_cost
      from
        aws_cost_by_service_monthly
      where
        account_id = $1
        and service like any (array ['Amazon Elastic Container Service', 'AWS Key Management Service', 'Amazon CloudFront', 'Amazon ElastiCache', 'Amazon Elastic Compute Cloud - Compute', 'Amazon Elastic Load Balancing', 'Amazon GuardDuty', 'Amazon Redshift', 'Amazon Relational Database Service', 'EC2 - Other', 'Amazon Virtual Private Cloud', 'Amazon Simple Storage Service', 'Amazon Simple Notification Service', 'Amazon Simple Queue Service'])
      group by service, period_start
      order by period_start asc
    ),
    cost_sum_other_service as (
      select
        'Others' as service,
        period_start,
        trunc(sum(net_unblended_cost_amount)::numeric, 2) as current_month_cost
      from
        aws_cost_by_service_monthly
      where
        account_id = $1
        and service not in ('Amazon Elastic Container Service', 'AWS Key Management Service', 'Amazon CloudFront', 'Amazon ElastiCache', 'Amazon Elastic Compute Cloud - Compute', 'Amazon Elastic Load Balancing', 'Amazon GuardDuty', 'Amazon Redshift', 'Amazon Relational Database Service', 'EC2 - Other', 'Amazon Virtual Private Cloud', 'Amazon Simple Storage Service', 'Amazon Simple Notification Service', 'Amazon Simple Queue Service')
      group by period_start
      order by period_start asc
    )
    select
      period_start,
      service,
      sum(current_month_cost)
    from
      used_services
    where
      current_month_cost > 0
    group by
      period_start, service
    union
    select
      period_start,
      service,
      sum(current_month_cost)
    from
      cost_sum_other_service
    group by
      period_start, service
  EOQ
}

query "account_service_mtd_trend" {
  sql = <<-EOQ
    select
      period_start,
      service,
      sum(net_unblended_cost_amount)
    from
      aws_cost_by_service_daily
    where
      period_start >= date_trunc('month', now())
      and period_end <= now()
      and service in (select unnest (string_to_array($1, ',')::text[]))
      and account_id = $2
    group by
      period_start,
      service
    order by
      period_start
  EOQ
  param "service" {}
  param "account_id" {}
}

query "account_service_ytd_trend" {
  sql = <<-EOQ
    select
      period_start,
      service,
      sum(net_unblended_cost_amount)
    from
      aws_cost_by_service_monthly
    where
      service in (select unnest (string_to_array($1, ',')::text[]))
      and account_id = $2
    group by
      period_start,
      service
    order by
      period_start;
  EOQ
  param "service" {}
  param "account_id" {}
}

query "account_top_5_service_by_mtd" {
  sql = <<-EOQ
    with top_5_services_per_usage as (
      select
        service
      from
        aws_cost_by_service_monthly
      where
        period_start >= date_trunc('month', now())
        and period_end <= now()
      group by service
      order by sum(net_unblended_cost_amount) desc
      limit 5
    )
    select
      m.period_start,
      m.service,
      sum(m.net_unblended_cost_amount)
    from
      aws_cost_by_service_daily as m
      join top_5_services_per_usage as t on m.service = t.service
    where
      m.period_start >= date_trunc('month', now())
      and m.period_end <= now()
      and m.account_id = $1
    group by
      m.period_start,
      m.service
  EOQ
}

query "account_service_by_usage_mtd" {
  sql = <<-EOQ
    with services_by_usage as (
      select
        service,
        sum(net_unblended_cost_amount) as current_month_cost
      from
        aws_cost_by_service_monthly
      where
        period_start >= date_trunc('month', now())
        and period_end <= now()
        and account_id = '533793682495'
      group by service
      order by sum(net_unblended_cost_amount) desc
    ), previous_month_cost as (
      select
        service,
        sum(net_unblended_cost_amount) as previous_month_cost
      from
        aws_cost_by_service_monthly
      where
        period_start >= (date_trunc('month', now()) -interval '1 month')
        and period_end <= date_trunc('month', now())
        and service in ( select service from services_by_usage)
        and account_id = '533793682495'
       group by service
       order by sum(net_unblended_cost_amount) desc
    )
    select
      s.service as "Service",
      case when previous_month_cost is null then 0 else (p.previous_month_cost::numeric(10,2)) end as "Previous Month",
      (s.current_month_cost::numeric(10,2)) "Current MTD"
    from
      services_by_usage as s
      left join previous_month_cost as p on p.service = s.service
    order by
      s.service

  EOQ
}