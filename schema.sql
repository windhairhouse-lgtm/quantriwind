-- =====================================================================
-- WIND HAIR HOUSE — Hệ thống vận hành (Supabase)
-- Chạy 1 lần trong Supabase → SQL Editor → New query → dán toàn bộ → Run.
-- TRƯỚC KHI CHẠY: sửa email chủ ở dòng "OWNER_EMAIL" gần cuối file.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------- 1. DOANH NGHIỆP ----------
create table if not exists public.businesses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  address text,
  owner_email text not null,
  open_time time not null default '09:00',
  staff_cutoff time not null default '19:00',   -- dịch vụ phải xong trước giờ này
  timezone text not null default 'Asia/Ho_Chi_Minh',
  created_at timestamptz not null default now()
);

-- ---------- 2. QUYỀN & VAI TRÒ (kiểu KiotViet: vai trò = bộ quyền mẫu) ----------
create table if not exists public.permissions (
  code text primary key,           -- vd 'lich_hen.tao'
  module text not null,            -- nhóm hiển thị
  label text not null,
  sort int not null default 0
);

create table if not exists public.roles (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id),
  name text not null,
  description text,
  login_from time,                 -- giới hạn giờ đăng nhập (null = không giới hạn)
  login_to time,
  created_at timestamptz not null default now(),
  unique (business_id, name)
);

create table if not exists public.role_permissions (
  role_id uuid not null references public.roles(id) on delete cascade,
  perm_code text not null references public.permissions(code),
  primary key (role_id, perm_code)
);

-- ---------- 3. THÀNH VIÊN (tài khoản đăng nhập) ----------
create table if not exists public.members (
  user_id uuid primary key references auth.users(id),
  business_id uuid not null references public.businesses(id),
  role_id uuid references public.roles(id),
  is_owner boolean not null default false,
  full_name text not null default '',
  email text,
  phone text,
  staff_kind text check (staff_kind in ('tho_chinh','tho_phu')),   -- null = không đứng máy
  staff_level int check (staff_level between 1 and 3),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- Lời mời: chủ tạo trước, nhân viên tự đăng ký bằng đúng email này là nhận vai trò
create table if not exists public.invites (
  email text primary key,
  business_id uuid not null references public.businesses(id),
  role_id uuid not null references public.roles(id),
  full_name text not null,
  phone text,
  staff_kind text check (staff_kind in ('tho_chinh','tho_phu')),
  staff_level int check (staff_level between 1 and 3),
  created_by uuid,
  created_at timestamptz not null default now(),
  used_at timestamptz
);

-- ---------- 4. NGHIỆP VỤ SALON ----------
create table if not exists public.services (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id),
  name text not null,
  group_name text,
  price numeric(12,0) not null check (price >= 0),
  duration_min int not null check (duration_min >= 0),
  commission_type text not null default 'truc_tiep' check (commission_type in ('truc_tiep','ho_tro','noi_tep')),
  needs_review boolean not null default false,   -- tự đánh dấu ca khó khi khách đặt online
  agent_note text,
  active boolean not null default true,
  sort int not null default 0
);

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id),
  name text not null,
  phone text not null,
  channel text,
  birthday date,
  hair_note text,
  tier text not null default 'moi' check (tier in ('moi','quen','vip')),
  loyal_to uuid references public.members(user_id),     -- khách ruột của thợ
  visits int not null default 0,
  total_spent numeric(14,0) not null default 0,
  last_visit_at timestamptz,
  created_at timestamptz not null default now(),
  unique (business_id, phone)
);

create table if not exists public.appointments (
  id uuid primary key default gen_random_uuid(),
  code bigint generated always as identity,
  business_id uuid not null references public.businesses(id),
  customer_id uuid not null references public.customers(id),
  service_id uuid not null references public.services(id),
  stylist_id uuid references public.members(user_id),
  assistant_id uuid references public.members(user_id),
  start_at timestamptz not null,
  end_at timestamptz,
  status text not null default 'da_chot'
    check (status in ('cho_duyet','da_chot','da_den','hoan_thanh','huy','khong_den')),
  channel text,
  customer_kind text check (customer_kind in ('tiem','ca_nhan')),
  price numeric(12,0),
  tip numeric(12,0) not null default 0,
  hair_pieces int not null default 0,
  hard_case boolean not null default false,
  hard_reason text,
  cancel_reason text,
  note text,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists appt_start_idx on public.appointments (business_id, start_at);

create table if not exists public.cash_entries (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id),
  entry_date date not null default (now() at time zone 'Asia/Ho_Chi_Minh')::date,
  kind text not null check (kind in ('thu','chi')),
  category text not null,
  amount numeric(14,0) not null check (amount > 0),
  method text not null default 'tien_mat' check (method in ('tien_mat','chuyen_khoan','the')),
  note text,
  appointment_id uuid references public.appointments(id),
  voided boolean not null default false,
  void_reason text,
  created_by uuid,
  created_at timestamptz not null default now()
);

create table if not exists public.commission_rates (
  business_id uuid not null references public.businesses(id),
  staff_kind text not null check (staff_kind in ('tho_chinh','tho_phu')),
  staff_level int not null check (staff_level between 1 and 3),
  rate_tiem numeric(5,4) not null,
  rate_ca_nhan numeric(5,4) not null,
  primary key (business_id, staff_kind, staff_level)
);

create table if not exists public.commissions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id),
  appointment_id uuid not null references public.appointments(id),
  member_id uuid not null references public.members(user_id),
  month text not null,                 -- 'YYYY-MM'
  base numeric(14,0) not null,
  rate numeric(5,4) not null,
  amount numeric(14,0) not null,
  voided boolean not null default false,
  created_at timestamptz not null default now(),
  unique (appointment_id, member_id)
);

create table if not exists public.monthly_targets (
  business_id uuid not null references public.businesses(id),
  member_id uuid not null references public.members(user_id),
  month text not null,
  target numeric(14,0) not null,
  primary key (member_id, month)
);

-- Nhật ký hoạt động: KHÔNG AI sửa hay xoá được, kể cả chủ
create table if not exists public.audit_log (
  id bigint generated always as identity primary key,
  business_id uuid,
  user_id uuid,
  user_name text,
  table_name text not null,
  action text not null,
  row_id text,
  old_data jsonb,
  new_data jsonb,
  at timestamptz not null default now()
);

-- =====================================================================
-- HÀM KIỂM TRA QUYỀN
-- =====================================================================
create or replace function public.me() returns public.members
language sql stable security definer set search_path = public as $$
  select * from public.members where user_id = auth.uid()
$$;

create or replace function public.is_owner(biz uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.members
    where user_id = auth.uid() and business_id = biz and is_owner and active)
$$;

