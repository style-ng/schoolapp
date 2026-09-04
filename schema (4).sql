-- ============================================================
-- SCHOOL MANAGEMENT PLATFORM — SUPABASE SCHEMA
-- Multi-tenant: every table is scoped to a school_id so one
-- deployment can serve many schools (each school = one tenant).
-- ============================================================

create extension if not exists "uuid-ossp";

-- ---------- 1. SCHOOLS (tenants) ----------
create table schools (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  slug text unique not null,               -- used in branded subdomain/URL
  logo_url text,
  primary_color text default '#1e8449',
  plan text default 'monthly_5k',          -- billing plan reference
  is_active boolean default true,
  created_at timestamptz default now()
);

-- ---------- 2. USERS / STAFF ROLES ----------
-- Extends Supabase auth.users with role + school scoping
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  school_id uuid references schools(id) on delete cascade,
  full_name text not null,
  role text not null check (role in ('super_admin','school_admin','teacher','accountant','parent')),
  phone text,
  is_active boolean default true,
  created_at timestamptz default now()
);

-- ---------- 3. CLASSES & SUBJECTS ----------
create table classes (
  id uuid primary key default uuid_generate_v4(),
  school_id uuid references schools(id) on delete cascade,
  name text not null,                      -- e.g. JSS1, SS2 Science
  arm text,                                -- e.g. A, B, Gold
  class_teacher_id uuid references profiles(id),
  created_at timestamptz default now()
);

create table subjects (
  id uuid primary key default uuid_generate_v4(),
  school_id uuid references schools(id) on delete cascade,
  name text not null,
  created_at timestamptz default now()
);

-- subject teacher assignment (per class, per subject)
create table class_subject_teachers (
  id uuid primary key default uuid_generate_v4(),
  class_id uuid references classes(id) on delete cascade,
  subject_id uuid references subjects(id) on delete cascade,
  teacher_id uuid references profiles(id),
  unique (class_id, subject_id)
);

-- ---------- 4. STUDENTS ----------
create table students (
  id uuid primary key default uuid_generate_v4(),
  school_id uuid references schools(id) on delete cascade,
  class_id uuid references classes(id),
  admission_number text not null,
  full_name text not null,
  gender text,
  date_of_birth date,
  parent_name text,
  parent_phone text,
  parent_email text,
  photo_url text,
  status text default 'active' check (status in ('active','graduated','withdrawn')),
  created_at timestamptz default now(),
  unique (school_id, admission_number)
);

-- ---------- 5. ADMISSIONS (intake pipeline, before becoming a student) ----------
create table admissions (
  id uuid primary key default uuid_generate_v4(),
  school_id uuid references schools(id) on delete cascade,
  applicant_name text not null,
  desired_class text,
  parent_name text,
  parent_phone text,
  parent_email text,
  status text default 'pending' check (status in ('pending','reviewed','offered','enrolled','rejected')),
  notes text,
  submitted_at timestamptz default now()
);

-- ---------- 6. ATTENDANCE ----------
create table student_attendance (
  id uuid primary key default uuid_generate_v4(),
  school_id uuid references schools(id) on delete cascade,
  student_id uuid references students(id) on delete cascade,
  class_id uuid references classes(id),
  date date not null,
  status text not null check (status in ('present','absent','late','excused')),
  marked_by uuid references profiles(id),
  created_at timestamptz default now(),
  unique (student_id, date)
);

-- teacher check-in / check-out
create table teacher_attendance (
  id uuid primary key default uuid_generate_v4(),
  school_id uuid references schools(id) on delete cascade,
  teacher_id uuid references profiles(id) on delete cascade,
  date date not null,
  check_in timestamptz,
  check_out timestamptz,
  unique (teacher_id, date)
);

-- ---------- 7. FEES & PAYMENTS ----------
create table fee_structures (
  id uuid primary key default uuid_generate_v4(),
  school_id uuid references schools(id) on delete cascade,
  class_id uuid references classes(id),
  term text not null,                      -- e.g. "2026/2027 First Term"
  amount numeric(12,2) not null,
  due_date date,
  created_at timestamptz default now()
);

create table payments (
  id uuid primary key default uuid_generate_v4(),
  school_id uuid references schools(id) on delete cascade,
  student_id uuid references students(id) on delete cascade,
  fee_structure_id uuid references fee_structures(id),
  amount numeric(12,2) not null,
  provider text check (provider in ('remita','palmpay','paystack','cash','bank_transfer')),
  reference text,                          -- RRR / transaction ref
  status text default 'pending' check (status in ('pending','confirmed','failed','duplicate_flagged')),
  paid_at timestamptz default now()
);

-- ---------- 8. REPORT CARDS / CONTINUOUS ASSESSMENT ----------
create table assessment_scores (
  id uuid primary key default uuid_generate_v4(),
  school_id uuid references schools(id) on delete cascade,
  student_id uuid references students(id) on delete cascade,
  subject_id uuid references subjects(id),
  term text not null,
  ca_score numeric(5,2) default 0,          -- continuous assessment
  exam_score numeric(5,2) default 0,
  total_score numeric(5,2) generated always as (ca_score + exam_score) stored,
  grade text,
  teacher_comment text,
  entered_by uuid references profiles(id),
  created_at timestamptz default now(),
  unique (student_id, subject_id, term)
);

