-- PostgreSQL port of the AMI Capstone schema
-- Requires pgcrypto for gen_random_uuid()
create extension if not exists pgcrypto;

create schema if not exists ami;
set search_path to ami;

-- Org & Master data
create table org_unit (
  org_unit_id   int generated always as identity primary key,
  type          varchar(20) not null check (type in ('Zone','Substation','Feeder','DTR')),
  name          varchar(100) not null,
  parent_id     int references org_unit(org_unit_id)
);

create table tariff (
  tariff_id     int generated always as identity primary key,
  name          varchar(100) not null,
  effective_from date not null,
  effective_to   date,
  base_rate     numeric(18,4) not null,
  tax_rate      numeric(18,4) not null default 0
);

create table tod_rule (
  tod_rule_id   int generated always as identity primary key,
  tariff_id     int not null references tariff(tariff_id),
  name          varchar(50) not null,
  start_time    time(0) not null,
  end_time      time(0) not null,
  rate_per_kwh  numeric(18,6) not null
);

create table tariff_slab (
  tariff_slab_id int generated always as identity primary key,
  tariff_id      int not null references tariff(tariff_id),
  from_kwh       numeric(18,6) not null,
  to_kwh         numeric(18,6) not null,
  rate_per_kwh   numeric(18,6) not null,
  constraint ck_tariff_slab_range check (from_kwh >= 0 and to_kwh > from_kwh)
);

create table consumer (
  consumer_id   bigint generated always as identity primary key,
  name          varchar(200) not null,
  address       varchar(500),
  phone         varchar(30),
  email         varchar(200),
  org_unit_id   int not null references org_unit(org_unit_id),
  tariff_id     int not null references tariff(tariff_id),
  status        varchar(20) not null default 'Active' check (status in ('Active','Inactive')),
  created_at    timestamptz(3) not null default now(),
  created_by    varchar(100) not null default 'system',
  updated_at    timestamptz(3),
  updated_by    varchar(100)
);

create table meter (
  meter_serial_no varchar(50) primary key,
  ip_address      varchar(45) not null,
  iccid           varchar(30) not null,
  imsi            varchar(30) not null,
  manufacturer    varchar(100) not null,
  firmware        varchar(50),
  category        varchar(50) not null,
  install_ts_utc  timestamptz(3) not null,
  status          varchar(20) not null default 'Active' check (status in ('Active','Inactive','Decommissioned')),
  consumer_id     bigint references consumer(consumer_id)
);

-- Profiles (time series)
create table daily_profile (
  daily_profile_id bigint generated always as identity primary key,
  meter_serial_no  varchar(50) not null references meter(meter_serial_no),
  date             date not null,
  kwh              numeric(18,6) not null,
  source           varchar(20) not null default 'Import' check (source in ('Import','Estimate','Edit')),
  vee_status       varchar(20) not null default 'Clean' check (vee_status in ('Clean','Estimated','Edited','Flagged')),
  estimation_flags varchar(200),
  constraint uq_daily_profile unique (meter_serial_no, date)
);

create table load_survey_interval (
  ls_id          bigint generated always as identity primary key,
  meter_serial_no varchar(50) not null references meter(meter_serial_no),
  ts_utc         timestamptz(0) not null,
  interval_index int not null check (interval_index between 0 and 95),
  reading        numeric(18,6) not null,
  vee_status     varchar(20) not null default 'Clean' check (vee_status in ('Clean','Estimated','Edited','Flagged')),
  constraint uq_load_survey unique (meter_serial_no, ts_utc)
);

create index ix_load_survey_meter_ts on load_survey_interval(meter_serial_no, ts_utc);

-- Import Staging
create table import_batch (
  batch_id     uuid not null default gen_random_uuid() primary key,
  type         varchar(20) not null check (type in ('Meter','Consumer','LS','DP','Commands')),
  file_name    varchar(260) not null,
  row_count    int not null,
  valid_count  int not null default 0,
  invalid_count int not null default 0,
  created_by   varchar(100) not null,
  created_at   timestamptz(3) not null default now(),
  status       varchar(20) not null default 'New' check (status in ('New','Validated','Approved','Rejected'))
);

