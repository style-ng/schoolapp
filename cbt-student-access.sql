-- ============================================================
-- CBT STUDENT ACCESS — run this AFTER schema.sql
-- Adds: missing RLS policies for cbt_questions/submissions/answers
-- (staff dashboard needs these to manage questions), plus
-- SECURITY DEFINER functions so students can take a test via a
-- public link WITHOUT ever seeing correct answers and WITHOUT
-- needing a staff login.
-- ============================================================

-- ---------- 1. Staff (admin) access to CBT tables ----------
-- cbt_questions has no direct school_id column, so scope through
-- its parent test.
create policy "school_scoped_via_test" on cbt_questions for all using (
  exists (select 1 from cbt_tests t where t.id = cbt_questions.test_id and t.school_id = auth_school_id())
);

create policy "admin_read_submissions" on cbt_submissions for select using (
  exists (select 1 from cbt_tests t where t.id = cbt_submissions.test_id and t.school_id = auth_school_id())
);

create policy "admin_read_answers" on cbt_answers for select using (
  exists (
    select 1 from cbt_submissions s
    join cbt_tests t on t.id = s.test_id
    where s.id = cbt_answers.submission_id and t.school_id = auth_school_id()
  )
);

-- allow the on-conflict upsert used by answer_cbt_question below
alter table cbt_answers add constraint cbt_answers_submission_question_unique unique (submission_id, question_id);

-- ---------- 2. Public student-facing functions ----------
-- These run as SECURITY DEFINER, meaning they execute with elevated
-- privileges internally but only ever return the specific safe data
-- defined below — students never get a correct_option value.

-- list the tests currently open for a school (by its public slug)
create or replace function public.list_published_tests(p_school_slug text)
returns jsonb
language plpgsql security definer as $$
declare
  v_school_id uuid;
  v_tests jsonb;
begin
  select id into v_school_id from schools where slug = p_school_slug;
  if v_school_id is null then
    return '[]'::jsonb;
  end if;

  select jsonb_agg(jsonb_build_object('id', id, 'title', title, 'duration_minutes', duration_minutes))
  into v_tests
  from cbt_tests
  where school_id = v_school_id and is_published = true;

  return coalesce(v_tests, '[]'::jsonb);
end;
$$;
grant execute on function public.list_published_tests(text) to anon;

-- start (or resume) a test for a verified student; returns questions
-- WITHOUT their correct_option
create or replace function public.start_cbt(p_test_id uuid, p_admission_number text, p_school_slug text)
returns jsonb
language plpgsql security definer as $$
declare
  v_school_id uuid;
  v_student_id uuid;
  v_test record;
  v_submission_id uuid;
  v_already_submitted timestamptz;
  v_questions jsonb;
begin
  select id into v_school_id from schools where slug = p_school_slug;
  if v_school_id is null then
    raise exception 'School not found';
  end if;

  select id into v_student_id from students
    where school_id = v_school_id and admission_number = p_admission_number;
  if v_student_id is null then
    raise exception 'Student not found — check the admission number';
  end if;

  select * into v_test from cbt_tests
    where id = p_test_id and school_id = v_school_id and is_published = true;
  if v_test.id is null then
    raise exception 'This test is not available';
  end if;

  select id, submitted_at into v_submission_id, v_already_submitted
    from cbt_submissions where test_id = v_test.id and student_id = v_student_id;

  if v_already_submitted is not null then
    raise exception 'This test has already been submitted';
  end if;

  if v_submission_id is null then
    insert into cbt_submissions (test_id, student_id) values (v_test.id, v_student_id)
      returning id into v_submission_id;
  end if;

  select jsonb_agg(jsonb_build_object(
    'id', q.id, 'question_text', q.question_text,
    'option_a', q.option_a, 'option_b', q.option_b,
    'option_c', q.option_c, 'option_d', q.option_d
  ) order by q.order_index)
  into v_questions
  from cbt_questions q where q.test_id = v_test.id;

  return jsonb_build_object(
    'submission_id', v_submission_id,
    'test_title', v_test.title,
    'duration_minutes', v_test.duration_minutes,
    'questions', coalesce(v_questions, '[]'::jsonb)
  );
end;
$$;
grant execute on function public.start_cbt(uuid, text, text) to anon;

-- record one answer; scoring happens server-side, correct_option
-- never leaves the database
create or replace function public.answer_cbt_question(p_submission_id uuid, p_question_id uuid, p_selected_option text)
returns void
language plpgsql security definer as $$
declare
  v_correct text;
begin
  if (select submitted_at from cbt_submissions where id = p_submission_id) is not null then
    raise exception 'This test has already been submitted';
  end if;

  select correct_option into v_correct from cbt_questions where id = p_question_id;

  insert into cbt_answers (submission_id, question_id, selected_option, is_correct)
  values (p_submission_id, p_question_id, p_selected_option, v_correct = p_selected_option)
  on conflict (submission_id, question_id) do update
    set selected_option = excluded.selected_option, is_correct = excluded.is_correct;
end;
$$;
grant execute on function public.answer_cbt_question(uuid, uuid, text) to anon;

-- finalize and return the score (percentage)
create or replace function public.finish_cbt(p_submission_id uuid)
returns numeric
language plpgsql security definer as $$
declare
  v_correct_count int;
  v_total int;
  v_score numeric;
begin
  select count(*) filter (where is_correct), count(*) into v_correct_count, v_total
  from cbt_answers where submission_id = p_submission_id;

  v_score := case when v_total > 0 then round((v_correct_count::numeric / v_total) * 100, 2) else 0 end;

  update cbt_submissions set score = v_score, submitted_at = now() where id = p_submission_id;
  return v_score;
end;
$$;
grant execute on function public.finish_cbt(uuid) to anon;
