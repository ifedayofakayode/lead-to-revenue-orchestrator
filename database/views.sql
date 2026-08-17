-- database/views.sql

create view automation_rate as
select
  actor,
  count(*) as quote_count,
  round(100.0 * count(*) / sum(count(*)) over (), 1) as pct_of_quotes
from lead_events
where event_type in ('auto_quoted', 'approved')
group by actor;


create view lead_funnel_summary as
select
  lead_status,
  count(*) as lead_count,
  round(100.0 * count(*) / sum(count(*)) over (), 1) as pct_of_total
from leads
group by lead_status
order by lead_count desc;


create table exception_queue (
  exception_id uuid primary key default gen_random_uuid(),
  lead_id uuid references leads(lead_id),
  exception_type text not null,
  details jsonb,
  status text not null default 'open',
  created_at timestamptz default now(),
  resolved_at timestamptz
);


create view lead_response_times as
select
  l.lead_id,
  l.first_name,
  l.last_name,
  l.created_at as lead_created_at,
  e.created_at as quoted_at,
  e.event_type as quote_path,
  round(extract(epoch from (e.created_at - l.created_at)) / 60, 1) as minutes_to_quote
from leads l
join lead_events e on e.lead_id = l.lead_id
where e.event_type in ('auto_quoted', 'approved')
order by l.created_at desc;