-- Có quyền X không? Chủ luôn có. Nhân viên: tài khoản đang mở + vai trò có quyền + trong khung giờ cho phép
create or replace function public.has_perm(biz uuid, perm text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare m public.members; r public.roles; t time;
begin
  select * into m from public.members where user_id = auth.uid() and business_id = biz;
  if not found or not m.active then return false; end if;
  if m.is_owner then return true; end if;
  select * into r from public.roles where id = m.role_id;
  if not found then return false; end if;
  if r.login_from is not null and r.login_to is not null then
    t := (now() at time zone 'Asia/Ho_Chi_Minh')::time;
    if t < r.login_from or t > r.login_to then return false; end if;
  end if;
  return exists (select 1 from public.role_permissions where role_id = r.id and perm_code = perm);
end $$;

-- Danh sách quyền của tôi (giao diện dùng để ẩn/hiện menu)
create or replace function public.my_permissions() returns table(code text)
language sql stable security definer set search_path = public as $$
  select p.code from public.permissions p
  where public.has_perm((select business_id from public.members where user_id = auth.uid()), p.code)
$$;

-- =====================================================================
-- TỰ ĐỘNG HOÁ
-- =====================================================================

-- (a) Nhật ký mọi thay đổi
create or replace function public.tg_audit() returns trigger
language plpgsql security definer set search_path = public as $$
declare biz uuid; rid text; nm text;
begin
  biz := coalesce((to_jsonb(new)->>'business_id')::uuid, (to_jsonb(old)->>'business_id')::uuid);
  rid := coalesce(to_jsonb(new)->>'id', to_jsonb(old)->>'id', to_jsonb(new)->>'user_id', to_jsonb(old)->>'user_id',
                  to_jsonb(new)->>'email', to_jsonb(old)->>'email', to_jsonb(new)->>'role_id');
  select full_name into nm from public.members where user_id = auth.uid();
  insert into public.audit_log(business_id, user_id, user_name, table_name, action, row_id, old_data, new_data)
  values (biz, auth.uid(), coalesce(nm, 'Hệ thống / khách online'), tg_table_name, tg_op, rid,
          case when tg_op <> 'INSERT' then to_jsonb(old) end,
          case when tg_op <> 'DELETE' then to_jsonb(new) end);
  return coalesce(new, old);
end $$;

-- (b) Lịch hẹn: tự tính giờ kết thúc, giá, loại khách; chặn quá giờ và trùng lịch; kiểm tra quyền theo thao tác
create or replace function public.tg_appt_before() returns trigger
language plpgsql security definer set search_path = public as $$
declare s public.services; b public.businesses; c public.customers; clash int; lt time; ls time;
begin
  select * into s from public.services where id = new.service_id;
  select * into b from public.businesses where id = new.business_id;
  if s.business_id <> new.business_id then raise exception 'Dịch vụ không thuộc doanh nghiệp này'; end if;

  if tg_op = 'INSERT' or new.service_id is distinct from old.service_id or new.start_at is distinct from old.start_at then
    new.end_at := new.start_at + make_interval(mins => s.duration_min);
  end if;
  if new.price is null or (tg_op = 'UPDATE' and new.service_id is distinct from old.service_id) then
    new.price := s.price;
  end if;
  if new.customer_kind is null or (tg_op = 'UPDATE' and new.stylist_id is distinct from old.stylist_id) then
    select * into c from public.customers where id = new.customer_id;
    new.customer_kind := case when c.loyal_to is not null and c.loyal_to = new.stylist_id then 'ca_nhan' else 'tiem' end;
  end if;

  if new.status not in ('huy','khong_den') then
    ls := (new.start_at at time zone b.timezone)::time;
    lt := (new.end_at at time zone b.timezone)::time;
    if ls < b.open_time then raise exception 'Tiệm mở cửa lúc %', to_char(b.open_time,'HH24:MI'); end if;
    if lt > b.staff_cutoff or (new.end_at at time zone b.timezone)::date > (new.start_at at time zone b.timezone)::date then
      raise exception 'Dịch vụ phải xong trước %. Giờ bắt đầu muộn nhất cho dịch vụ này là %',
        to_char(b.staff_cutoff,'HH24:MI'), to_char(b.staff_cutoff - make_interval(mins => s.duration_min),'HH24:MI');
    end if;
    if new.stylist_id is not null then
      select count(*) into clash from public.appointments a
       where a.stylist_id = new.stylist_id and a.id <> new.id
         and a.status not in ('huy','khong_den')
         and a.start_at < new.end_at and a.end_at > new.start_at;
      if clash > 0 then raise exception 'Thợ này đã có lịch trùng giờ'; end if;
    end if;
  end if;

  -- Quyền theo từng thao tác (bỏ qua khi hệ thống/khách online thực hiện qua hàm đặt lịch)
  if auth.uid() is not null and tg_op = 'UPDATE' then
    if new.status = 'huy' and old.status <> 'huy' then
      if not public.has_perm(new.business_id,'lich_hen.huy') then raise exception 'Bạn không có quyền huỷ lịch'; end if;
      if coalesce(trim(new.cancel_reason),'') = '' then raise exception 'Phải ghi lý do huỷ'; end if;
    end if;
    if old.status = 'cho_duyet' and new.status <> 'cho_duyet' and new.status <> 'huy'
       and not public.has_perm(new.business_id,'lich_hen.duyet_ca_kho') then
      raise exception 'Chỉ người có quyền duyệt ca khó mới chốt được lịch này';
    end if;
    if new.price is distinct from old.price and not public.has_perm(new.business_id,'dich_vu.sua_gia') then
      raise exception 'Bạn không có quyền đổi giá';
    end if;
    if not public.has_perm(new.business_id,'lich_hen.sua') and not public.has_perm(new.business_id,'lich_hen.huy') then
      -- thợ chỉ được cập nhật trạng thái (đã đến / hoàn thành), thợ phụ hỗ trợ, tip, số tép nối, ghi chú của lịch mình
      if (new.customer_id, new.service_id, new.stylist_id, new.start_at, new.channel, new.hard_case)
         is distinct from (old.customer_id, old.service_id, old.stylist_id, old.start_at, old.channel, old.hard_case)
         or new.status not in (old.status,'da_den','hoan_thanh') then
        raise exception 'Bạn chỉ được cập nhật trạng thái, thợ phụ, tip và ghi chú của lịch mình';
      end if;
    end if;
    if old.status = 'hoan_thanh' and not public.is_owner(new.business_id) then
      raise exception 'Lịch đã hoàn thành chỉ chủ mới được sửa';
    end if;
  end if;
  new.updated_at := now();
  return new;
end $$;

-- (c) Khi lịch chuyển sang HOÀN THÀNH: tự ghi thu, tự tính hoa hồng, tự cập nhật hồ sơ khách
create or replace function public.add_commission(ap public.appointments, mem uuid) returns void
language plpgsql security definer set search_path = public as $$
declare m public.members; r public.commission_rates; rate numeric;
begin
  if mem is null then return; end if;
  select * into m from public.members where user_id = mem;
  select * into r from public.commission_rates
   where business_id = ap.business_id and staff_kind = m.staff_kind and staff_level = m.staff_level;
  if not found then return; end if;
  rate := case when ap.customer_kind = 'ca_nhan' then r.rate_ca_nhan else r.rate_tiem end;
  insert into public.commissions(business_id, appointment_id, member_id, month, base, rate, amount)
  values (ap.business_id, ap.id, mem, to_char(ap.start_at at time zone 'Asia/Ho_Chi_Minh','YYYY-MM'),
          coalesce(ap.price,0), rate, round(coalesce(ap.price,0) * rate))
  on conflict (appointment_id, member_id) do update set voided = false, rate = excluded.rate, amount = excluded.amount, base = excluded.base;
end $$;
revoke all on function public.add_commission(public.appointments, uuid) from public, anon, authenticated;

create or replace function public.tg_appt_after() returns trigger
language plpgsql security definer set search_path = public as $$
declare s public.services; base numeric;
begin
  if new.status = 'hoan_thanh' and (tg_op = 'INSERT' or old.status <> 'hoan_thanh') then
    select * into s from public.services where id = new.service_id;
    base := coalesce(new.price,0);
    insert into public.cash_entries(business_id, entry_date, kind, category, amount, method, note, appointment_id, created_by)
    select new.business_id, (new.start_at at time zone 'Asia/Ho_Chi_Minh')::date, 'thu', 'Dịch vụ', base, 'tien_mat',
           'Tự ghi từ lịch #' || new.code || ' — ' || s.name, new.id, auth.uid()
    where base > 0;
    perform public.add_commission(new, new.stylist_id);
    perform public.add_commission(new, new.assistant_id);
    update public.customers set visits = visits + 1, total_spent = total_spent + base, last_visit_at = new.start_at,
      tier = case when visits + 1 >= 6 or total_spent + base >= 10000000 then 'vip' when visits + 1 >= 2 then 'quen' else tier end
    where id = new.customer_id;
  elsif tg_op = 'UPDATE' and new.status = 'hoan_thanh' and new.assistant_id is distinct from old.assistant_id then
    -- thêm / đổi thợ phụ sau khi đã hoàn thành
    update public.commissions set voided = true where appointment_id = new.id and member_id = old.assistant_id;
    perform public.add_commission(new, new.assistant_id);
  end if;

  -- Huỷ một lịch đã hoàn thành → vô hiệu thu & hoa hồng đi kèm (không xoá, giữ dấu vết)
  if tg_op = 'UPDATE' and old.status = 'hoan_thanh' and new.status <> 'hoan_thanh' then
    update public.cash_entries set voided = true, void_reason = 'Lịch #' || new.code || ' đổi trạng thái' where appointment_id = new.id;
    update public.commissions set voided = true where appointment_id = new.id;
  end if;
  return new;
end $$;

-- (d) Thu chi: không xoá, chỉ huỷ phiếu có lý do
create or replace function public.tg_cash_before() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' then
    if auth.uid() is not null and not public.is_owner(new.business_id) then
      if new.voided and not old.voided then
        if not public.has_perm(new.business_id,'thu_chi.huy') then raise exception 'Bạn không có quyền huỷ phiếu'; end if;
        if coalesce(trim(new.void_reason),'') = '' then raise exception 'Phải ghi lý do huỷ phiếu'; end if;
        new.amount := old.amount; new.kind := old.kind; new.category := old.category;
      elsif old.voided and not new.voided then
        raise exception 'Chỉ chủ mới khôi phục được phiếu đã huỷ';
      elsif (new.amount, new.kind, new.category, new.entry_date) is distinct from (old.amount, old.kind, old.category, old.entry_date) then
        raise exception 'Phiếu đã lưu không sửa được số tiền. Hãy huỷ và lập phiếu mới';
      end if;
    end if;
  end if;
  return new;
end $$;

-- (e) Thành viên: chống tự nâng quyền, bảo vệ tài khoản chủ
create or replace function public.tg_member_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;
  if new.is_owner is distinct from old.is_owner and not public.is_owner(old.business_id) then
    raise exception 'Chỉ chủ mới cấp quyền chủ'; end if;
  if old.is_owner and not public.is_owner(old.business_id) then
    raise exception 'Không thể sửa tài khoản chủ'; end if;
  if old.user_id = auth.uid() and not old.is_owner
     and (new.role_id is distinct from old.role_id or new.active is distinct from old.active) then
    raise exception 'Không thể tự đổi vai trò hoặc trạng thái của chính mình'; end if;
  if old.is_owner and old.user_id = auth.uid() and new.active = false then
    raise exception 'Chủ không thể tự khoá tài khoản của mình'; end if;
  new.business_id := old.business_id;
  return new;
end $$;

-- (f) Đăng ký tài khoản mới: email chủ → chủ; email có lời mời → nhận đúng vai trò; còn lại → không có quyền gì
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare inv public.invites; b public.businesses;
begin
  select * into b from public.businesses where lower(owner_email) = lower(new.email) limit 1;
  if found then
    insert into public.members(user_id, business_id, is_owner, full_name, email)
    values (new.id, b.id, true, coalesce(new.raw_user_meta_data->>'full_name', 'Chủ tiệm'), new.email)
    on conflict (user_id) do nothing;
    return new;
  end if;
  select * into inv from public.invites where lower(email) = lower(new.email) and used_at is null;
  if found then
    insert into public.members(user_id, business_id, role_id, full_name, email, phone, staff_kind, staff_level)
    values (new.id, inv.business_id, inv.role_id, inv.full_name, new.email, inv.phone, inv.staff_kind, inv.staff_level)
    on conflict (user_id) do nothing;
    update public.invites set used_at = now() where email = inv.email;
  end if;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

drop trigger if exists appt_before on public.appointments;
create trigger appt_before before insert or update on public.appointments
  for each row execute function public.tg_appt_before();
drop trigger if exists appt_after on public.appointments;
create trigger appt_after after insert or update on public.appointments
  for each row execute function public.tg_appt_after();
drop trigger if exists cash_before on public.cash_entries;
create trigger cash_before before update on public.cash_entries
  for each row execute function public.tg_cash_before();
drop trigger if exists member_guard on public.members;
create trigger member_guard before update on public.members
  for each row execute function public.tg_member_guard();

do $$ declare t text; begin
  foreach t in array array['businesses','roles','role_permissions','members','invites','services','customers',
                           'appointments','cash_entries','commission_rates','commissions','monthly_targets'] loop
    execute format('drop trigger if exists audit on public.%I', t);
    execute format('create trigger audit after insert or update or delete on public.%I for each row execute function public.tg_audit()', t);
  end loop;
end $$;

-- =====================================================================
-- ĐẶT LỊCH ONLINE CHO KHÁCH (không cần đăng nhập)
-- =====================================================================
-- Khung giờ còn trống cho 1 dịch vụ trong 1 ngày
create or replace function public.available_slots(p_business uuid, p_service uuid, p_date date)
returns table(slot text, free_stylists int)
language plpgsql stable security definer set search_path = public as $$
declare s public.services; b public.businesses; t timestamptz; stop timestamptz; n int;
begin
  select * into s from public.services where id = p_service and business_id = p_business and active;
  if not found then return; end if;
  select * into b from public.businesses where id = p_business;
  t := (p_date + b.open_time) at time zone b.timezone;
  stop := (p_date + b.staff_cutoff) at time zone b.timezone - make_interval(mins => s.duration_min);
  while t <= stop loop
    if t > now() + interval '30 minutes' then
      select count(*) into n from public.members m
       where m.business_id = p_business and m.active and m.staff_kind = 'tho_chinh'
         and not exists (select 1 from public.appointments a where a.stylist_id = m.user_id
              and a.status not in ('huy','khong_den')
              and a.start_at < t + make_interval(mins => s.duration_min) and a.end_at > t);
      if n > 0 then slot := to_char(t at time zone b.timezone,'HH24:MI'); free_stylists := n; return next; end if;
    end if;
    t := t + interval '30 minutes';
  end loop;
end $$;

-- Khách đặt lịch: tự tạo/nhận ra khách qua SĐT, tự phân thợ rảnh (ưu tiên thợ quen), dịch vụ khó → chờ duyệt
create or replace function public.book_online(p_business uuid, p_service uuid, p_date date, p_time text,
                                              p_name text, p_phone text, p_note text default null)
returns json language plpgsql security definer set search_path = public as $$
declare s public.services; b public.businesses; c public.customers; t timestamptz; st uuid; ap public.appointments; ph text;
begin
  ph := regexp_replace(coalesce(p_phone,''), '\D', '', 'g');
  if ph !~ '^0\d{9}$' then raise exception 'Số điện thoại cần 10 số, bắt đầu bằng 0'; end if;
  if length(trim(coalesce(p_name,''))) < 2 then raise exception 'Vui lòng nhập tên'; end if;
  select * into s from public.services where id = p_service and business_id = p_business and active;
  if not found then raise exception 'Dịch vụ không tồn tại'; end if;
  select * into b from public.businesses where id = p_business;
  t := (p_date + p_time::time) at time zone b.timezone;
  if t < now() + interval '30 minutes' then raise exception 'Vui lòng chọn giờ muộn hơn'; end if;
  if (select count(*) from public.appointments a join public.customers cc on cc.id = a.customer_id
       where cc.phone = ph and a.business_id = p_business and a.status in ('cho_duyet','da_chot') and a.start_at > now()) >= 3 then
    raise exception 'Số điện thoại này đã có 3 lịch sắp tới. Vui lòng gọi tiệm để được hỗ trợ';
  end if;

  insert into public.customers(business_id, name, phone, channel)
  values (p_business, trim(p_name), ph, 'Website')
  on conflict (business_id, phone) do update set name = public.customers.name
  returning * into c;

  -- ưu tiên thợ quen nếu rảnh, sau đó thợ chính ít lịch nhất trong ngày
  select m.user_id into st from public.members m
   where m.business_id = p_business and m.active and m.staff_kind = 'tho_chinh'
     and not exists (select 1 from public.appointments a where a.stylist_id = m.user_id and a.status not in ('huy','khong_den')
                     and a.start_at < t + make_interval(mins => s.duration_min) and a.end_at > t)
   order by (m.user_id = c.loyal_to) desc nulls last,
            (select count(*) from public.appointments a2 where a2.stylist_id = m.user_id
               and (a2.start_at at time zone b.timezone)::date = p_date and a2.status not in ('huy','khong_den'))
   limit 1;
  if st is null then raise exception 'Khung giờ này vừa kín. Vui lòng chọn giờ khác'; end if;

  insert into public.appointments(business_id, customer_id, service_id, stylist_id, start_at, status, channel,
                                  hard_case, hard_reason, note)
  values (p_business, c.id, p_service, st, t,
          case when s.needs_review then 'cho_duyet' else 'da_chot' end, 'Website',
          s.needs_review, case when s.needs_review then 'Dịch vụ cần thợ xem tóc trước (tự đánh dấu)' end, p_note)
  returning * into ap;

  return json_build_object('code', ap.code, 'status', ap.status,
    'start', to_char(ap.start_at at time zone b.timezone,'HH24:MI DD/MM/YYYY'), 'service', s.name, 'price', ap.price);
end $$;

-- Thông tin công khai cho trang đặt lịch
create or replace function public.public_catalog(p_business uuid)
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'business', (select json_build_object('name', name, 'address', address, 'open', to_char(open_time,'HH24:MI'),
                  'cutoff', to_char(staff_cutoff,'HH24:MI')) from public.businesses where id = p_business),
    'services', coalesce((select json_agg(json_build_object('id', id, 'name', name, 'group', group_name, 'price', price,
                  'duration', duration_min) order by sort, name)
                 from public.services where business_id = p_business and active and duration_min > 0), '[]'::json))