create table import_staging (
  staging_id   bigint generated always as identity primary key,
  batch_id     uuid not null references import_batch(batch_id) on delete cascade,
  row_json     jsonb not null,
  row_status   varchar(20) not null check (row_status in ('Valid','Invalid','Duplicate')),
  errors       jsonb
);

-- Commands (table-queue via command_item.state)
create table command_request (
  request_id      uuid not null default gen_random_uuid() primary key,
  type            varchar(20) not null check (type in ('Connect','Disconnect','Ping','RelayStatus')),
  requested_by    varchar(100) not null,
  requested_at_utc timestamptz(3) not null default now(),
  state           varchar(20) not null default 'Draft' check (state in ('Draft','PendingApproval','Approved','Rejected','Dispatched')),
  reason          varchar(300)
);

create table command_item (
  item_id        bigint generated always as identity primary key,
  request_id     uuid not null references command_request(request_id) on delete cascade,
  meter_serial_no varchar(50) not null references meter(meter_serial_no),
  state          varchar(20) not null default 'PendingApproval' check (state in ('PendingApproval','Approved','Rejected','Dispatched','Acked','Failed','Dlq')),
  attempts       int not null default 0,
  last_error     varchar(500),
  idempotency_key varchar(100) not null
);

create index ix_command_item_request on command_item(request_id);
create index ix_command_item_state on command_item(state);

create table command_log (
  log_id        bigint generated always as identity primary key,
  item_id       bigint not null references command_item(item_id) on delete cascade,
  status        varchar(20) not null check (status in ('Dispatched','Acked','Failed','Retried','MovedToDlq')),
  at_ts         timestamptz(3) not null default now(),
  message       varchar(500)
);

create index ix_command_log_item_at on command_log(item_id, at_ts);

-- Billing & Prepaid
create table bill (
  bill_id       bigint generated always as identity primary key,
  consumer_id   bigint not null references consumer(consumer_id),
  period_start  date not null,
  period_end    date not null,
  energy_kwh    numeric(18,6) not null,
  subtotal      numeric(18,2) not null,
  taxes         numeric(18,2) not null,
  total         numeric(18,2) generated always as (subtotal + taxes) stored,
  status        varchar(20) not null default 'Draft' check (status in ('Draft','Approved','Published'))
);
create index ix_bill_consumer_period on bill(consumer_id, period_start, period_end);

create table bill_line (
  bill_line_id  bigint generated always as identity primary key,
  bill_id       bigint not null references bill(bill_id) on delete cascade,
  line_type     varchar(10) not null check (line_type in ('Base','TOD','Slab','Adj')),
  qty_kwh       numeric(18,6) not null default 0,
  rate          numeric(18,6) not null default 0,
  amount        numeric(18,2) not null,
  note          varchar(200)
);
create index ix_bill_line_bill on bill_line(bill_id);

create table prepaid_balance (
  balance_id     bigint generated always as identity primary key,
  consumer_id    bigint not null references consumer(consumer_id),
  meter_serial_no varchar(50) references meter(meter_serial_no),
  balance_amount numeric(18,2) not null default 0,
  threshold_amount numeric(18,2) not null default 0,
  updated_at     timestamptz(3) not null default now()
);

create table recharge_transaction (
  recharge_id    bigint generated always as identity primary key,
  consumer_id    bigint not null references consumer(consumer_id),
  meter_serial_no varchar(50) references meter(meter_serial_no),
  amount         numeric(18,2) not null,
  mode           varchar(20) not null check (mode in ('Cash','UPI','Card','Online')),
  reference      varchar(100),
  at_ts          timestamptz(3) not null default now()
);
create index ix_recharge_consumer_at on recharge_transaction(consumer_id, at_ts);

create table prepaid_ledger (
  ledger_id     bigint generated always as identity primary key,
  consumer_id   bigint not null references consumer(consumer_id),
  meter_serial_no varchar(50) references meter(meter_serial_no),
  ts            timestamptz(3) not null,
  delta_amount  numeric(18,2) not null,
  reason        varchar(20) not null check (reason in ('Consumption','Recharge','Adjustment')),
  balance_after numeric(18,2) not null
);
create index ix_ledger_consumer_ts on prepaid_ledger(consumer_id, ts);

