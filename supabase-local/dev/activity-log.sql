create table if not exists public.board_activity (
  id bigint generated always as identity primary key,
  board_id uuid references public.boards(id) on delete set null,
  board_name text not null,
  actor_id uuid not null,
  actor_email text not null,
  summary text not null check (char_length(trim(summary)) between 1 and 200),
  created_at timestamptz not null default now()
);

create index if not exists board_activity_board_created_idx
  on public.board_activity (board_id, created_at desc, id desc);

alter table public.board_activity enable row level security;

drop policy if exists "Board members can view activity." on public.board_activity;
create policy "Board members can view activity."
  on public.board_activity for select
  to authenticated
  using (
    (board_id is not null and public.board_access_permission(board_id) in ('owner', 'read', 'write'))
    or (board_id is null and actor_id = auth.uid())
  );

create or replace function public.save_board_with_activity(
  p_board_id uuid,
  p_state jsonb,
  p_summaries jsonb
)
returns table(id uuid,name text,user_id uuid,created_at timestamptz,updated_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  updated_board public.boards%rowtype;
  activity_item jsonb;
  summary_text text;
begin
  if auth.uid() is null or public.board_access_permission(p_board_id) not in ('owner', 'write') then
    raise exception 'You do not have permission to update this board.';
  end if;
  if jsonb_typeof(p_state) <> 'object' or jsonb_typeof(p_summaries) <> 'array' then
    raise exception 'Invalid board activity payload.';
  end if;
  if jsonb_array_length(p_summaries) > 100 then
    raise exception 'Too many activity entries in one save.';
  end if;

  update public.boards as b
  set state = p_state, updated_at = now()
  where b.id = p_board_id
  returning b.* into updated_board;

  if not found then
    raise exception 'Board not found.';
  end if;

  for activity_item in select value from jsonb_array_elements(p_summaries)
  loop
    summary_text := left(trim(activity_item ->> 'summary'), 200);
    if summary_text = '' then
      raise exception 'Activity summary cannot be empty.';
    end if;
    insert into public.board_activity(board_id,board_name,actor_id,actor_email,summary)
    values(p_board_id,updated_board.name,auth.uid(),coalesce(auth.jwt() ->> 'email','Unknown user'),summary_text);
  end loop;

  return query select updated_board.id,updated_board.name,updated_board.user_id,updated_board.created_at,updated_board.updated_at;
end;
$$;

create or replace function public.append_board_activity(p_board_id uuid,p_summary text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  board_row public.boards%rowtype;
  summary_text text := left(trim(p_summary),200);
begin
  if auth.uid() is null or public.board_access_permission(p_board_id) not in ('owner', 'read', 'write') then
    raise exception 'You do not have permission to view this board activity.';
  end if;
  if summary_text is null or summary_text = '' then
    raise exception 'Activity summary cannot be empty.';
  end if;

  select * into board_row from public.boards where id = p_board_id;
  if not found then
    raise exception 'Board not found.';
  end if;

  insert into public.board_activity(board_id,board_name,actor_id,actor_email,summary)
  values(p_board_id,board_row.name,auth.uid(),coalesce(auth.jwt() ->> 'email','Unknown user'),summary_text);
end;
$$;

revoke all on function public.save_board_with_activity(uuid,jsonb,jsonb) from public;
revoke all on function public.append_board_activity(uuid,text) from public;
grant execute on function public.save_board_with_activity(uuid,jsonb,jsonb) to authenticated;
grant execute on function public.append_board_activity(uuid,text) to authenticated;
grant select on public.board_activity to authenticated;