$$;

-- Bảng lương tháng (tự tính từ hoa hồng + chỉ tiêu)
create or replace function public.payroll(p_business uuid, p_month text)
returns table(member_id uuid, full_name text, staff_kind text, staff_level int, revenue numeric,
              commission numeric, target numeric, bonus numeric, total numeric)
language sql stable security definer set search_path = public as $$
  select m.user_id, m.full_name, m.staff_kind, m.staff_level,
         coalesce(sum(c.base) filter (where not c.voided),0),
         coalesce(sum(c.amount) filter (where not c.voided),0),
         t.target,
         case when t.target is not null and coalesce(sum(c.base) filter (where not c.voided),0) > t.target
              then round(coalesce(sum(c.base) filter (where not c.voided),0) * 0.01) else 0 end,
         coalesce(sum(c.amount) filter (where not c.voided),0)
           + case when t.target is not null and coalesce(sum(c.base) filter (where not c.voided),0) > t.target
                  then round(coalesce(sum(c.base) filter (where not c.voided),0) * 0.01) else 0 end
  from public.members m
  left join public.commissions c on c.member_id = m.user_id and c.month = p_month
  left join public.monthly_targets t on t.member_id = m.user_id and t.month = p_month
  where m.business_id = p_business and m.staff_kind is not null
    and (public.has_perm(p_business,'luong.xem_tat_ca') or (m.user_id = auth.uid() and public.has_perm(p_business,'luong.xem_cua_minh')))
  group by m.user_id, m.full_name, m.staff_kind, m.staff_level, t.target