-- Meter Replacement
create table mr_ticket (
  mr_id          bigint generated always as identity primary key,
  old_serial     varchar(50) not null references meter(meter_serial_no),
  new_serial     varchar(50) not null references meter(meter_serial_no),
  requested_by   varchar(100) not null,
  approved_by    varchar(100),
  effective_at_utc timestamptz(3) not null,
  state          varchar(20) not null default 'Draft' check (state in ('Draft','PendingApproval','Approved','Completed','Rejected'))
);

-- Security & Admin
create table app_user (
  user_id       bigint generated always as identity primary key,
  username      varchar(100) not null unique,
  password_hash bytea not null,
  display_name  varchar(150) not null,
  email         varchar(200),
  phone         varchar(30),
  last_login_utc timestamptz(3),
  is_active     boolean not null default true
);

create table role (
  role_id       int generated always as identity primary key,
  name          varchar(100) not null unique
);

create table user_role (
  user_id       bigint not null references app_user(user_id) on delete cascade,
  role_id       int not null references role(role_id) on delete cascade,
  constraint pk_user_role primary key (user_id, role_id)
);

create table permission (
  permission_id int generated always as identity primary key,
  name          varchar(150) not null unique,
  description   varchar(300)
);

create table role_permission (
  role_id        int not null references role(role_id) on delete cascade,
  permission_id  int not null references permission(permission_id) on delete cascade,
  constraint pk_role_permission primary key (role_id, permission_id)
);

create table menu (
  menu_id       int generated always as identity primary key,
  parent_id     int references menu(menu_id),
  name          varchar(100) not null,
  route         varchar(200) not null,
  sort_order    int not null default 0,
  icon          varchar(50),
  permission_id int references permission(permission_id)
);

create table role_menu (
  role_id  int not null references role(role_id) on delete cascade,
  menu_id  int not null references menu(menu_id) on delete cascade,
  constraint pk_role_menu primary key (role_id, menu_id)
);

create table user_org_scope (
  user_id     bigint not null references app_user(user_id) on delete cascade,
  org_unit_id int not null references org_unit(org_unit_id) on delete cascade,
  constraint pk_user_org_scope primary key (user_id, org_unit_id)
);

-- Reporting admin
create table report_template (
  report_template_id int generated always as identity primary key,
  name          varchar(150) not null,
  category      varchar(20) not null check (category in ('Operations','Regulatory','Finance','Prepaid')),
  description   varchar(300),
  sql_view_or_proc varchar(200) not null,
  default_format varchar(10) not null check (default_format in ('CSV','PDF'))
);

create table report_schedule (
  report_schedule_id int generated always as identity primary key,
  report_template_id int not null references report_template(report_template_id) on delete cascade,
  cron           varchar(100) not null,
  timezone       varchar(40) not null default 'Asia/Kolkata',
  enabled        boolean not null default true,
  visibility     varchar(10) not null check (visibility in ('Role','User')),
  target_role_id int references role(role_id),
  target_user_id bigint references app_user(user_id)
);

create table user_report_subscription (
  subscription_id   bigint generated always as identity primary key,
  report_template_id int not null references report_template(report_template_id) on delete cascade,
  user_id           bigint not null references app_user(user_id) on delete cascade,
  channel           varchar(10) not null check (channel in ('Email','InApp')),
  frequency         varchar(10) not null check (frequency in ('Daily','Weekly','Monthly'))
);

create table generated_report (
  generated_report_id bigint generated always as identity primary key,
  report_template_id  int not null references report_template(report_template_id) on delete cascade,
  run_at        timestamptz(3) not null default now(),
  status        varchar(10) not null check (status in ('New','Ready','Failed')),
  storage_uri   varchar(400),
  requested_by  varchar(100)
);

-- Analytics views
create or replace view v_monthly_peak as
select
  meter_serial_no,
  extract(year from date)  as year,
  extract(month from date) as month,
  max(kwh)                 as peak_kwh
from daily_profile
group by meter_serial_no, extract(year from date), extract(month from date);

create or replace view v_daily_kpi as
select
  dp.date,
  dp.meter_serial_no,
  dp.kwh,
  case when ls_cnt.cnt = 96 then 1 else 0 end as is_complete_day
from daily_profile dp
left join lateral (
  select count(*) as cnt
  from load_survey_interval ls
  where ls.meter_serial_no = dp.meter_serial_no
    and date(ls.ts_utc) = dp.date
) ls_cnt on true;