create table report_cards (
  id uuid primary key default uuid_generate_v4(),
  school_id uuid references schools(id) on delete cascade,
  student_id uuid references students(id) on delete cascade,
  term text not null,
  overall_average numeric(5,2),
  class_position text,
  class_teacher_comment text,
  head_teacher_comment text,
  status text default 'draft' check (status in ('draft','published')),
  generated_at timestamptz default now(),
  unique (student_id, term)
);

-- ---------- 9. COMPUTER BASED TESTS (CBT) ----------
create table cbt_tests (
  id uuid primary key default uuid_generate_v4(),
  school_id uuid references schools(id) on delete cascade,
  subject_id uuid references subjects(id),
  class_id uuid references classes(id),
  title text not null,
  duration_minutes int default 30,
  is_published boolean default false,
  created_by uuid references profiles(id),
  created_at timestamptz default now()
);

create table cbt_questions (
  id uuid primary key default uuid_generate_v4(),
  test_id uuid references cbt_tests(id) on delete cascade,
  question_text text not null,
  option_a text, option_b text, option_c text, option_d text,
  correct_option text check (correct_option in ('a','b','c','d')),
  order_index int default 0
);

create table cbt_submissions (
  id uuid primary key default uuid_generate_v4(),
  test_id uuid references cbt_tests(id) on delete cascade,
  student_id uuid references students(id) on delete cascade,
  score numeric(5,2),
  started_at timestamptz default now(),
  submitted_at timestamptz,
  unique (test_id, student_id)
);

create table cbt_answers (
  id uuid primary key default uuid_generate_v4(),
  submission_id uuid references cbt_submissions(id) on delete cascade,
  question_id uuid references cbt_questions(id) on delete cascade,
  selected_option text check (selected_option in ('a','b','c','d')),
  is_correct boolean
);

-- ---------- 10. ANNOUNCEMENTS / EVENTS ----------
create table announcements (
  id uuid primary key default uuid_generate_v4(),
  school_id uuid references schools(id) on delete cascade,
  title text not null,
  body text,
  audience text default 'all' check (audience in ('all','staff','parents','students')),
  event_date date,                          -- null = plain announcement, set = event
  created_by uuid references profiles(id),
  created_at timestamptz default now()
);

-- ---------- 11. LEADS (from the marketing landing page signup form) ----------
create table leads (
  id uuid primary key default uuid_generate_v4(),
  school_name text not null,
  contact_name text,
  phone text,
  email text,
  message text,
  status text default 'new' check (status in ('new','contacted','converted','lost')),
  created_at timestamptz default now()
);

-- ============================================================
-- ROW LEVEL SECURITY
-- Core rule: every table scoped by school_id only exposes rows
-- to profiles belonging to that same school_id (or super_admin).
-- ============================================================

alter table profiles enable row level security;
alter table classes enable row level security;
alter table subjects enable row level security;
alter table class_subject_teachers enable row level security;
alter table students enable row level security;
alter table admissions enable row level security;
alter table student_attendance enable row level security;
alter table teacher_attendance enable row level security;
alter table fee_structures enable row level security;
alter table payments enable row level security;
alter table assessment_scores enable row level security;
alter table report_cards enable row level security;
alter table cbt_tests enable row level security;
alter table cbt_questions enable row level security;
alter table cbt_submissions enable row level security;
alter table cbt_answers enable row level security;
alter table announcements enable row level security;
alter table leads enable row level security;

-- helper: get the school_id of the currently logged-in user
create or replace function auth_school_id() returns uuid as $$
  select school_id from profiles where id = auth.uid();
$$ language sql stable security definer;

-- generic policy pattern applied per table (school-scoped read/write)
create policy "school_scoped_all" on classes for all using (school_id = auth_school_id());
create policy "school_scoped_all" on subjects for all using (school_id = auth_school_id());
create policy "school_scoped_all" on students for all using (school_id = auth_school_id());
create policy "school_scoped_all" on admissions for all using (school_id = auth_school_id());
create policy "school_scoped_all" on student_attendance for all using (school_id = auth_school_id());
create policy "school_scoped_all" on teacher_attendance for all using (school_id = auth_school_id());
create policy "school_scoped_all" on fee_structures for all using (school_id = auth_school_id());
create policy "school_scoped_all" on payments for all using (school_id = auth_school_id());
create policy "school_scoped_all" on assessment_scores for all using (school_id = auth_school_id());
create policy "school_scoped_all" on report_cards for all using (school_id = auth_school_id());
create policy "school_scoped_all" on cbt_tests for all using (school_id = auth_school_id());
create policy "school_scoped_all" on announcements for all using (school_id = auth_school_id());

create policy "self_or_same_school" on profiles for select using (
  id = auth.uid() or school_id = auth_school_id()
);
create policy "self_update" on profiles for update using (id = auth.uid());

-- leads: public can insert (landing page signup), only admins can read
create policy "public_insert_leads" on leads for insert with check (true);
create policy "admin_read_leads" on leads for select using (
  exists (select 1 from profiles where id = auth.uid() and role in ('super_admin','school_admin'))
);