$$;

-- =====================================================================
-- BẢO MẬT HÀNG (RLS) — mọi quyền được kiểm tra ở máy chủ, không chỉ ẩn nút
-- Nguyên tắc: KHÔNG CÓ quyền xoá cho nhân viên. Chỉ chủ xoá được (và vẫn bị ghi nhật ký).
-- =====================================================================
alter table public.businesses enable row level security;
alter table public.permissions enable row level security;
alter table public.roles enable row level security;
alter table public.role_permissions enable row level security;
alter table public.members enable row level security;
alter table public.invites enable row level security;
alter table public.services enable row level security;
alter table public.customers enable row level security;
alter table public.appointments enable row level security;
alter table public.cash_entries enable row level security;
alter table public.commission_rates enable row level security;
alter table public.commissions enable row level security;
alter table public.monthly_targets enable row level security;
alter table public.audit_log enable row level security;

do $$ declare r record; begin
  for r in select policyname, tablename from pg_policies where schemaname = 'public' loop
    execute format('drop policy %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

-- doanh nghiệp
create policy biz_sel on public.businesses for select using (exists (select 1 from public.members where user_id = auth.uid() and business_id = id));
create policy biz_upd on public.businesses for update using (public.is_owner(id));
-- danh mục quyền
create policy perm_sel on public.permissions for select using (auth.uid() is not null);
-- vai trò
create policy role_sel on public.roles for select using (public.has_perm(business_id,'nhan_su.xem') or id = (select role_id from public.members where user_id = auth.uid()));
create policy role_ins on public.roles for insert with check (public.is_owner(business_id));
create policy role_upd on public.roles for update using (public.is_owner(business_id));
create policy role_del on public.roles for delete using (public.is_owner(business_id) and not exists (select 1 from public.members m where m.role_id = id));
create policy rp_sel on public.role_permissions for select using (exists (select 1 from public.roles r where r.id = role_id and (public.has_perm(r.business_id,'nhan_su.xem') or r.id = (select role_id from public.members where user_id = auth.uid()))));
create policy rp_ins on public.role_permissions for insert with check (exists (select 1 from public.roles r where r.id = role_id and public.is_owner(r.business_id)));
create policy rp_del on public.role_permissions for delete using (exists (select 1 from public.roles r where r.id = role_id and public.is_owner(r.business_id)));
-- thành viên
create policy mem_sel on public.members for select using (user_id = auth.uid() or public.has_perm(business_id,'nhan_su.xem')
  or public.has_perm(business_id,'lich_hen.tao') or public.has_perm(business_id,'lich_hen.cap_nhat_cua_minh'));
create policy mem_upd on public.members for update using (public.has_perm(business_id,'nhan_su.quan_ly') or user_id = auth.uid());
-- lời mời
create policy inv_sel on public.invites for select using (public.has_perm(business_id,'nhan_su.quan_ly'));
create policy inv_ins on public.invites for insert with check (public.has_perm(business_id,'nhan_su.quan_ly'));
create policy inv_upd on public.invites for update using (public.has_perm(business_id,'nhan_su.quan_ly'));
create policy inv_del on public.invites for delete using (public.has_perm(business_id,'nhan_su.quan_ly') and used_at is null);
-- dịch vụ
create policy svc_sel on public.services for select using (public.has_perm(business_id,'dich_vu.xem') or public.has_perm(business_id,'lich_hen.tao') or public.has_perm(business_id,'lich_hen.xem_cua_minh'));
create policy svc_ins on public.services for insert with check (public.has_perm(business_id,'dich_vu.sua_gia'));
create policy svc_upd on public.services for update using (public.has_perm(business_id,'dich_vu.sua_gia'));
create policy svc_del on public.services for delete using (public.is_owner(business_id));
-- khách hàng
create policy cus_sel on public.customers for select using (public.has_perm(business_id,'khach_hang.xem') or public.has_perm(business_id,'lich_hen.xem_tat_ca')
  or exists (select 1 from public.appointments a where a.customer_id = id and (a.stylist_id = auth.uid() or a.assistant_id = auth.uid())));
create policy cus_ins on public.customers for insert with check (public.has_perm(business_id,'khach_hang.tao') or public.has_perm(business_id,'lich_hen.tao'));
create policy cus_upd on public.customers for update using (public.has_perm(business_id,'khach_hang.sua'));
create policy cus_del on public.customers for delete using (public.is_owner(business_id));
-- lịch hẹn
create policy apt_sel on public.appointments for select using (public.has_perm(business_id,'lich_hen.xem_tat_ca')
  or (public.has_perm(business_id,'lich_hen.xem_cua_minh') and (stylist_id = auth.uid() or assistant_id = auth.uid())));
create policy apt_ins on public.appointments for insert with check (public.has_perm(business_id,'lich_hen.tao'));
create policy apt_upd on public.appointments for update using (public.has_perm(business_id,'lich_hen.sua') or public.has_perm(business_id,'lich_hen.huy')
  or (public.has_perm(business_id,'lich_hen.cap_nhat_cua_minh') and (stylist_id = auth.uid() or assistant_id = auth.uid())));
create policy apt_del on public.appointments for delete using (public.is_owner(business_id));
-- thu chi
create policy cash_sel on public.cash_entries for select using (public.has_perm(business_id,'thu_chi.xem'));
create policy cash_ins on public.cash_entries for insert with check (public.has_perm(business_id,'thu_chi.tao'));
create policy cash_upd on public.cash_entries for update using (public.has_perm(business_id,'thu_chi.huy') or public.is_owner(business_id));
create policy cash_del on public.cash_entries for delete using (public.is_owner(business_id));
-- tỷ lệ hoa hồng, chỉ tiêu
create policy rate_sel on public.commission_rates for select using (public.has_perm(business_id,'luong.xem_tat_ca') or public.has_perm(business_id,'luong.xem_cua_minh'));
create policy rate_all on public.commission_rates for all using (public.is_owner(business_id)) with check (public.is_owner(business_id));
create policy com_sel on public.commissions for select using (public.has_perm(business_id,'luong.xem_tat_ca') or (member_id = auth.uid() and public.has_perm(business_id,'luong.xem_cua_minh')));
create policy tgt_sel on public.monthly_targets for select using (public.has_perm(business_id,'luong.xem_tat_ca') or (member_id = auth.uid() and public.has_perm(business_id,'luong.xem_cua_minh')));
create policy tgt_all on public.monthly_targets for all using (public.has_perm(business_id,'luong.quan_ly')) with check (public.has_perm(business_id,'luong.quan_ly'));
-- nhật ký: chỉ xem, không ai sửa/xoá
create policy log_sel on public.audit_log for select using (public.has_perm(business_id,'nhat_ky.xem'));

-- Quyền gọi hàm
revoke all on function public.book_online(uuid,uuid,date,text,text,text,text) from public;
grant execute on function public.book_online(uuid,uuid,date,text,text,text,text) to anon, authenticated;
grant execute on function public.available_slots(uuid,uuid,date) to anon, authenticated;
grant execute on function public.public_catalog(uuid) to anon, authenticated;
grant execute on function public.my_permissions() to authenticated;
grant execute on function public.payroll(uuid,text) to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
revoke insert, update, delete on public.audit_log from authenticated;
revoke update, delete on public.commissions from authenticated;

-- =====================================================================
-- DỮ LIỆU KHỞI TẠO
-- =====================================================================
insert into public.permissions(code, module, label, sort) values
 ('lich_hen.xem_tat_ca','Lịch hẹn','Xem lịch của cả tiệm',10),
 ('lich_hen.xem_cua_minh','Lịch hẹn','Xem lịch của mình',11),
 ('lich_hen.tao','Lịch hẹn','Tạo lịch hẹn',12),
 ('lich_hen.sua','Lịch hẹn','Sửa lịch, check-in, hoàn thành',13),
 ('lich_hen.cap_nhat_cua_minh','Lịch hẹn','Cập nhật lịch của mình (bắt đầu, xong)',14),
 ('lich_hen.huy','Lịch hẹn','Huỷ lịch (bắt buộc ghi lý do)',15),
 ('lich_hen.duyet_ca_kho','Lịch hẹn','Duyệt ca khó',16),
 ('khach_hang.xem','Khách hàng','Xem danh sách khách',20),
 ('khach_hang.tao','Khách hàng','Thêm khách',21),
 ('khach_hang.sua','Khách hàng','Sửa hồ sơ khách',22),
 ('dich_vu.xem','Dịch vụ','Xem bảng giá',30),
 ('dich_vu.sua_gia','Dịch vụ','Thêm dịch vụ, sửa giá',31),
 ('thu_chi.xem','Thu chi','Xem sổ thu chi',40),
 ('thu_chi.tao','Thu chi','Lập phiếu thu/chi',41),
 ('thu_chi.huy','Thu chi','Huỷ phiếu (bắt buộc ghi lý do)',42),
 ('luong.xem_cua_minh','Lương','Xem lương, hoa hồng của mình',50),
 ('luong.xem_tat_ca','Lương','Xem lương cả tiệm',51),
 ('luong.quan_ly','Lương','Đặt chỉ tiêu tháng',52),
 ('bao_cao.xem','Báo cáo','Xem báo cáo doanh thu, lợi nhuận',60),
 ('nhan_su.xem','Nhân sự','Xem danh sách nhân sự',70),
 ('nhan_su.quan_ly','Nhân sự','Cấp tài khoản, đổi vai trò, khoá tài khoản',71),
 ('nhat_ky.xem','Hệ thống','Xem nhật ký hoạt động',80)
on conflict (code) do update set label = excluded.label, module = excluded.module, sort = excluded.sort;

do $$
declare biz uuid; r_ql uuid; r_lt uuid; r_tc uuid; r_tp uuid;
begin
  select id into biz from public.businesses where name = 'Wind Hair House' limit 1;
  if biz is null then
    insert into public.businesses(name, address, owner_email)
    values ('Wind Hair House', 'Toà S8.03 Vinhomes Grand Park, TP Thủ Đức',
            'OWNER_EMAIL@gmail.com')    -- <<< SỬA THÀNH EMAIL CỦA DUY
    returning id into biz;

    insert into public.roles(business_id, name, description) values (biz,'Quản lý','Toàn quyền vận hành, trừ phân quyền và xoá dữ liệu') returning id into r_ql;
    insert into public.roles(business_id, name, description, login_from, login_to) values (biz,'Lễ tân / thu ngân','Đặt lịch, check-in, thu tiền. Không xem lợi nhuận, không huỷ phiếu','08:30','20:30') returning id into r_lt;
    insert into public.roles(business_id, name, description, login_from, login_to) values (biz,'Thợ chính','Xem và cập nhật lịch của mình, xem hoa hồng của mình','08:30','20:30') returning id into r_tc;
    insert into public.roles(business_id, name, description, login_from, login_to) values (biz,'Thợ phụ','Xem lịch của mình, xem hoa hồng của mình','08:30','20:30') returning id into r_tp;

    insert into public.role_permissions select r_ql, code from public.permissions where code not in ('nhan_su.quan_ly');
    insert into public.role_permissions(role_id, perm_code) values
      (r_lt,'lich_hen.xem_tat_ca'),(r_lt,'lich_hen.tao'),(r_lt,'lich_hen.sua'),(r_lt,'khach_hang.xem'),(r_lt,'khach_hang.tao'),
      (r_lt,'khach_hang.sua'),(r_lt,'dich_vu.xem'),(r_lt,'thu_chi.tao'),
      (r_tc,'lich_hen.xem_cua_minh'),(r_tc,'lich_hen.cap_nhat_cua_minh'),(r_tc,'dich_vu.xem'),(r_tc,'luong.xem_cua_minh'),
      (r_tp,'lich_hen.xem_cua_minh'),(r_tp,'dich_vu.xem'),(r_tp,'luong.xem_cua_minh');

    -- Tỷ lệ hoa hồng theo cơ chế lương (bậc 3: chủ bổ sung trong trang Lương)
    insert into public.commission_rates values
      (biz,'tho_chinh',1,0.18,0.20),(biz,'tho_chinh',2,0.20,0.22),
      (biz,'tho_phu',1,0.03,0.05),(biz,'tho_phu',2,0.05,0.07);

    insert into public.services(business_id, name, group_name, price, duration_min, commission_type, needs_review, sort) values
      (biz,'Cắt + gội + tạo kiểu','Dịch vụ chính',150000,60,'truc_tiep',false,1),
      (biz,'Gội','Dịch vụ chính',60000,30,'ho_tro',false,2),
      (biz,'Uốn','Dịch vụ chính',600000,150,'truc_tiep',false,3),
      (biz,'Duỗi','Dịch vụ chính',600000,150,'truc_tiep',false,4),
      (biz,'Nhuộm','Dịch vụ chính',600000,120,'truc_tiep',false,5),
      (biz,'Tẩy','Dịch vụ chính',600000,120,'truc_tiep',true,6),
      (biz,'Balayage','Dịch vụ chính',2500000,240,'truc_tiep',true,7),
      (biz,'Nâng sáng','Tẩy tóc',300000,90,'truc_tiep',false,10),
      (biz,'Bóc đen / đỏ','Tẩy tóc',500000,120,'truc_tiep',true,11),
      (biz,'Tẩy nối','Tẩy tóc',600000,120,'truc_tiep',true,12),
      (biz,'Babylight','Tẩy tóc',800000,180,'truc_tiep',false,13),
      (biz,'Highlight','Tẩy tóc',900000,180,'truc_tiep',false,14),
      (biz,'Uốn / duỗi phồng chân','Dịch vụ lẻ',300000,90,'truc_tiep',false,20),
      (biz,'Chấm chân tóc','Dịch vụ lẻ',300000,60,'truc_tiep',false,21),
      (biz,'Phục hồi Mielle Almighty Cocktail','Phục hồi',600000,60,'truc_tiep',false,30),
      (biz,'Phục hồi 3 bước Milbon Deesse''s','Phục hồi',900000,75,'truc_tiep',false,31),
      (biz,'Phục hồi 3C Labios Collagen','Phục hồi',1200000,90,'truc_tiep',false,32),
      (biz,'Combo cắt + uốn + nhuộm + Mielle','Combo',1500000,240,'truc_tiep',false,40),
      (biz,'Combo cắt + uốn + nhuộm + Milbon','Combo',1800000,255,'truc_tiep',false,41),
      (biz,'Tẩy + nhuộm màu sáng','Màu sáng',2100000,240,'truc_tiep',true,50),
      (biz,'Tẩy + nhuộm màu sáng + Milbon','Màu sáng',2600000,270,'truc_tiep',true,51),
      (biz,'Nối tóc lông vũ (theo tép, bao công liên hệ)','Nối tóc',0,0,'noi_tep',true,60);
  end if;
end $$;

-- =====================================================================
-- PHẦN MỞ RỘNG v2: CÔNG VIỆC NỘI BỘ · KHO · BÁO CÁO · BÁO CÁO ZALO
-- (chạy lại toàn bộ file là đủ, không mất dữ liệu cũ)
-- =====================================================================

-- Định dạng tiền kiểu Việt Nam: 1.250.000đ
create or replace function public.fmt_vnd(n numeric) returns text language sql immutable as $$
  select replace(to_char(round(coalesce(n,0)),'FM999G999G999G990'),',','.') || 'đ'
$$;
create or replace function public.fmt_qty(n numeric) returns text language sql immutable as $$
  select case when n = trunc(n) then trunc(n)::text else rtrim(rtrim(n::text,'0'),'.') end
$$;

-- ---------- CÔNG VIỆC NỘI BỘ ----------
create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  code bigint generated always as identity,
  business_id uuid not null references public.businesses(id),
  title text not null,
  description text,
  assignee_id uuid references public.members(user_id),
  created_by uuid,
  due_at timestamptz,
  priority text not null default 'tb' check (priority in ('thap','tb','cao')),
  status text not null default 'chua_lam' check (status in ('chua_lam','dang_lam','cho_duyet','hoan_thanh','huy')),
  report text,
  cancel_reason text,
  done_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.tg_task_before() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and tg_op = 'UPDATE' and not public.has_perm(new.business_id,'cong_viec.giao') then
    -- người được giao: chỉ chuyển Chưa làm → Đang làm → Chờ duyệt và ghi kết quả
    if (new.title, new.description, new.assignee_id, new.due_at, new.priority) is distinct from
       (old.title, old.description, old.assignee_id, old.due_at, old.priority)
       or new.status not in (old.status,'dang_lam','cho_duyet') then
      raise exception 'Bạn chỉ được cập nhật tiến độ và kết quả công việc của mình';
    end if;
  end if;
  if new.status = 'huy' and (tg_op = 'INSERT' or old.status <> 'huy') and coalesce(trim(new.cancel_reason),'') = '' then
    raise exception 'Phải ghi lý do huỷ công việc';
  end if;
  if new.status = 'hoan_thanh' and (tg_op = 'INSERT' or old.status <> 'hoan_thanh') then new.done_at := now(); end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists task_before on public.tasks;
create trigger task_before before insert or update on public.tasks for each row execute function public.tg_task_before();

-- ---------- KHO THUỐC / HOÁ CHẤT / SẢN PHẨM ----------
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id),
  name text not null,
  unit text not null default 'chai',
  stock numeric(12,2) not null default 0,
  min_stock numeric(12,2) not null default 0,
  cost numeric(12,0) not null default 0,
  sell_price numeric(12,0),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.stock_moves (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id),
  product_id uuid not null references public.products(id),
  kind text not null check (kind in ('nhap','xuat_dung','ban','kiem_ke')),
  qty numeric(12,2) not null,          -- nhập/xuất/bán: số dương; kiểm kê: số tồn thực tế đếm được
  unit_cost numeric(12,0),
  note text,
  created_by uuid,
  created_at timestamptz not null default now()
);

