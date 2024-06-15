create function app_public.logout() returns void as $$
begin
  delete from app_private.sessions where uuid = app_public.current_session_id();

  perform set_config('jwt.claims.session_id', '', true);
end;
$$ language plpgsql security definer volatile;
