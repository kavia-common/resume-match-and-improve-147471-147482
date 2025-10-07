-- Optional seed data for demo/testing

-- Ensure schema exists
\i schema.sql

-- Upsert-like inserts using ON CONFLICT to avoid duplicates where possible

-- Users
INSERT INTO public.users (id, email, role)
VALUES
    (gen_random_uuid(), 'alice@example.com', 'job_seeker'),
    (gen_random_uuid(), 'recruiter@company.com', 'recruiter'),
    (gen_random_uuid(), 'coach@university.edu', 'coach')
ON CONFLICT (email) DO UPDATE SET role = EXCLUDED.role;

-- Capture generated/known user IDs for later inserts (use CTEs)
WITH alice AS (
  SELECT id FROM public.users WHERE email = 'alice@example.com' LIMIT 1
), rec AS (
  SELECT id FROM public.users WHERE email = 'recruiter@company.com' LIMIT 1
)
-- Resumes
INSERT INTO public.resumes (user_id, original_file_url, extracted_text, parsed_structured)
SELECT
  (SELECT id FROM alice),
  'https://example.com/resumes/alice.pdf',
  'Experienced data analyst with Python and SQL skills...',
  jsonb_build_object(
    'name','Alice Candidate',
    'skills', jsonb_build_array('Python','SQL','Pandas','Data Visualization'),
    'experience', jsonb_build_array(
      jsonb_build_object('title','Data Analyst','years',3)
    ),
    'education', jsonb_build_array(
      jsonb_build_object('degree','B.Sc. Computer Science')
    )
  )
WHERE NOT EXISTS (
  SELECT 1 FROM public.resumes r WHERE r.user_id = (SELECT id FROM alice)
);

-- Jobs
WITH rec_user AS (
  SELECT id FROM public.users WHERE email = 'recruiter@company.com' LIMIT 1
)
INSERT INTO public.jobs (user_id, title, description_text, parsed_structured)
SELECT
  (SELECT id FROM rec_user),
  'Data Analyst',
  'Looking for a Data Analyst proficient in Python, SQL, and data visualization tools.',
  jsonb_build_object(
    'skills', jsonb_build_array('Python','SQL','Tableau','Pandas'),
    'seniority','mid',
    'location','Remote'
  )
WHERE NOT EXISTS (
  SELECT 1 FROM public.jobs j WHERE j.title = 'Data Analyst'
);

-- Matches
WITH r AS (
  SELECT r.id as resume_id FROM public.resumes r
  JOIN public.users u ON u.id = r.user_id
  WHERE u.email = 'alice@example.com'
  LIMIT 1
),
j AS (
  SELECT id as job_id FROM public.jobs WHERE title = 'Data Analyst' LIMIT 1
)
INSERT INTO public.matches (resume_id, job_id, score, explanation)
SELECT r.resume_id, j.job_id, 87.50,
  jsonb_build_object(
    'reason','Strong overlap in Python and SQL skills; lacking Tableau but has data viz experience',
    'keywords_match', jsonb_build_array('Python','SQL','Pandas')
  )
FROM r, j
ON CONFLICT (resume_id, job_id) DO UPDATE SET
  score = EXCLUDED.score,
  explanation = EXCLUDED.explanation;

-- Suggestions
WITH r AS (
  SELECT r.id as resume_id FROM public.resumes r
  JOIN public.users u ON u.id = r.user_id
  WHERE u.email = 'alice@example.com'
  LIMIT 1
)
INSERT INTO public.suggestions (resume_id, suggestion_text, category, severity)
SELECT r.resume_id, 'Add Tableau to your skills to better match job requirements.', 'skills', 'medium'
FROM r
WHERE NOT EXISTS (
  SELECT 1 FROM public.suggestions s WHERE s.resume_id = r.resume_id AND s.suggestion_text ILIKE 'Add Tableau%'
);

-- Audit log example entries
INSERT INTO public.audit_logs (user_id, action, meta)
SELECT id, 'seed_insert', jsonb_build_object('note','initial seed') FROM public.users
ON CONFLICT DO NOTHING;

-- Done