-- Tự cập nhật tồn kho; nhập có giá → tự ghi phiếu chi; bán lẻ → tự ghi phiếu thu
create or replace function public.tg_stock_move() returns trigger
language plpgsql security definer set search_path = public as $$
declare p public.products; delta numeric;
begin
  select * into p from public.products where id = new.product_id for update;
  if p.business_id <> new.business_id then raise exception 'Sản phẩm không thuộc doanh nghiệp này'; end if;
  if new.kind <> 'kiem_ke' and new.qty <= 0 then raise exception 'Số lượng phải lớn hơn 0'; end if;
  if new.kind = 'kiem_ke' and new.qty < 0 then raise exception 'Số tồn kiểm kê không được âm'; end if;
  delta := case new.kind when 'nhap' then new.qty when 'kiem_ke' then new.qty - p.stock else -new.qty end;
  if p.stock + delta < 0 then raise exception 'Tồn kho không đủ (còn % %)', public.fmt_qty(p.stock), p.unit; end if;
  perform set_config('app.stock_move','1',true);
  update public.products set stock = stock + delta,
         cost = case when new.kind = 'nhap' and coalesce(new.unit_cost,0) > 0 then new.unit_cost else cost end
   where id = p.id;
  perform set_config('app.stock_move','',true);
  if new.kind = 'nhap' and coalesce(new.unit_cost,0) > 0 then
    insert into public.cash_entries(business_id, kind, category, amount, method, note, created_by)
    values (new.business_id, 'chi', 'Thuốc / hoá chất', round(new.qty * new.unit_cost), 'tien_mat',
            'Tự ghi: nhập ' || public.fmt_qty(new.qty) || ' ' || p.unit || ' ' || p.name, auth.uid());
  elsif new.kind = 'ban' and coalesce(p.sell_price,0) > 0 then
    insert into public.cash_entries(business_id, kind, category, amount, method, note, created_by)
    values (new.business_id, 'thu', 'Bán sản phẩm', round(new.qty * p.sell_price), 'tien_mat',
            'Tự ghi: bán ' || public.fmt_qty(new.qty) || ' ' || p.unit || ' ' || p.name, auth.uid());
  end if;
  return new;
