-- Resume Match & Improve - PostgreSQL Schema
-- Idempotent schema creation for users, resumes, jobs, matches, suggestions, audit_logs

-- Enable required extensions (idempotent)
CREATE EXTENSION IF NOT EXISTS pgcrypto; -- for gen_random_uuid()
-- Fallback: uncomment if pgcrypto not available in your environment
-- CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- PUBLIC_INTERFACE
-- Users: Application users (job seekers, recruiters, coaches)
CREATE TABLE IF NOT EXISTS public.users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email text UNIQUE NOT NULL,
    role text NOT NULL DEFAULT 'job_seeker' CHECK (role IN ('job_seeker','recruiter','coach')),
    created_at timestamptz NOT NULL DEFAULT now()
);

-- PUBLIC_INTERFACE
-- Resumes: Uploaded resumes and their parsed forms
CREATE TABLE IF NOT EXISTS public.resumes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES public.users(id) ON DELETE CASCADE,
    original_file_url text,
    extracted_text text,
    parsed_structured jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- PUBLIC_INTERFACE
-- Jobs: Job descriptions and parsed forms
CREATE TABLE IF NOT EXISTS public.jobs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
    title text NOT NULL,
    description_text text,
    parsed_structured jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- PUBLIC_INTERFACE
-- Matches: Resume-to-Job matching results
CREATE TABLE IF NOT EXISTS public.matches (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    resume_id uuid REFERENCES public.resumes(id) ON DELETE CASCADE,
    job_id uuid REFERENCES public.jobs(id) ON DELETE CASCADE,
    score numeric(5,2) NOT NULL,
    explanation jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_matches_resume_job UNIQUE (resume_id, job_id)
);

-- PUBLIC_INTERFACE
-- Suggestions: Improvement suggestions for resumes
CREATE TABLE IF NOT EXISTS public.suggestions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    resume_id uuid REFERENCES public.resumes(id) ON DELETE CASCADE,
    suggestion_text text NOT NULL,
    category text,
    severity text NOT NULL DEFAULT 'medium' CHECK (severity IN ('low','medium','high')),
    created_at timestamptz NOT NULL DEFAULT now()
);

-- PUBLIC_INTERFACE
-- Audit Logs: Track user actions and system events
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id bigserial PRIMARY KEY,
    user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
    action text NOT NULL,
    meta jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Indexes
-- JSONB GIN indexes for structured search
CREATE INDEX IF NOT EXISTS idx_resumes_parsed_structured_gin ON public.resumes USING gin (parsed_structured);
CREATE INDEX IF NOT EXISTS idx_jobs_parsed_structured_gin ON public.jobs USING gin (parsed_structured);
CREATE INDEX IF NOT EXISTS idx_matches_explanation_gin ON public.matches USING gin (explanation);

-- BTREE indexes on created_at for common ordering/filtering
CREATE INDEX IF NOT EXISTS idx_users_created_at ON public.users (created_at);
CREATE INDEX IF NOT EXISTS idx_resumes_created_at ON public.resumes (created_at);
CREATE INDEX IF NOT EXISTS idx_jobs_created_at ON public.jobs (created_at);
CREATE INDEX IF NOT EXISTS idx_matches_created_at ON public.matches (created_at);
CREATE INDEX IF NOT EXISTS idx_suggestions_created_at ON public.suggestions (created_at);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON public.audit_logs (created_at);

-- Composite index for match lookups (though unique constraint already creates one, we keep explicit for clarity)
CREATE INDEX IF NOT EXISTS idx_matches_resume_job ON public.matches (resume_id, job_id);

-- Helpful partial indexes for frequent queries (optional - safe if recreated)
-- Example: users by role
CREATE INDEX IF NOT EXISTS idx_users_role ON public.users (role);

-- Data validity helpers (optional)
-- Enforce lowercase emails to ensure uniqueness by canonical form
CREATE OR REPLACE FUNCTION public.normalize_email() RETURNS trigger AS $$
BEGIN
  NEW.email := lower(NEW.email);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_users_normalize_email ON public.users;
CREATE TRIGGER trg_users_normalize_email
BEFORE INSERT OR UPDATE OF email ON public.users
FOR EACH ROW
EXECUTE FUNCTION public.normalize_email();