end $$;
drop trigger if exists stock_move_after on public.stock_moves;
create trigger stock_move_after after insert on public.stock_moves for each row execute function public.tg_stock_move();

-- Không ai sửa tay số tồn: chỉ đổi qua phiếu nhập / xuất / bán / kiểm kê (có nhật ký)
create or replace function public.tg_product_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null and new.stock <> 0 then new.stock := 0; end if;   -- tồn đầu kỳ phải nhập bằng phiếu
    return new;
  end if;
  if new.stock is distinct from old.stock and coalesce(current_setting('app.stock_move', true),'') <> '1' then
    raise exception 'Không sửa trực tiếp tồn kho. Hãy dùng phiếu kiểm kê';
  end if;
  return new;
end $$;
drop trigger if exists product_guard on public.products;
create trigger product_guard before insert or update on public.products for each row execute function public.tg_product_guard();

-- ---------- BÁO CÁO ----------
create or replace function public.report_summary(p_business uuid, p_from date, p_to date)
returns json language plpgsql stable security definer set search_path = public as $$
declare tz text := 'Asia/Ho_Chi_Minh'; res json;
begin
  if not public.has_perm(p_business,'bao_cao.xem') then raise exception 'Bạn không có quyền xem báo cáo'; end if;
  with a as (
    select ap.*, (ap.start_at at time zone tz)::date d from public.appointments ap
    where ap.business_id = p_business and (ap.start_at at time zone tz)::date between p_from and p_to),
  done as (select * from a where status = 'hoan_thanh'),
  cash as (select * from public.cash_entries where business_id = p_business and not voided and entry_date between p_from and p_to)
  select json_build_object(
    'revenue', coalesce((select sum(price) from done),0),
    'tips', coalesce((select sum(tip) from done),0),
    'bookings', (select count(*) from a),
    'done', (select count(*) from done),
    'cancelled', (select count(*) from a where status = 'huy'),
    'no_show', (select count(*) from a where status = 'khong_den'),
    'thu', coalesce((select sum(amount) from cash where kind='thu'),0),
    'chi', coalesce((select sum(amount) from cash where kind='chi'),0),
    'commission', coalesce((select sum(c.amount) from public.commissions c join done on done.id = c.appointment_id where not c.voided),0),
    'new_customers', (select count(*) from public.customers where business_id = p_business and (created_at at time zone tz)::date between p_from and p_to),
    'by_day', coalesce((select json_agg(x order by x.d) from (select d, sum(price) revenue, count(*) n from done group by d) x),'[]'),
    'by_stylist', coalesce((select json_agg(x order by x.revenue desc) from (select coalesce(m.full_name,'Chưa phân') as name, sum(done.price) revenue, count(*) n
                   from done left join public.members m on m.user_id = done.stylist_id group by m.full_name) x),'[]'),
    'by_service', coalesce((select json_agg(x order by x.revenue desc) from (select s.name, sum(done.price) revenue, count(*) n
                   from done join public.services s on s.id = done.service_id group by s.name) x),'[]'),
    'by_channel', coalesce((select json_agg(x order by x.n desc) from (select coalesce(channel,'Khác') as name, count(*) n from a group by 1) x),'[]'),
    'by_category', coalesce((select json_agg(x order by x.amount desc) from (select category as name, kind, sum(amount) amount from cash group by category, kind) x),'[]')
  ) into res;
  return res;
end $$;
grant execute on function public.report_summary(uuid,date,date) to authenticated;

-- ---------- BÁO CÁO CUỐI NGÀY CHO ZALO (chỉ n8n gọi được, bằng khoá service_role) ----------
create or replace function public.daily_report(p_business uuid, p_date date default null)
returns json language plpgsql stable security definer set search_path = public as $$
declare tz text := 'Asia/Ho_Chi_Minh'; d date; t text; r record; c record; low text; late text; n int; nm text; first_t text;
begin
  d := coalesce(p_date, (now() at time zone tz)::date);
  select name into nm from public.businesses where id = p_business;
  select count(*) filter (where status not in ('huy','khong_den')) total,
         count(*) filter (where status = 'hoan_thanh') done,
         count(*) filter (where status = 'huy') cancel,
         count(*) filter (where status = 'khong_den') noshow,
         coalesce(sum(price) filter (where status = 'hoan_thanh'),0) rev,
         coalesce(sum(tip) filter (where status = 'hoan_thanh'),0) tip
    into r from public.appointments where business_id = p_business and (start_at at time zone tz)::date = d;
  select coalesce(sum(amount) filter (where kind='thu'),0) thu, coalesce(sum(amount) filter (where kind='chi'),0) chi
    into c from public.cash_entries where business_id = p_business and not voided and entry_date = d;
  t := '💈 ' || upper(nm) || ' — BÁO CÁO ' || to_char(d,'DD/MM/YYYY') || E'\n\n'
    || '📅 Lịch: ' || r.total || ' | Hoàn thành ' || r.done || ' | Huỷ ' || r.cancel || ' | Không đến ' || r.noshow || E'\n'
    || '💰 Doanh thu dịch vụ: ' || public.fmt_vnd(r.rev) || '' || E'\n'
    || '🎁 Tip của thợ: ' || public.fmt_vnd(r.tip) || '' || E'\n'
    || '➕ Tổng thu: ' || public.fmt_vnd(c.thu) || ' | ➖ Chi: ' || public.fmt_vnd(c.chi) || '' || E'\n'
    || '📊 Chênh lệch: ' || public.fmt_vnd(c.thu - c.chi) || ' (mỗi thành viên 1/3: ' || public.fmt_vnd(round((c.thu - c.chi)/3)) || ')' || E'\n\n';
  select count(*) into n from public.appointments where business_id = p_business and status = 'cho_duyet' and start_at > now();
  if n > 0 then t := t || '🚩 Ca khó đang chờ duyệt: ' || n || E'\n'; end if;
  select string_agg(name || ' (còn ' || public.fmt_qty(stock) || ' ' || unit || ')', ', ') into low
    from public.products where business_id = p_business and active and min_stock > 0 and stock <= min_stock;
  if low is not null then t := t || '📦 Sắp hết hàng: ' || low || E'\n'; end if;
  select string_agg(title, ', ') into late from public.tasks
   where business_id = p_business and status in ('chua_lam','dang_lam') and due_at < now();
  if late is not null then t := t || '⏰ Việc quá hạn: ' || late || E'\n'; end if;
  select count(*), to_char(min(start_at) at time zone tz,'HH24:MI') into n, first_t from public.appointments
   where business_id = p_business and (start_at at time zone tz)::date = d + 1 and status in ('da_chot','cho_duyet');
  t := t || '🗓 Ngày mai: ' || n || ' lịch' || coalesce(', khách đầu tiên ' || first_t, '') || '.';
  return json_build_object('text', t);
end $$;
revoke all on function public.daily_report(uuid,date) from public, anon, authenticated;
do $$ begin if exists (select 1 from pg_roles where rolname = 'service_role') then
  grant execute on function public.daily_report(uuid,date) to service_role; end if; end $$;

-- ---------- RLS cho bảng mới ----------
alter table public.tasks enable row level security;
alter table public.products enable row level security;
alter table public.stock_moves enable row level security;
create policy task_sel on public.tasks for select using (public.has_perm(business_id,'cong_viec.xem_tat_ca')
  or (public.has_perm(business_id,'cong_viec.cap_nhat_cua_minh') and (assignee_id = auth.uid() or created_by = auth.uid())));
create policy task_ins on public.tasks for insert with check (public.has_perm(business_id,'cong_viec.giao'));
create policy task_upd on public.tasks for update using (public.has_perm(business_id,'cong_viec.giao')
  or (public.has_perm(business_id,'cong_viec.cap_nhat_cua_minh') and assignee_id = auth.uid()));
create policy task_del on public.tasks for delete using (public.is_owner(business_id));
create policy prod_sel on public.products for select using (public.has_perm(business_id,'kho.xem'));
create policy prod_ins on public.products for insert with check (public.has_perm(business_id,'kho.quan_ly'));
create policy prod_upd on public.products for update using (public.has_perm(business_id,'kho.quan_ly'));
create policy prod_del on public.products for delete using (public.is_owner(business_id));
create policy mv_sel on public.stock_moves for select using (public.has_perm(business_id,'kho.xem'));
create policy mv_ins on public.stock_moves for insert with check (
  public.has_perm(business_id,'kho.quan_ly')
  or (kind in ('xuat_dung','ban') and public.has_perm(business_id,'kho.xuat_dung')));
grant select, insert, update, delete on public.tasks, public.products to authenticated;
grant select, insert on public.stock_moves to authenticated;
revoke update, delete on public.stock_moves from authenticated;

do $$ declare t text; begin
  foreach t in array array['tasks','products','stock_moves'] loop
    execute format('drop trigger if exists audit on public.%I', t);
    execute format('create trigger audit after insert or update or delete on public.%I for each row execute function public.tg_audit()', t);
  end loop;
end $$;

-- ---------- Quyền mới + tự gán cho vai trò mặc định ----------
insert into public.permissions(code, module, label, sort) values
 ('khach_hang.cham_soc','Khách hàng','Xem danh sách chăm sóc (nhắc quay lại, sinh nhật)',23),
 ('cong_viec.xem_tat_ca','Công việc','Xem công việc của cả tiệm',90),
 ('cong_viec.giao','Công việc','Giao việc, sửa, duyệt, huỷ công việc',91),
 ('cong_viec.cap_nhat_cua_minh','Công việc','Nhận và báo cáo việc được giao cho mình',92),
 ('kho.xem','Kho','Xem tồn kho',100),
 ('kho.xuat_dung','Kho','Xuất dùng khi làm dịch vụ, bán lẻ sản phẩm',101),
 ('kho.quan_ly','Kho','Thêm sản phẩm, nhập hàng, kiểm kê',102)
on conflict (code) do update set label = excluded.label, module = excluded.module, sort = excluded.sort;

insert into public.role_permissions(role_id, perm_code)
select r.id, p.code from public.roles r cross join public.permissions p
where (r.name = 'Quản lý' and p.code in ('khach_hang.cham_soc','cong_viec.xem_tat_ca','cong_viec.giao','cong_viec.cap_nhat_cua_minh','kho.xem','kho.xuat_dung','kho.quan_ly'))
   or (r.name = 'Lễ tân / thu ngân' and p.code in ('khach_hang.cham_soc','cong_viec.cap_nhat_cua_minh','kho.xem','kho.xuat_dung'))
   or (r.name in ('Thợ chính','Thợ phụ') and p.code in ('cong_viec.cap_nhat_cua_minh','kho.xem','kho.xuat_dung'))
on conflict do nothing;

-- Lấy mã doanh nghiệp để dán vào index.html:
select id as business_id, name from public.businesses;
